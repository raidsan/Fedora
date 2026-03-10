# 源码文件名: github-tools.sh

#!/bin/bash

# ==============================================================================
# 功能: github-tools 脚本管理器 (兼容 Fedora/OpenWrt/Debian)
# 1. 帮助: github-tools help / -v  /-doc 查阅md文档
# 2. 列出: github-tools (不带参数)
# 3. 新增: <sudo> github-tools add <URL 或 相对路径>
# 4. 更新: <sudo> github-tools update 全部更新 (自动检测 HASH 变动并同步文档)
# 依赖: curl, sha256sum, grep, awk
# 管理: /usr/local/share/github-tools-meta/
# ==============================================================================

TOOL_NAME="github-tools"
DEST_DIR="/usr/local/bin"
DEST_PATH="$DEST_DIR/$TOOL_NAME"
META_DIR="/usr/local/share/github-tools-meta"

# 确保目录存在 (带权限尝试)
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR" 2>/dev/null
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# 检测权限与 sudo 命令 (兼容 ash/dash)
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    else
        # 预检：如果后面需要执行 add/update 而又没权限，此处不报错，留给具体操作时判断
        SUDO_CMD="" 
    fi
fi

# 检查目标目录是否可写
check_write_permission() {
    if [ ! -w "$DEST_DIR" ] || [ ! -w "$META_DIR" ]; then
        if [ -z "$SUDO_CMD" ] && [ "$CURRENT_UID" -ne 0 ]; then
            echo "错误: 对 $DEST_DIR 或 $META_DIR 无写权限，且系统中未找到 sudo。"
            exit 1
        fi
    fi
}

# 自动设置 PATH 环境变量
setup_path() {
    if ! echo "$PATH" | grep -q "$DEST_DIR"; then
        export PATH="$PATH:$DEST_DIR"
        # 永久写入配置文件
        local profile="/etc/profile"
        if [ -f "$profile" ] && ! grep -q "$DEST_DIR" "$profile"; then
            echo "export PATH=\"\$PATH:$DEST_DIR\"" >> "$profile"
            echo "已将 $DEST_DIR 加入 $profile，请执行 'source $profile' 或重新登录。"
        fi
    fi
}

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
        local full_url=$(tail -n 1 "$v_file" | cut -f2)
        echo "${full_url%/*}"
    fi
}

# 无缓存下载逻辑
curl_no_cache() {
    local url="$1"
    local out="$2"
    local sep="?"
    echo "$url" | grep -q '?' && sep="&"
    local fresh_url="${url}${sep}t=$(date +%s%N)"
    
    curl -sL --fail -H "Pragma: no-cache" -H "Cache-Control: no-cache" "$fresh_url" -o "$out"
}

# 自动解析 URL
resolve_url() {
    local input="$1"
    # POSIX 兼容的字符串开头检查
    case "$input" in
        http*) echo "$input" ; return ;;
    esac

    local main_url=$(get_base_url)
    if [ -z "$main_url" ]; then
        echo "错误: 无法确定 Main URL，请先通过 URL 安装 github-tools。" >&2
        exit 1
    fi
    echo "${main_url}/${input}"
}

