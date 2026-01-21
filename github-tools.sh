#!/bin/bash

# ==============================================================================
# 功能: github-tools 脚本管理器 (Fedora/Linux)
# 1. 安装: curl -sL <URL> | sudo bash -s -- <URL>
# 2. 列出: sudo github-tools (自动修复损坏的元数据)
# 3. 更新: sudo github-tools update
# 元数据格式: 时间 <tab> URL <tab> HASH
# ==============================================================================

TOOL_NAME="github-tools"
DEST_PATH="/usr/local/bin/$TOOL_NAME"
META_DIR="/usr/local/bin/github-tools-meta"
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR"

# 获取下载 URL (优先取参数 $1，其次追溯进程树)
get_download_url() {
    if [[ "$1" =~ ^http ]]; then echo "$1"; return; fi
    local pid=$$
    for i in {1..10}; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        local cmdlines=$(pgrep -P $ppid | xargs -I {} cat /proc/{}/cmdline 2>/dev/null | tr '\0' ' ')
        local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | grep "$TOOL_NAME" | head -1)
        [ -z "$url" ] && url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | head -1)
        [ -n "$url" ] && echo "$url" && return
        pid=$ppid
    done
}

# 记录或追加版本信息 (单行，Tab 分隔)
save_metadata() {
    local name=$1
    local url=$2
    local path="/usr/local/bin/$name"
    local v_file="$META_DIR/$name.version"
    local m_time=$(date '+%Y-%m-%d/%H:%M:%S')
    local m_hash=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)
    
    [ -z "$m_hash" ] && return
    printf "%s\t%s\t%s\n" "$m_time" "$url" "$m_hash" >> "$v_file"
}

# 核心安装/覆盖逻辑
do_install() {
    local name=$1
    local url=$2
    local tmp_file=$(mktemp)
    echo "--- 正在处理: $name ---"
    if curl -sL "$url" -o "$tmp_file"; then
        # 如果是安装自身，直接写入 DEST_PATH；否则执行脚本内的安装逻辑
        if [ "$name" == "$TOOL_NAME" ]; then
            cat "$tmp_file" > "$DEST_PATH" && chmod +x "$DEST_PATH"
        else
            bash "$tmp_file"
        fi
        # 成功后写入/追加元数据
        save_metadata "$name" "$url"
        rm -f "$tmp_file"
        return 0
    else
        echo "错误: 下载失败 $url"
        rm -f "$tmp_file"
        return 1
    fi
}

# --- 第一阶段：安装逻辑 (管道运行) ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "请使用 sudo 运行"; exit 1; fi
    URL=$(get_download_url "$1")
    if [ -n "$URL" ]; then
        do_install "$TOOL_NAME" "$URL"
        echo "github-tools 安装成功。"
    else
        echo "错误: 无法确定下载源。请使用: curl -sL <URL> | sudo bash -s -- <URL>"
        exit 1
    fi
    exit 0
fi

# --- 第二阶段：管理功能 ---

# 1. 安装新工具 (参数为 URL)
if [[ "$1" =~ ^http ]]; then
    do_install "$(basename "$1" .sh)" "$1"
    exit 0
fi

# 2. 批量更新 (update 参数)
if [ "$1" == "update" ]; then
    echo "--- 检查所有脚本更新 ---"
    SELF_URL=""
    for vfile in "$META_DIR"/*.version; do
        [ ! -e "$vfile" ] && continue
        T_NAME=$(basename "$vfile" .version)
        LAST_LINE=$(tail -n 1 "$vfile")
        
        # 健壮性检查：如果行内容不符合 Tab 分隔的三列逻辑，则重建
        T_URL=$(echo "$LAST_LINE" | awk -F'\t' '{print $2}')
        T_HASH=$(echo "$LAST_LINE" | awk -F'\t' '{print $3}')

        if [[ ! "$T_URL" =~ ^http ]] || [ -z "$T_HASH" ]; then
            echo "警告: [$T_NAME] 元数据损坏，尝试重新安装..."
            # 如果没法从损坏的文件抓 URL，就跳过
            continue 
        fi

        if [ "$T_NAME" == "$TOOL_NAME" ]; then SELF_URL="$T_URL"; continue; fi

        # 检查远程 HASH
        REMOTE_HASH=$(curl -sL "$T_URL" | sha256sum | cut -d' ' -f1)
        if [ "$REMOTE_HASH" != "$T_HASH" ]; then
            do_install "$T_NAME" "$T_URL"
        else
            echo "[$T_NAME] 已是最新。"
        fi
    done
    # 自身更新放在最后
    if [ -n "$SELF_URL" ]; then
        CUR_HASH=$(sha256sum "$DEST_PATH" | cut -d' ' -f1)
        REMOTE_HASH=$(curl -sL "$SELF_URL" | sha256sum | cut -d' ' -f1)
        [ "$REMOTE_HASH" != "$CUR_HASH" ] && do_install "$TOOL_NAME" "$SELF_URL" || echo "[$TOOL_NAME] 已是最新。"
    fi
    exit 0
fi

# 3. 列出列表 (无参数)
printf "%-15s %-20s %-45s %-s\n" "工具名称" "更新时间" "最后下载地址" "HASH(部分)"
printf "%-15s %-20s %-45s %-s\n" "---------------" "-------------------" "---------------------------------------------" "----------------"
for vfile in "$META_DIR"/*.version; do
    [ ! -e "$vfile" ] && break
    T_NAME=$(basename "$vfile" .version)
    LAST_LINE=$(tail -n 1 "$vfile")
    
    # 格式化解析
    IFS=$'\t' read -r m_time m_url m_hash <<< "$LAST_LINE"
    
    # 容错处理：如果解析失败
    if [[ ! "$m_url" =~ ^http ]]; then
        printf "%-15s %-20s %-45s %-s\n" "$T_NAME" "METADATA_ERROR" "RE-INSTALL RECOMMENDED" "N/A"
    else
        printf "%-15s %-20s %-45s %-s\n" "$T_NAME" "$m_time" "$m_url" "${m_hash:0:12}..."
    fi
done
