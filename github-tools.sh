#!/bin/bash

# ==============================================================================
# 功能: github-tools 脚本管理器 (兼容 Fedora/OpenWrt)
# 1. 帮助: github-tools help / -v  /-doc 查阅md文档
# 2. 列出: github-tools (不带参数)
# 3. 新增: <sudo> github-tools add <URL 或 相对路径>
# 4. 更新: <sudo> github-tools update 全部更新 (自动检测 HASH 变动并同步文档)
# 依赖: curl, sha256sum, grep, awk, ps
# 管理: /usr/local/share/github-tools-meta/
# ==============================================================================

TOOL_NAME="github-tools"
DEST_DIR="/usr/local/bin"
DEST_PATH="$DEST_DIR/$TOOL_NAME"
META_DIR="/usr/local/share/github-tools-meta"

# 确保目录存在
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR" 2>/dev/null
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# 自动设置 PATH 环境变量 (针对 OpenWrt)
setup_path() {
    if ! echo "$PATH" | grep -q "$DEST_DIR"; then
        export PATH="$PATH:$DEST_DIR"
        # 永久写入配置文件
        local profile="/etc/profile"
        if [ -f "$profile" ] && ! grep -q "$DEST_DIR" "$profile"; then
            echo "export PATH=\$PATH:$DEST_DIR" >> "$profile"
            echo "已将 $DEST_DIR 加入 $profile，请执行 'source $profile' 或重新登录。"
        fi
    fi
}

# 检测权限 (兼容 ash)
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    else
        echo "错误: 当前非 root 用户且系统中未找到 sudo。"
        exit 1
    fi
fi

# --- 文档查阅逻辑 ---
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

# 获取自身根 URL (用于拼接相对路径)
get_base_url() {
    local v_file="$META_DIR/$TOOL_NAME.version"
    if [ -f "$v_file" ]; then
        local full_url=$(tail -n 1 "$v_file" | cut -d'	' -f2)
        echo "${full_url%/*}" # 返回去掉文件名的部分
    fi
}

# 解析输入参数 (URL or Path)
resolve_url() {
    local input=$1
    # 兼容 ash 的字符串匹配
    case "$input" in
        http*) echo "$input" ;;
        *)
            local base=$(get_base_url)
            if [ -z "$base" ]; then
                echo "错误: 无法获取根路径，请先使用完整 URL 安装 $TOOL_NAME" >&2
                exit 1
            fi
            echo "$base/${input#*/}"
            ;;
    esac
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
    # 优先从命令行参数获取 (针对 (b)ash -s -- URL)
    case "$1" in
        http*) echo "$1"; return ;;
    esac
    
    # 备选：从进程树捕获
    local pid=$$
    for i in 1 2 3 4 5; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        # OpenWrt cat /proc/pid/cmdline 可能因 busybox 限制不可用，增加 grep 检查
        local cmdlines=$(cat /proc/$ppid/cmdline 2>/dev/null | tr '\0' ' ')
        local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | head -1)
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
    # 使用标准制表符写入
    printf "%s\t%s\t%s\n" "$(date '+%Y-%m-%d/%H:%M:%S')" "$url" "$m_hash" >> "$v_file" 2>/dev/null
}

# 无缓存下载核心 (注入时间戳与请求头屏蔽 GitHub 缓存)
curl_no_cache() {
    local url=$1
    local out=$2
    local sep="?"
    # 检查 URL 是否已包含问号
    echo "$url" | grep -q '?' && sep="&"
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
        rec_hash=$(tail -n 1 "$v_file" | cut -d'	' -f3)
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
    if [ "$rem_hash" = "$rec_hash" ]; then
        if [ "$cur_hash" = "$rec_hash" ]; then
            echo "没有新版本。"
        else
            echo "⚠️  远程内容未更新，但本地文件已被外部修改，不作处理。"
        fi
        rm -f "$tmp_file"; return 0
    else
        if [ -f "$dest" ] && [ "$cur_hash" != "$rec_hash" ]; then
            echo "⚠️  检测到远程更新，但本地文件已被外部修改。"
            printf "是否使用远程版本覆盖本地修改？(y/n): "
            read confirm
            case "$confirm" in
                [Yy]*) ;;
                *) echo "操作已取消。"; rm -f "$tmp_file"; return 0 ;;
            esac
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
    
    # 安装完成后尝试修复路径
    [ "$name" = "$TOOL_NAME" ] && setup_path
}

