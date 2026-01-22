#!/bin/bash

# ==============================================================================
# 功能: github-tools 脚本管理器
# 1. 帮助: sudo github-tools help / -v
# 2. 列出: github-tools (不带参数)
# 3. 新增: sudo github-tools add <URL> - 安装新脚本并同步 .md 文档
# 4. 更新: sudo github-tools update - 全部更新 (自动检测 HASH 变动并同步文档)
# 5. 文档: 工具存储于 /usr/local/share/github-tools-meta/，支持工具带 -doc 参数查阅
# ==============================================================================

TOOL_NAME="github-tools"
DEST_DIR="/usr/local/bin"
DEST_PATH="$DEST_DIR/$TOOL_NAME"
# 元数据及文档存放至 share 目录
META_DIR="/usr/local/share/github-tools-meta"

# 确保元数据目录存在
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# --- 新增：文档查阅逻辑 ---
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    if [ ! -f "$doc_file" ]; then
        echo "错误: 未找到对应的文档文件 ($doc_file)。"
        exit 1
    fi

    if command -v glow >/dev/null 2>&1; then
        glow "$doc_file"
    elif command -v ghostwriter >/dev/null 2>&1; then
        ghostwriter "$doc_file" &
    else
        echo "--- 文档内容开始 ---"
        cat "$doc_file"
        echo "--- 文档内容结束 ---"
    fi
    echo "" # 结尾空行
    exit 0
}

