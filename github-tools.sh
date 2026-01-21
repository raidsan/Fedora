#!/bin/bash

# ==============================================================================
# 功能: 1. 自安装: 自动识别 curl 下载源并安装到 /usr/local/bin
#       2. 包管理: sudo github-tools <URL> 安装新脚本
#       3. 批量更新: sudo github-tools update (含自身更新)
# ==============================================================================

TOOL_NAME="github-tools"
DEST_PATH="/usr/local/bin/$TOOL_NAME"
META_DIR="/usr/local/bin/github-tools-meta"
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR"

# --- 核心改进：更激进的 URL 追溯 ---
get_download_url() {
    local pid=$$
    # 向上追溯，直到找到包含 curl/wget 的命令行
    while [ "$pid" -gt 1 ]; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] && break
        
        # 扫描父进程的所有后代进程（包括并行的管道进程）
        local cmdlines=$(pgrep -P $ppid | xargs -I {} cat /proc/{}/cmdline 2>/dev/null | tr '\0' ' ')
        
        # 匹配包含脚本特征的 URL，优先匹配 github-tools.sh
        local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | grep "$TOOL_NAME" | head -1)
        # 如果没找到自身，就找任意脚本 URL
        [ -z "$url" ] && url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | head -1)
        
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

# --- 第一阶段：安装/自注册逻辑 ---
# 判断条件：如果当前执行的 $0 不是 DEST_PATH，且是 bash/sh 环境
if [ "$ABS_PATH" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh)$ ]]; then
    if [ "$EUID" -ne 0 ]; then echo "请使用 sudo 执行安装"; exit 1; fi
    
    URL=$(get_download_url)
    
    if [ -n "$URL" ]; then
        echo "检测到下载源: $URL"
        if curl -sL "$URL" -o "$DEST_PATH"; then
            chmod +x "$DEST_PATH"
            save_metadata "$TOOL_NAME" "$URL"
            echo "成功: $TOOL_NAME 已安装至 $DEST_PATH 并注册。"
            exit 0
        fi
    else
        # 保底：如果是在本地运行 sh github-tools.sh
        if [ -f "$0" ] && [[ "$0" == *.sh ]]; then
             cp "$0" "$DEST_PATH"
             chmod +x "$DEST_PATH"
             echo "已从本地文件完成安装。"
             exit 0
        fi
        echo "错误: 无法确定下载 URL 且无法读取标准输入。请尝试: sudo bash github-tools.sh <URL>"
        exit 1
    fi
fi

# --- 第二阶段：常规功能逻辑 (update, list, install URL) ---

# 1. 如果参数是 URL: 安装新脚本
if [[ "$1" =~ ^http ]]; then
    URL="$1"
    NAME=$(basename "$URL" .sh)
    do_install "$NAME" "$URL"
    exit 0
fi

# 2. 如果参数是 update: 批量更新
if [ "$1" == "update" ]; then
    SELF_URL=""
    for vfile in "$META_DIR"/*.version; do
        [ ! -e "$vfile" ] && continue
        NAME=$(basename "$vfile" .version)
        URL=$(sed -n '1p' "$vfile")
        
        if [ "$NAME" == "$TOOL_NAME" ]; then SELF_URL="$URL"; continue; fi
        
        # 简单比对远程 HASH
        REMOTE_H=$(curl -sL "$URL" | sha256sum | cut -d' ' -f1)
        LOCAL_H=$(sed -n '3p' "$vfile")
        if [ "$REMOTE_H" != "$LOCAL_H" ]; then
            do_install "$NAME" "$URL"
        else
            echo "[$NAME] 已是最新。"
        fi
    done
    # 最后更新自己
    if [ -n "$SELF_URL" ]; then
        REMOTE_H=$(curl -sL "$SELF_URL" | sha256sum | cut -d' ' -f1)
        LOCAL_H=$(sha256sum "$DEST_PATH" | cut -d' ' -f1)
        [ "$REMOTE_H" != "$LOCAL_H" ] && do_install "$TOOL_NAME" "$SELF_URL" || echo "[$TOOL_NAME] 已是最新。"
    fi
    exit 0
fi

# 3. 无参数: 列出列表
printf "%-20s %-20s %-s\n" "工具名称" "最后更新时间" "下载来源"
printf "%-20s %-20s %-s\n" "----------------" "-------------------" "--------------------------------"
for vfile in "$META_DIR"/*.version; do
    [ ! -e "$vfile" ] && break
    NAME=$(basename "$vfile" .version)
    printf "%-20s %-20s %-s\n" "$NAME" "$(sed -n '2p' "$vfile")" "$(sed -n '1p' "$vfile")"
done
