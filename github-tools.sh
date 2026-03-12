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
#       curl -vL $TOOLS_URL |  bash -s -- $TOOLS_URL
# 依赖: curl, sha256sum, grep, awk, ps
# 管理: /usr/local/share/github-tools-meta/
# ==============================================================================

TOOL_NAME="github-tools"
DEST_DIR="/usr/local/bin"
DEST_PATH="$DEST_DIR/$TOOL_NAME"
META_DIR="/usr/local/share/github-tools-meta"

# 初始化环境：创建必要的元数据存储目录
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR" 2>/dev/null
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# 权限检测：判定当前执行者是否为 root，若非 root 则尝试定位 sudo 提权路径
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && SUDO_CMD="sudo"
fi

# 获取下载 URL
# 核心逻辑：实现自注册安装。优先识别第一个位置参数；若为空，则溯源父进程，
# 从 /proc/[PPID]/cmdline 中正则提取 curl 管道中原始的链接地址。
get_download_url() {
    if [[ "$1" == http* ]]; then echo "$1"; return; fi
    
    local pid=$$
    for i in 1 2 3 4 5; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        if [ -f "/proc/$ppid/cmdline" ]; then
            local cline=$(cat "/proc/$ppid/cmdline" 2>/dev/null | tr '\0' ' ')
            local url=$(echo "$cline" | grep -oE 'https?://[^[:space:]"]+(\.sh|github|gh-proxy)[^[:space:]"]*' | head -1)
            [ -n "$url" ] && echo "$url" && return
        fi
        pid=$ppid
    done
}

# 提取基准 URL (Base URL)
# 核心逻辑：解析本地版本库中 github-tools 自身的下载源，剥离文件名，
# 为后续“添加工具”功能提供默认的 GitHub 仓库根路径。
get_base_url() {
    local vfile="$META_DIR/$TOOL_NAME.version"
    [ -f "$vfile" ] && echo "$(tail -n 1 "$vfile" | cut -f2 | rev | cut -d/ -f2- | rev)"
}

# 解析输入参数 (URL 或 相对路径)
# 核心逻辑：支持快捷添加。若输入非 http 链接，则自动与 Base URL 拼接。
resolve_url() {
    local input=$1
    if [[ "$input" == http* ]]; then
        echo "$input"
    else
        local base=$(get_base_url)
        if [ -z "$base" ]; then
            echo "[错误] 无法解析相对路径，Base URL 未就绪。" >&2
            exit 1
        fi
        echo "$base/${input#*/}"
    fi
}

# 文档查阅逻辑
# 核心逻辑：查阅存放在 META_DIR 下的 .md 文档，优先使用 glow 进行美化渲染。
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    [ ! -f "$doc_file" ] && echo "[错误] 未找到文档: $doc_file" && exit 1
    if command -v glow >/dev/null 2>&1; then
        glow "$doc_file"
    else
        echo "--- DOCUMENTATION ---"
        cat "$doc_file"
    fi
    exit 0
}

# 核心安装逻辑单元
# 核心逻辑：下载脚本 -> 空响应检查 -> SHA256 校验更新 -> 权限分发 -> 文档同步同步。
do_install() {
    local name="$1"
    local url="$2"
    local tmp_sh="/tmp/$name.sh"
    local vfile="$META_DIR/$name.version"

    echo ">> 正在处理: $name"
    
    # 移除 -s (静默) 标志，强制回显网络错误原因
    if ! curl -fL -k --connect-timeout 10 -H "Cache-Control: no-cache" "$url" -o "$tmp_sh"; then
        echo "   [致命错误] 网络连接失败。请检查 PVE 到外网的路由（No route to host）。"
        return 1
    fi

    if [ ! -s "$tmp_sh" ]; then
        echo "   [错误] 下载的文件为空。"
        rm -f "$tmp_sh"
        return 1
    fi

    local new_hash=$(sha256sum "$tmp_sh" | awk '{print $1}')
    local old_hash=""
    [ -f "$vfile" ] && old_hash=$(tail -n 1 "$vfile" | cut -f3)

    if [ "$new_hash" = "$old_hash" ] && [ -x "$DEST_DIR/$name" ]; then
        echo "   [信息] 版本已是最新，跳过部署。"
        rm -f "$tmp_sh"
        return 0
    fi

    $SUDO_CMD cp "$tmp_sh" "$DEST_DIR/$name" && $SUDO_CMD chmod +x "$DEST_DIR/$name"
    
    local m_time=$(date "+%Y-%m-%d %H:%M")
    echo -e "$m_time\t$url\t$new_hash" | $SUDO_CMD tee -a "$vfile" >/dev/null
    
    # 同步配套文档 (.md)
    local doc_url="${url%.sh}.md"
    curl -sfL "$doc_url" -o "/tmp/$name.md" && [ -s "/tmp/$name.md" ] && $SUDO_CMD cp "/tmp/$name.md" "$META_DIR/$name.md"

    echo "   [完成] 工具部署成功。"
    rm -f "$tmp_sh" "/tmp/$name.md"
}

# --- 脚本执行入口 ---

# 0. 启动即回显，确认脚本已解析
echo "[BOOT] github-tools 任务就绪"

# 1. 检测是否处于自安装/管道执行场景
RAW_URL=$(get_download_url "$1")
if [ -n "$RAW_URL" ] && [[ "$0" != "$DEST_PATH" && "$BASH_SOURCE" != "$DEST_PATH" ]]; then
    do_install "$TOOL_NAME" "$RAW_URL"
    exit 0
fi

# 2. 分发业务指令
case "$1" in
    help|-v) grep "^# [0-9]." "$0"; exit 0 ;;
    -doc)    show_doc ;;
    add)
        [ -z "$2" ] && echo "用法: add <URL>" && exit 1
        do_install "$(basename "$2" .sh)" "$(resolve_url "$2")"
        exit 0
        ;;
    update)
        if [ -n "$2" ]; then
            VF="$META_DIR/$2.version"
            [ -f "$VF" ] && do_install "$2" "$(tail -n 1 "$VF" | cut -f2)"
        else
            echo "正在扫描全局更新..."
            for v in "$META_DIR"/*.version; do
                [ ! -e "$v" ] && continue
                N=$(basename "$v" .version)
                [ "$N" != "$TOOL_NAME" ] && do_install "$N" "$(tail -n 1 "$v" | cut -f2)"
            done
            # 自身放在最后更新
            VS="$META_DIR/$TOOL_NAME.version"
            [ -f "$VS" ] && do_install "$TOOL_NAME" "$(tail -n 1 "$VS" | cut -f2)"
        fi
        exit 0
        ;;
esac

# 3. 默认逻辑：列出所有已安装工具的状态
if [ -z "$1" ]; then
    printf "%-15s %-20s %-6s %-s\n" "TOOL" "LAST_UPDATE" "DOC" "SHA256"
    for v in "$META_DIR"/*.version; do
        [ ! -e "$v" ] && continue
        L=$(tail -n 1 "$v")
        printf "%-15s %-20s %-6s %-s\n" "$(basename "$v" .version)" "$(echo "$LN" | cut -f1)" \
               "$([ -f "$META_DIR/$(basename "$v" .version).md" ] && echo "[√]" || echo "[ ]")" \
               "$(echo "$L" | awk '{print substr($3,1,10)}')"
    done
    exit 0
fi