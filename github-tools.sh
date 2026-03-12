#!/bin/bash

# ==============================================================================
# 功能: github-tools 脚本管理器 (兼容 Fedora/OpenWrt/Debian)
# 1. 帮助: github-tools help / -v  
#                     -doc 查阅相关的md文档
# 2. 列出: github-tools (不带参数)
# 3. 新增: <sudo> github-tools add <URL 或 相对路径>
# 4. 更新: <sudo> github-tools update 全部更新 (自动检测 HASH 变动并同步文档)
# 5. 支持从网站下载进行自身注册安装:
#       export TOOLS_URL=https://gh-proxy.com/raw.githubusercontent.com/raidsan/Fedora/refs/heads/main/github-tools.sh
#       curl -sL $TOOLS_URL |  bash -s -- $TOOLS_URL
# 依赖: curl, sha256sum, grep, awk, ps
# 管理: /usr/local/share/github-tools-meta/
# ==============================================================================

TOOL_NAME="github-tools"
DEST_DIR="/usr/local/bin"
DEST_PATH="$DEST_DIR/$TOOL_NAME"
META_DIR="/usr/local/share/github-tools-meta"

# 确保必要的系统目录存在
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR" 2>/dev/null
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# 权限检测：判定是否具备 root 权限或存在 sudo 提权路径
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && SUDO_CMD="sudo"
fi

# 获取下载 URL (实现自注册的核心逻辑)
# 实现逻辑：
# 1. 优先检查命令行传入的第一个参数是否为 URL。
# 2. 若无参数，则向上追溯进程树（最多5层），读取父进程的 /proc/PID/cmdline。
# 3. 利用正则从中提取 HTTP/HTTPS 链接，解决 curl | bash 管道执行时的源定位问题。
get_download_url() {
    case "$1" in
        http*) echo "$1"; return ;;
    esac
    
    local pid=$$
    for i in 1 2 3 4 5; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        local cmdlines=$(cat /proc/$ppid/cmdline 2>/dev/null | tr '\0' ' ')
        local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh' | head -1)
        if [ -n "$url" ]; then
            echo "$url"
            return
        fi
        pid=$ppid
    done
}

# 提取基准 URL (用于支持相对路径添加工具)
get_base_url() {
    local vfile="$META_DIR/$TOOL_NAME.version"
    if [ -f "$vfile" ]; then
        local full_url=$(tail -n 1 "$vfile" | cut -f2)
        echo "${full_url%/*}"
    fi
}

# 解析输入参数 (URL 或 相对路径)
# 实现逻辑：支持添加工具时仅输入仓库内的相对路径，系统自动补全 Base URL。
resolve_url() {
    local input=$1
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

# 绕过服务器缓存的下载工具
curl_no_cache() {
    local url="$1"
    local output="$2"
    curl -sL -H "Cache-Control: no-cache" "$url" -o "$output"
}

# 文档查阅逻辑
# 实现逻辑：支持调用渲染器（glow/ghostwriter）查看工具配套的 .md 文档。
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

# 核心安装/更新逻辑单元
# 实现逻辑：下载脚本 -> HASH 比对 -> 部署 -> 同步文档 -> 记录版本。
do_install() {
    local name="$1"
    local url="$2"
    local tmp_file="/tmp/$name.sh"
    local vfile="$META_DIR/$name.version"

    if [ -z "$url" ]; then
        echo "错误: 无法获取有效的下载链接。"
        return 1
    fi

    echo ">> 正在同步: $name"
    echo "   来源: $url"
    
    if ! curl_no_cache "$url" "$tmp_file"; then
        echo "   错误: 文件下载失败。"
        return 1
    fi

    local new_hash=$(sha256sum "$tmp_file" | awk '{print $1}')
    local old_hash=""
    [ -f "$vfile" ] && old_hash=$(tail -n 1 "$vfile" | cut -f3)

    if [ "$new_hash" = "$old_hash" ] && [ -x "$DEST_DIR/$name" ]; then
        echo "   状态: 已是最新版本 (HASH: ${new_hash:0:10})。"
        rm -f "$tmp_file"
        return 0
    fi

    $SUDO_CMD cp "$tmp_file" "$DEST_DIR/$name"
    $SUDO_CMD chmod +x "$DEST_DIR/$name"
    
    local m_time=$(date "+%Y-%m-%d %H:%M")
    echo -e "$m_time\t$url\t$new_hash" | $SUDO_CMD tee -a "$vfile" >/dev/null
    
    local doc_url="${url%.sh}.md"
    curl_no_cache "$doc_url" "/tmp/$name.md"
    if [ -s "/tmp/$name.md" ]; then
        $SUDO_CMD cp "/tmp/$name.md" "$META_DIR/$name.md"
    fi

    echo "   成功: $name 已安装至 $DEST_DIR"
    rm -f "$tmp_file" "/tmp/$name.md"
}

# --- 业务流程入口 ---

# 1. 捕获自安装请求
# 实现逻辑：优先识别传参或进程树中的 URL。
DETECTED_URL=$(get_download_url "$1")

# 2. 执行路径判定逻辑
# 如果当前运行的文件不是已安装的正式路径，且拿到了 URL，则视为正在执行安装/注册。
if [ -n "$DETECTED_URL" ] && [ "$BASH_SOURCE" != "$DEST_PATH" ] && [ "$0" != "$DEST_PATH" ]; then
    do_install "$TOOL_NAME" "$DETECTED_URL"
    exit 0
fi

# 3. 基础指令处理
if [ "$1" = "help" ] || [ "$1" = "-v" ]; then
    grep "^# [0-9]." "$0"
    exit 0
fi

if [ "$1" = "-doc" ]; then
    show_doc
fi

# 4. 无参数：列出已安装工具
if [ -z "$1" ]; then
    printf "%-15s %-20s %-6s %-s\n" "TOOL" "LAST_UPDATE" "DOC" "SHA256"
    if [ -d "$META_DIR" ]; then
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && break
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            m_time=$(echo "$LAST_LINE" | cut -f1)
            T_HASH=$(echo "$LAST_LINE" | cut -f3)
            DOC_STAT="[ ]"; [ -f "$META_DIR/$T_NAME.md" ] && DOC_STAT="[√]"
            printf "%-15s %-20s %-6s %-s\n" "$T_NAME" "$m_time" "$DOC_STAT" "${T_HASH:0:10}"
        done
    fi
    echo ""; exit 0
fi

# 5. 指令：add
if [ "$1" = "add" ]; then
    if [ -n "$2" ]; then
        FINAL_URL=$(resolve_url "$2")
        NAME=$(basename "$2" .sh)
        do_install "$NAME" "$FINAL_URL"
    else
        echo "用法: $TOOL_NAME add <URL/Path>"
    fi
    exit 0
fi

# 6. 指令：update
if [ "$1" = "update" ]; then
    if [ -n "$2" ]; then
        VFILE="$META_DIR/$2.version"
        [ -f "$VFILE" ] && do_install "$2" "$(tail -n 1 "$VFILE" | cut -f2)"
    else
        echo "开始检查更新..."
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && continue
            T_NAME=$(basename "$vfile" .version)
            [ "$T_NAME" = "$TOOL_NAME" ] && continue
            URL=$(tail -n 1 "$vfile" | cut -f2)
            do_install "$T_NAME" "$URL"
        done
        VSELF="$META_DIR/$TOOL_NAME.version"
        [ -f "$VSELF" ] && do_install "$TOOL_NAME" "$(tail -n 1 "$VSELF" | cut -f2)"
    fi
    exit 0
fi