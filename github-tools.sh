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
    echo ""
    exit 0
}

# 获取本地文件修改时间
get_file_mtime() {
    local file=$1
    if [ -f "$file" ]; then
        date -r "$file" "+%Y-%m-%d %H:%M:%S"
    else
        echo "不存在"
    fi
}

# 获取下载 URL (通过追溯进程树捕获 curl | bash 管道中的源链接)
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

# 记录版本信息
save_metadata() {
    local name=$1
    local url=$2
    local v_file="$META_DIR/$name.version"
    local m_hash=$(sha256sum "$DEST_DIR/$name" 2>/dev/null | cut -d' ' -f1)
    
    [ -z "$m_hash" ] && return 1
    if ! printf "%s\t%s\t%s\n" "$(date '+%Y-%m-%d/%H:%M:%S')" "$url" "$m_hash" >> "$v_file" 2>/dev/null; then
        return 1
    fi
}

# 无缓存下载核心 (注入时间戳与请求头屏蔽 GitHub 缓存)
curl_no_cache() {
    local url=$1
    local out=$2
    local sep="?"
    [[ "$url" == *\?* ]] && sep="&"
    local fresh_url="${url}${sep}t=$(date +%s%N)"
    
    curl -sL -H "Pragma: no-cache" -H "Cache-Control: no-cache" "$fresh_url" -o "$out"
}

# 安装/更新核心逻辑 (精简输出版 + 防缓存)
do_install() {
    local name=$1
    local url=$2
    local dest="$DEST_DIR/$name"
    local v_file="$META_DIR/$name.version"
    local tmp_file=$(mktemp)
    
    echo "--- 正在处理: $name ---"
    echo "本地版本时间: $(get_file_mtime "$dest")"
    
    # 1. 提取本地记录信息
    local rec_hash=""
    if [ -f "$v_file" ]; then
        rec_hash=$(tail -n 1 "$v_file" | cut -d$'\t' -f3)
    fi

    # 2. 提取物理文件 Hash
    local cur_hash=""
    [ -f "$dest" ] && cur_hash=$(sha256sum "$dest" | cut -d' ' -f1)

    # 3. 获取远程文件 (使用防缓存下载)
    if ! curl_no_cache "$url" "$tmp_file"; then
        echo "❌ 错误: 下载失败 $url"; rm -f "$tmp_file"; return 1
    fi
    local rem_hash=$(sha256sum "$tmp_file" | cut -d' ' -f1)

    # --- 逻辑判定矩阵 ---
    if [ "$rem_hash" == "$rec_hash" ]; then
        if [ "$cur_hash" == "$rec_hash" ]; then
            echo "没有新版本。"
        else
            echo "⚠️  远程内容未更新，但本地文件已被外部修改，不作处理。"
        fi
        rm -f "$tmp_file"; return 0
    else
        if [ -f "$dest" ] && [ "$cur_hash" != "$rec_hash" ]; then
            echo "⚠️  检测到远程更新，但本地文件已被外部修改。"
            read -p "是否使用远程版本覆盖本地修改？(y/n): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "操作已取消。"
                rm -f "$tmp_file"; return 0
            fi
        else
            echo "检测到新版本。"
        fi

        if cat "$tmp_file" > "$dest" 2>/dev/null; then
            chmod +x "$dest"
            save_metadata "$name" "$url"
            
            # 同步 .md 文档 (同样使用防缓存下载)
            local doc_url="${url%.sh}.md"
            curl_no_cache "$doc_url" "$META_DIR/$name.md" >/dev/null 2>&1
            echo "✅ 已更新。"
        else
            echo "❌ 错误: 无法写入 $dest"
        fi
    fi
    rm -f "$tmp_file"
}

# 打印帮助信息
show_help() {
    echo "用法: [sudo] $TOOL_NAME [命令]"
    echo ""
    echo "命令:"
    echo "  (无参数)             列出所有已安装工具及文档状态"
    echo "  help, -v             显示帮助信息"
    echo "  -doc                 查阅 github-tools 自身说明文档"
    echo "  sudo $TOOL_NAME add <URL>      安装脚本并同步文档"
    echo "  sudo $TOOL_NAME update         更新全部工具"
    echo "  sudo $TOOL_NAME update <名称>  更新指定工具"
}

# 拦截 -doc 参数
for arg in "$@"; do
    if [ "$arg" == "-doc" ]; then show_doc; fi
done

# --- 第一阶段: 管道自安装 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    URL=$(get_download_url)
    if [ -n "$URL" ]; then do_install "$TOOL_NAME" "$URL"
    else echo "无法确定来源，请通过 'sudo $TOOL_NAME add <URL>' 注册自身"; fi
    echo ""; exit 0
fi

# --- 第二阶段: 管理逻辑 ---

if [ "$1" == "help" ] || [ "$1" == "-v" ]; then
    show_help; echo ""; exit 0
fi

if [ -z "$1" ]; then
    printf "%-15s %-20s %-10s %-s\n" "工具名称" "最近更新" "文档" "HASH(部分)"
    printf "%-15s %-20s %-10s %-s\n" "---------------" "-------------------" "----------" "----------------"
    if [ -d "$META_DIR" ]; then
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && break
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            IFS=$'\t' read -r m_time T_URL T_HASH <<< "$LAST_LINE"
            DOC_STAT="×"; [ -f "$META_DIR/$T_NAME.md" ] && DOC_STAT="√"
            printf "%-15s %-20s %-10s %-s\n" "$T_NAME" "$m_time" "$DOC_STAT" "${T_HASH:0:12}..."
        done
    fi
    echo ""; exit 0
fi

if [ "$1" == "add" ]; then
    if [[ "$2" =~ ^http ]]; then
        NAME=$(basename "$2" .sh); do_install "$NAME" "$2"
    else echo "错误: 需要有效 URL。"; fi
    echo ""; exit 0
fi

if [ "$1" == "update" ]; then
    if [ -n "$2" ]; then
        VFILE="$META_DIR/$2.version"
        if [ -f "$VFILE" ]; then
            URL=$(tail -n 1 "$VFILE" | awk -F'\t' '{print $2}')
            do_install "$2" "$URL"
        fi
    else
        SELF_URL=""
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && continue
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            IFS=$'\t' read -r m_time T_URL T_HASH <<< "$LAST_LINE"
            [ "$T_NAME" == "$TOOL_NAME" ] && { SELF_URL="$T_URL"; continue; }
            do_install "$T_NAME" "$T_URL"
        done
        [ -n "$SELF_URL" ] && do_install "$TOOL_NAME" "$SELF_URL"
    fi
    echo ""; exit 0
fi

echo ""
