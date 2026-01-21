#!/bin/bash

# ==============================================================================
# 功能: github-tools 脚本管理器
# 1. 安装: curl -sL <URL> | sudo bash -s -- <URL>
# 2. 列出: sudo github-tools
# 3. 更新: sudo github-tools update
# ==============================================================================

TOOL_NAME="github-tools"
DEST_PATH="/usr/local/bin/$TOOL_NAME"
META_DIR="/usr/local/bin/github-tools-meta"
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR"

# 追溯下载 URL 的函数
get_download_url() {
    # 如果参数 $1 是 URL，直接使用（最可靠）
    if [[ "$1" =~ ^http ]]; then echo "$1"; return; fi

    # 否则尝试追溯进程树
    local pid=$$
    for i in {1..10}; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        local cmdlines=$(pgrep -P $ppid | xargs -I {} cat /proc/{}/cmdline 2>/dev/null | tr '\0' ' ')
        local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | grep "$TOOL_NAME" | head -1)
        if [ -n "$url" ]; then echo "$url"; return; fi
        pid=$ppid
    done
}

save_metadata() {
    local name=$1
    local url=$2
    local v_file="$META_DIR/$name.version"
    echo "$url" > "$v_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" >> "$v_file"
    sha256sum "/usr/local/bin/$name" | cut -d' ' -f1 >> "$v_file"
}

# --- 第一阶段：安装逻辑 (当 $0 不是目的地时触发) ---
# 检查是否是在通过管道运行或从非标准位置运行
if [ "$ABS_PATH" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "请使用 sudo 运行"; exit 1; fi

    # 尝试多种手段获取 URL
    URL=$(get_download_url "$1")

    if [ -n "$URL" ]; then
        echo "检测到下载源: $URL"
        # 此时重新下载一份完整版以确保脚本内容完整
        if curl -sL "$URL" -o "$DEST_PATH"; then
            chmod +x "$DEST_PATH"
            save_metadata "$TOOL_NAME" "$URL"
            echo "成功: $TOOL_NAME 已安装至 $DEST_PATH 并注册。"
            exit 0
        fi
    elif [ -f "$0" ] && [[ "$(basename "$0")" == "$TOOL_NAME.sh" ]]; then
        # 本地文件安装保底
        cp "$0" "$DEST_PATH"
        chmod +x "$DEST_PATH"
        echo "已从本地文件完成安装。注意：未注册下载源，无法自动更新。"
        exit 0
    else
        echo "错误: 无法确定下载 URL。"
        echo "请使用: curl -sL <URL> | sudo bash -s -- <URL>"
        exit 1
    fi
fi

# --- 第二阶段：常规包管理逻辑 ---

# 1. 参数为 URL：安装新工具
if [[ "$1" =~ ^http ]] && [ "$1" != "$(sed -n '1p' "$META_DIR/$TOOL_NAME.version" 2>/dev/null)" ]; then
    URL="$1"
    NAME=$(basename "$URL" .sh)
    echo "--- 正在安装新工具: $NAME ---"
    if curl -sL "$URL" | bash; then
        save_metadata "$NAME" "$URL"
        echo "安装完成。"
    fi
    exit 0
fi

# 2. update 参数
if [ "$1" == "update" ]; then
    # ... (之前的 update 逻辑) ...
    exit 0
fi

# 3. 无参数：列出列表
printf "%-20s %-20s %-s\n" "工具名称" "最后更新时间" "下载来源"
printf "%-20s %-20s %-s\n" "----------------" "-------------------" "--------------------------------"
for vfile in "$META_DIR"/*.version; do
    [ ! -e "$vfile" ] && break
    NAME=$(basename "$vfile" .version)
    printf "%-20s %-20s %-s\n" "$NAME" "$(sed -n '2p' "$vfile")" "$(sed -n '1p' "$vfile")"
done