# 打印帮助信息
show_help() {
    echo "用法: [sudo] $TOOL_NAME [命令]"
    echo ""
    echo "命令:"
    echo "  (无参数)             列出所有已安装工具及文档状态"
    echo "  help, -v             显示帮助信息"
    echo "  -doc                 查阅 github-tools 自身说明文档"
    echo "  sudo $TOOL_NAME add <URL 或 相对路径>      安装脚本并同步文档"
    echo "  sudo $TOOL_NAME update         更新全部工具"
    echo "  sudo $TOOL_NAME update <名称>  更新指定工具"
}

# 拦截 -doc 参数
for arg in "$@"; do
    if [ "$arg" = "-doc" ]; then show_doc; fi
done

# --- 第一阶段: 自注册/安装逻辑优化 ---
CURRENT_REALPATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
IS_PIPE=0
# 使用更兼容的模式匹配检查运行环境
if [ ! -f "$0" ]; then
    IS_PIPE=1
else
    case "$0" in
        *bash*|*sh*|/tmp/*) IS_PIPE=1 ;;
    esac
fi

if [ "$CURRENT_REALPATH" != "$DEST_PATH" ] || [ "$IS_PIPE" -eq 1 ]; then
    setup_path # 运行即尝试修复当前会话 PATH
    URL=$(get_download_url "$1")
    if [ -n "$URL" ]; then
        do_install "$TOOL_NAME" "$URL"
    else
        echo "无法确定来源。建议手动注册: github-tools add <URL>"
    fi
    echo ""
    exit 0
fi

# --- 第二阶段: 管理逻辑 ---

if [ "$1" = "help" ] || [ "$1" = "-v" ]; then
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
            # 兼容 ash 的 IFS 读取
            m_time=$(echo "$LAST_LINE" | cut -d'	' -f1)
            T_URL=$(echo "$LAST_LINE" | cut -d'	' -f2)
            T_HASH=$(echo "$LAST_LINE" | cut -d'	' -f3)
            DOC_STAT="×"; [ -f "$META_DIR/$T_NAME.md" ] && DOC_STAT="√"
            printf "%-15s %-20s %-10s %-s\n" "$T_NAME" "$m_time" "$DOC_STAT" "$(echo $T_HASH | cut -c1-12)..."
        done
    fi
    echo ""; exit 0
fi

if [ "$1" = "add" ]; then
    if [ -n "$2" ]; then
        FINAL_URL=$(resolve_url "$2")
        NAME=$(basename "$FINAL_URL" .sh)
        do_install "$NAME" "$FINAL_URL"
    fi
    echo ""; exit 0
fi

if [ "$1" = "update" ]; then
    if [ -n "$2" ]; then
        VFILE="$META_DIR/$2.version"
        if [ -f "$VFILE" ]; then
            URL=$(tail -n 1 "$VFILE" | cut -d'	' -f2)
            do_install "$2" "$URL"
        fi
    else
        SELF_URL=""
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && continue
            T_NAME=$(basename "$vfile" .version)
            T_URL=$(tail -n 1 "$vfile" | cut -d'	' -f2)
            if [ "$T_NAME" = "$TOOL_NAME" ]; then
                SELF_URL="$T_URL"
                continue
            fi
            do_install "$T_NAME" "$T_URL"
        done
        [ -n "$SELF_URL" ] && do_install "$TOOL_NAME" "$SELF_URL"
    fi
    echo ""; exit 0
fi

echo ""
