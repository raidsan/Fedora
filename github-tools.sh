#!/bin/bash

# ==============================================================================
# 功能: 1. 自安装/自注册: 识别 curl 下载链接并初始化
#       2. 无参数: 列出所有已安装工具及其最后更新时间
#       3. update: 根据元数据批量更新工具 (自身更新放在最后)
#       4. <URL>: 安装新工具或手动指定自身链接
# ==============================================================================

TOOL_NAME="github-tools"
DEST_PATH="/usr/local/bin/$TOOL_NAME"
META_DIR="/usr/local/bin/github-tools-meta"
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR"

# --- 核心改进：追溯下载来源 URL ---
get_download_url() {
    local pid=$$
    local url=""
    # 向上追溯 10 层进程，确保穿透 sudo 和管道
    for i in {1..10}; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        
        # 获取父进程及其兄弟进程的命令行
        # 在管道 curl | sh 中，curl 通常是 sh 的兄弟进程或父进程的子进程
        # 扫描该父进程下的所有子进程命令行
        local cmdlines=$(pgrep -P $ppid | xargs -I {} cat /proc/{}/cmdline 2>/dev/null | tr '\0' ' ')
        
        url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+' | grep "\.sh" | head -1)
        if [ -n "$url" ]; then echo "$url"; return; fi
        pid=$ppid
    done
}

# --- 内部函数: 记录版本元数据 ---
save_metadata() {
    local name=$1
    local url=$2
    local v_file="$META_DIR/$name.version"
    echo "$url" > "$v_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" >> "$v_file"
    sha256sum "/usr/local/bin/$name" | cut -d' ' -f1 >> "$v_file"
}

# --- 内部函数: 执行脚本安装 ---
do_install() {
    local name=$1
    local url=$2
    echo "--- 正在安装/更新工具: $name ---"
    # 下载内容到临时文件，防止脚本在执行过程中被改写导致中断
    local tmp_file=$(mktemp)
    if curl -sL "$url" -o "$tmp_file"; then
        bash "$tmp_file"  # 执行脚本自身的安装逻辑
        save_metadata "$name" "$url"
        rm -f "$tmp_file"
        return 0
    else
        echo "错误: $name 下载失败。"
        return 1
    fi
}

# --- 第一阶段: 处理 curl 管道直接运行的“自安装”情况 ---
if [[ "$0" == *"bash"* ]] || [[ "$0" == *"sh"* ]]; then
    if [ "$EUID" -ne 0 ]; then echo "请使用 sudo 运行"; exit 1; fi
    
    # 改进点：判断 $0 是否为有效文件，如果不是，则从 stdin 读取
    if [ -f "$0" ]; then
        cat "$0" > "$DEST_PATH"
    else
        # 此时脚本内容在内存中，由于是在 sudo bash 环境，
        # 我们利用一个临时变量或重定向来保存内容
        # 在管道执行时，最稳妥的方法是再次使用追溯到的 URL 进行下载自存
        URL=$(get_download_url)
        if [ -n "$URL" ]; then
            curl -sL "$URL" -o "$DEST_PATH"
        else
            # 如果实在没法追溯 URL，提示用户手动保存
            echo "错误: 管道模式下无法读取自身文件且未检测到 URL。请手动安装。"
            exit 1
        fi
    fi
    
    chmod +x "$DEST_PATH"
    
    # 记录元数据
    if [ -n "$URL" ]; then
        save_metadata "$TOOL_NAME" "$URL"
        echo "检测到下载来源并已注册: $URL"
    fi
    echo "github-tools 已安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 已安装后的正常功能逻辑 ---

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