# 追溯进程树捕获下载 URL
get_download_url() {
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

# 记录版本信息 (记录时间、原始 URL 和 SHA256 哈希)
save_metadata() {
    local name=$1
    local url=$2
    local v_file="$META_DIR/$name.version"
    local m_hash=$(sha256sum "$DEST_DIR/$name" 2>/dev/null | cut -d' ' -f1)
    
    [ -z "$m_hash" ] && return 1
    # 尝试写入，若权限不足则返回失败
    if ! printf "%s\t%s\t%s\n" "$(date '+%Y-%m-%d/%H:%M:%S')" "$url" "$m_hash" >> "$v_file" 2>/dev/null; then
        return 1
    fi
}

# 同步文档逻辑 (探测并下载同名 .md 文件)
sync_document() {
    local name=$1
    local url=$2
    local doc_url="${url%.sh}.md"
    local doc_dest="$META_DIR/$name.md"

    # 只有当远程存在 .md 时才下载
    if curl --output /dev/null --silent --head --fail "$doc_url"; then
        if curl -sL "$doc_url" -o "$doc_dest"; then
            echo "[$name] 说明文档已同步。"
        fi
    fi
}

# 安装/下载核心逻辑 (带执行状态捕获)
do_install() {
    local name=$1
    local url=$2
    local tmp_file=$(mktemp)
    local status=0
    
    echo "--- 正在处理: $name ---"
    if curl -sL "$url" -o "$tmp_file"; then
        if [ "$name" == "$TOOL_NAME" ]; then
            # 针对自身的权限捕获
            if ! { cat "$tmp_file" > "$DEST_PATH" 2>/dev/null && chmod +x "$DEST_PATH" 2>/dev/null; }; then
                echo "错误: 无法写入 $DEST_PATH，请使用 sudo 运行。"
                status=1
            fi
        else
            # 执行子脚本自身的安装逻辑，并捕获其返回码
            if ! bash "$tmp_file"; then
                status=1
            fi
        fi

        # 只有在物理安装成功后，才更新元数据记录和同步文档
        if [ $status -eq 0 ]; then
            if save_metadata "$name" "$url"; then
                sync_document "$name" "$url"
                echo "[$name] 成功完成。"
            else
                echo "错误: 无法保存 [$name] 的版本记录，请使用 sudo 运行。"
                status=1
            fi
        fi
    else
        echo "错误: 下载失败 $url"
        status=1
    fi
    rm -f "$tmp_file"
    return $status
}

# 打印帮助信息
show_help() {
    echo "用法: [sudo] $TOOL_NAME [命令]"
    echo ""
    echo "命令:"
    echo "  (无参数)             列出所有已安装工具、版本及文档状态"
    echo "  help, -v             显示此帮助信息"
    echo "  sudo $TOOL_NAME add <URL>      安装新脚本。如果工具名已存在，则视为更新"
    echo "  sudo $TOOL_NAME update         更新所有已记录的工具 (自动同步文档，最后更新自身)"
    echo "  sudo $TOOL_NAME update <名称>  指定更新某个工具 (使用最后记录的 URL)"
}

# --- 检查 -doc 参数 ---
for arg in "$@"; do
    if [ "$arg" == "-doc" ]; then show_doc; fi
done

# --- 第一阶段: 管道自安装 (检测当前是否处于管道执行状态) ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    URL=$(get_download_url)
    if [ -n "$URL" ]; then
        do_install "$TOOL_NAME" "$URL"
    else
        echo "无法自动确定来源，请通过 'sudo $TOOL_NAME add <URL>' 注册自身"
    fi
    echo ""
    exit 0
fi

# --- 第二阶段: 管理逻辑 ---

# 1. 帮助
if [ "$1" == "help" ] || [ "$1" == "-v" ]; then
    show_help
    echo ""
    exit 0
fi

# 2. 无参数: 查询列表
if [ -z "$1" ]; then
    printf "%-15s %-20s %-10s %-s\n" "工具名称" "最近更新" "文档" "HASH(部分)"
    printf "%-15s %-20s %-10s %-s\n" "---------------" "-------------------" "----------" "----------------"
    if [ -d "$META_DIR" ]; then
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && break
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            IFS=$'\t' read -r m_time m_url m_hash <<< "$LAST_LINE"
            
            # 检查本地是否有 .md 文档
            DOC_STAT="×"
            [ -f "$META_DIR/$T_NAME.md" ] && DOC_STAT="√"
            
            if [[ ! "$m_url" =~ ^http ]]; then
                printf "%-15s %-20s %-10s %-s\n" "$T_NAME" "损坏" "$DOC_STAT" "N/A"
            else
                printf "%-15s %-20s %-10s %-s\n" "$T_NAME" "$m_time" "$DOC_STAT" "${m_hash:0:12}..."
            fi
        done
    fi
    echo ""
    exit 0
fi

# 3. add <URL>
if [ "$1" == "add" ]; then
    if [[ "$2" =~ ^http ]]; then
        NAME=$(basename "$2" .sh)
        do_install "$NAME" "$2"
    else
        echo "错误: add 命令需要提供有效的 URL。"
        show_help; exit 1
    fi
    echo ""
    exit 0
fi

# 4. update
if [ "$1" == "update" ]; then
    if [ -n "$2" ]; then
        # 更新指定工具
        VFILE="$META_DIR/$2.version"
        if [ -f "$VFILE" ]; then
            URL=$(tail -n 1 "$VFILE" | awk -F'\t' '{print $2}')
            do_install "$2" "$URL"
        else
            echo "错误: 未找到工具 [$2] 的版本记录。"
            exit 1
        fi
    else
        echo "--- 检查全部更新 ---"
        SELF_URL=""
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && continue
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            IFS=$'\t' read -r m_time T_URL T_HASH <<< "$LAST_LINE"
            [[ ! "$T_URL" =~ ^http ]] && continue
            if [ "$T_NAME" == "$TOOL_NAME" ]; then SELF_URL="$T_URL"; continue; fi
            REMOTE_H=$(curl -sL "$T_URL" | sha256sum | cut -d' ' -f1)
            if [ "$REMOTE_H" != "$T_HASH" ]; then
                do_install "$T_NAME" "$T_URL"
            else
                echo "[$T_NAME] 已是最新。"
            fi
        done
        
        # 最后执行自更新
        if [ -n "$SELF_URL" ]; then
            read -r CUR_H _ < <(sha256sum "$DEST_PATH")
            REMOTE_H=$(curl -sL "$SELF_URL" | sha256sum | cut -d' ' -f1)
            [ "$REMOTE_H" != "$CUR_H" ] && do_install "$TOOL_NAME" "$SELF_URL" || echo "[$TOOL_NAME] 已是最新。"
        fi
    fi
    echo ""
    exit 0
fi

# 5. 未知参数处理
echo "未知参数: $1"
echo "----------------"
show_help
echo ""
exit 1
