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

# --- 启动哨兵 (确保任何情况下都有输出) ---
echo "[DEBUG] github-tools 管理器启动..."

# 环境依赖检查
for cmd in curl sha256sum grep awk ps; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "[FATAL] 缺少必要依赖: $cmd，请先安装后再运行。"
        exit 1
    fi
done

# 确保目录存在
mkdir -p "$DEST_DIR" "$META_DIR" 2>/dev/null

# 权限检测
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && SUDO_CMD="sudo"
    [ -z "$SUDO_CMD" ] && echo "[WARN] 当前非 Root 且未找到 sudo，操作可能会失败。"
fi

# 获取下载 URL (实现自注册的核心逻辑)
# 实现逻辑：
# 1. 检查参数 $1 是否为有效的 HTTP 链接。
# 2. 溯源逻辑：通过 ps 命令向上追溯父进程的命令行参数。
# 3. 解析 /proc/[PID]/cmdline，这是解决 curl | bash 无法获取自身 URL 的唯一可靠方案。
get_download_url() {
    # 如果参数 1 本身就是 URL
    if [[ "$1" == http* ]]; then
        echo "$1"
        return
    fi
    
    # 尝试追溯进程树
    local pid=$$
    for i in 1 2 3 4 5; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        
        if [ -f "/proc/$ppid/cmdline" ]; then
            local cmdlines=$(cat "/proc/$ppid/cmdline" 2>/dev/null | tr '\0' ' ')
            # 强化后的正则：匹配 http 开头且包含 .sh 的连续字符串
            local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+\.sh[^[:space:]"]*' | head -1)
            if [ -n "$url" ]; then
                echo "$url"
                return
            fi
        fi
        pid=$ppid
    done
}

# 提取基准 URL (用于支持相对路径添加工具)
get_base_url() {
    local vfile="$META_DIR/$TOOL_NAME.version"
    if [ -f "$vfile" ]; then
        local last_url=$(tail -n 1 "$vfile" | cut -f2)
        echo "${last_url%/*}"
    fi
}

# 解析输入参数 (URL 或 相对路径)
resolve_url() {
    local input=$1
    if [[ "$input" == http* ]]; then
        echo "$input"
    else
        local base=$(get_base_url)
        if [ -z "$base" ]; then
            echo "[ERROR] 无法获取基准路径，请使用完整 URL 进行第一次安装。" >&2
            exit 1
        fi
        echo "$base/${input#*/}"
    fi
}

# 强制跳过缓存的下载
curl_no_cache() {
    curl -sL -k -H "Cache-Control: no-cache" "$1" -o "$2"
}

# 文档查阅逻辑
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    if [ ! -f "$doc_file" ]; then
        echo "[ERROR] 文档未就绪: $doc_file"
        exit 1
    fi
    if command -v glow >/dev/null 2>&1; then
        glow "$doc_file"
    else
        echo "--- DOCUMENTATION ---"
        cat "$doc_file"
    fi
    exit 0
}

# 核心安装逻辑
do_install() {
    local name="$1"
    local url="$2"
    local tmp_sh="/tmp/$name.sh"
    local vfile="$META_DIR/$name.version"

    echo "[INFO] 开始同步: $name"
    echo "[INFO] 来源地址: $url"

    curl_no_cache "$url" "$tmp_sh"
    if [ ! -s "$tmp_sh" ]; then
        echo "[ERROR] 下载失败或文件为空: $url"
        return 1
    fi

    local new_hash=$(sha256sum "$tmp_sh" | awk '{print $1}')
    local old_hash=""
    [ -f "$vfile" ] && old_hash=$(tail -n 1 "$vfile" | cut -f3)

    if [ "$new_hash" = "$old_hash" ] && [ -x "$DEST_DIR/$name" ]; then
        echo "[SKIP] $name 已是最新版本 (SHA: ${new_hash:0:10})"
        rm -f "$tmp_sh"
        return 0
    fi

    echo "[ACTION] 正在部署到 $DEST_DIR/$name ..."
    $SUDO_CMD cp "$tmp_sh" "$DEST_DIR/$name" && $SUDO_CMD chmod +x "$DEST_DIR/$name"
    
    # 记录版本元数据
    local m_time=$(date "+%Y-%m-%d %H:%M")
    echo -e "$m_time\t$url\t$new_hash" | $SUDO_CMD tee -a "$vfile" >/dev/null
    
    # 文档同步
    local doc_url="${url%.sh}.md"
    curl_no_cache "$doc_url" "/tmp/$name.md"
    if [ -s "/tmp/$name.md" ]; then
        $SUDO_CMD cp "/tmp/$name.md" "$META_DIR/$name.md"
        echo "[INFO] 文档同步完成。"
    fi

    echo "[SUCCESS] $name 处理成功。"
    rm -f "$tmp_sh" "/tmp/$name.md"
}