# 执行安装/更新逻辑
do_install() {
    local name="$1"
    local url="$2"
    local vfile="$META_DIR/$name.version"
    local tmp_file="/tmp/$name.sh.tmp"
    local tmp_md="/tmp/$name.md.tmp"

    check_write_permission

    echo "--- 正在处理: $name ---"

    if ! curl_no_cache "$url" "$tmp_file"; then
        echo "错误: 无法下载脚本 (可能是 404): $url"
        return 1
    fi

    local new_hash=$(sha256sum "$tmp_file" | awk '{print $1}')
    local old_hash=""
    [ -f "$vfile" ] && old_hash=$(tail -n 1 "$vfile" | cut -f3)

    if [ -f "$DEST_DIR/$name" ]; then
        local current_hash=$(sha256sum "$DEST_DIR/$name" | awk '{print $1}')
        if [ "$current_hash" != "$old_hash" ] && [ "$current_hash" != "$new_hash" ]; then
             echo "本地版本时间: $(ls -l --time-style=+"%Y-%m-%d %H:%M:%S" "$DEST_DIR/$name" | awk '{print $6, $7}')"
             echo "⚠️  检测到远程更新，但本地文件已被外部修改。"
             printf "是否使用远程版本覆盖本地修改？(y/n): "
             read confirm
             if [ "$confirm" != "y" ]; then
                 echo "跳过 $name。"
                 rm -f "$tmp_file"
                 return 0
             fi
        fi
    fi

    $SUDO_CMD mv "$tmp_file" "$DEST_DIR/$name"
    $SUDO_CMD chmod +x "$DEST_DIR/$name"

    local md_url="${url%.sh}.md"
    if curl_no_cache "$md_url" "$tmp_md"; then
        $SUDO_CMD mv "$tmp_md" "$META_DIR/$name.md"
    else
        rm -f "$tmp_md" 2>/dev/null
    fi

    # 使用 printf 避免 echo -e 在不同 shell 下的歧义
    local version_line="$(date +'%Y-%m-%d/%H:%M:%S')\t$url\t$new_hash"
    printf "%b\n" "$version_line" | $SUDO_CMD tee -a "$vfile" > /dev/null

    if grep -q "\-init" "$DEST_DIR/$name"; then
        "$DEST_DIR/$name" -init
    fi

    echo "✅ $name 已完成更新与初始化。"
}

# --- 主程序逻辑 ---

# 自注册逻辑 (处理参数为 URL 的情况)
case "$1" in
    http*) do_install "$TOOL_NAME" "$1" ; exit 0 ;;
esac

if [ "$1" = "help" ] || [ "$1" = "-v" ] || [ "$1" = "--help" ]; then
    grep "^#" "$0" | head -n 15
    exit 0
fi

if [ "$1" = "-doc" ]; then
    show_doc
fi

if [ -z "$1" ]; then
    echo "已安装工具列表 (位置: $META_DIR):"
    printf "%-15s %-20s %-10s %-s\n" "名称" "最后更新时间" "文档" "SHA256(前12位)"
    echo "----------------------------------------------------------------------------"
    if [ -d "$META_DIR" ]; then
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && break
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            m_time=$(echo "$LAST_LINE" | cut -f1)
            T_HASH=$(echo "$LAST_LINE" | cut -f3)
            DOC_STAT="×"; [ -f "$META_DIR/$T_NAME.md" ] && DOC_STAT="√"
            printf "%-15s %-20s %-10s %-s\n" "$T_NAME" "$m_time" "$DOC_STAT" "$(echo "$T_HASH" | cut -c1-12)"
        done
    fi
    echo ""; exit 0
fi

if [ "$1" = "add" ]; then
    if [ -n "$2" ]; then
        # 1. 解析出完整的 URL
        FINAL_URL=$(resolve_url "$2")
        # 2. 从输入中提取文件名（如 linux-tools/ssh_tmux.sh -> ssh_tmux）
        NAME=$(basename "$2" .sh)
        do_install "$NAME" "$FINAL_URL"
    fi
    echo ""; exit 0
fi

if [ "$1" = "update" ]; then
    if [ -n "$2" ]; then
        VFILE="$META_DIR/$2.version"
        if [ -f "$VFILE" ]; then
            URL=$(tail -n 1 "$VFILE" | cut -f2)
            do_install "$2" "$URL"
        else
            echo "错误: 工具 $2 未安装。"
        fi
    else
        for vfile in "$META_DIR"/*.version; do
            T_NAME=$(basename "$vfile" .version)
            [ "$T_NAME" = "$TOOL_NAME" ] && continue
            URL=$(tail -n 1 "$vfile" | cut -f2)
            do_install "$T_NAME" "$URL"
        done
        VFILE="$META_DIR/$TOOL_NAME.version"
        if [ -f "$VFILE" ]; then
            URL=$(tail -n 1 "$VFILE" | cut -f2)
            do_install "$TOOL_NAME" "$URL"
        fi
    fi
    echo ""; exit 0
fi

setup_path