# --- 业务逻辑执行 ---

# 1. 尝试识别 URL (管道安装的关键)
RAW_URL=$(get_download_url "$1")

# 2. 判定安装场景
# 如果能拿到 URL，且当前不是从目的地执行，则强制进入安装流程
if [ -n "$RAW_URL" ]; then
    # 检查是否已经在 bin 目录下正式运行
    if [[ "$0" != "$DEST_PATH" && "$BASH_SOURCE" != "$DEST_PATH" ]]; then
        echo "[INFO] 检测到安装/注册请求，正在处理..."
        do_install "$TOOL_NAME" "$RAW_URL"
        exit 0
    fi
fi

# 3. 处理已知参数
case "$1" in
    help|-v)
        grep "^# [0-9]." "$0"
        exit 0
        ;;
    -doc)
        show_doc
        ;;
    add)
        [ -z "$2" ] && echo "用法: add <URL/Path>" && exit 1
        do_install "$(basename "$2" .sh)" "$(resolve_url "$2")"
        exit 0
        ;;
    update)
        if [ -n "$2" ]; then
            VFILE="$META_DIR/$2.version"
            [ ! -f "$VFILE" ] && echo "[ERROR] 工具 $2 未记录 URL" && exit 1
            do_install "$2" "$(tail -n 1 "$VFILE" | cut -f2)"
        else
            echo "[INFO] 开始全局更新..."
            for vfile in "$META_DIR"/*.version; do
                [ ! -e "$vfile" ] && continue
                T_NAME=$(basename "$vfile" .version)
                [ "$T_NAME" = "$TOOL_NAME" ] && continue
                do_install "$T_NAME" "$(tail -n 1 "$vfile" | cut -f2)"
            done
            # 自身最后更新
            VSELF="$META_DIR/$TOOL_NAME.version"
            [ -f "$VSELF" ] && do_install "$TOOL_NAME" "$(tail -n 1 "$VSELF" | cut -f2)"
        fi
        exit 0
        ;;
esac

# 4. 默认逻辑：无参数时列出工具
if [ -z "$1" ]; then
    echo "--- 已安装工具清单 ---"
    printf "%-15s %-20s %-6s %-s\n" "TOOL" "LAST_UPDATE" "DOC" "SHA256"
    ls "$META_DIR"/*.version >/dev/null 2>&1 || { echo "暂无已安装工具。"; exit 0; }
    for vfile in "$META_DIR"/*.version; do
        [ ! -e "$vfile" ] && continue
        T_NAME=$(basename "$vfile" .version)
        LAST_LINE=$(tail -n 1 "$vfile")
        printf "%-15s %-20s %-6s %-s\n" "$T_NAME" "$(echo "$LAST_LINE" | cut -f1)" \
               "$([ -f "$META_DIR/$T_NAME.md" ] && echo "[√]" || echo "[ ]")" \
               "$(echo "$LAST_LINE" | awk '{print substr($3,1,10)}')"
    done
    exit 0
fi

# 5. 未知参数兜底
echo "[ERROR] 未知指令: $1"
grep "^# [0-9]." "$0"
exit 1