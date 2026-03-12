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

# 基础目录检查
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR" 2>/dev/null
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# 权限检测
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && SUDO_CMD="sudo"
fi

# 获取下载 URL (实现自注册的核心逻辑)
# 实现逻辑：
# 1. 检查第一个参数 $1 是否看似 URL。
# 2. 若不是，则通过 ps 追溯父进程，读取 /proc/PID/cmdline 获取 curl 管道中的原始链接。
# 3. 正则优化：支持捕获包含 githubusercontent 或 gh-proxy 的脚本链接。
get_download_url() {
    case "$1" in
        http*) echo "$1"; return ;;
    esac
    
    local pid=$$
    for i in 1 2 3 4 5; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        local cmdlines=$(cat /proc/$ppid/cmdline 2>/dev/null | tr '\0' ' ')
        # 优化正则：不再死磕 .sh 结尾，只要包含关键域名和脚本特征即可
        local url=$(echo "$cmdlines" | grep -oE 'https?://[^[:space:]"]+(githubusercontent|github|gh-proxy)[^[:space:]"]+\.sh[^[:space:]"]*' | head -1)
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

# 强制无缓存下载函数
curl_no_cache() {
    local url="$1"
    local output="$2"
    curl -sL -k -H "Cache-Control: no-cache" "$url" -o "$output"
}

# 文档查阅逻辑
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    [ ! -f "$doc_file" ] && echo "错误: 未找到文档 $doc_file" && exit 1

    if command -v glow >/dev/null 2>&1; then
        glow "$doc_file"
    else
        echo "--- 文档内容 ---"
        cat "$doc_file"
    fi
    exit 0
}

# 核心安装/更新逻辑单元 (包含详细日志输出)
do_install() {
    local name="$1"
    local url="$2"
    local tmp_file="/tmp/$name.sh"
    local vfile="$META_DIR/$name.version"

    echo "[INFO] 准备同步工具: $name"
    echo "[INFO] 目标地址: $url"
    
    if ! curl_no_cache "$url" "$tmp_file"; then
        echo "[ERROR] 下载失败，请检查网络或 URL 有效性。"
        return 1
    fi

    if [ ! -s "$tmp_file" ]; then
        echo "[ERROR] 下载的文件为空，同步取消。"
        return 1
    fi

    local new_hash=$(sha256sum "$tmp_file" | awk '{print $1}')
    local old_hash=""
    [ -f "$vfile" ] && old_hash=$(tail -n 1 "$vfile" | cut -f3)

    if [ "$new_hash" = "$old_hash" ] && [ -x "$DEST_DIR/$name" ]; then
        echo "[SKIP] HASH 未改变，已是最新状态。"
        rm -f "$tmp_file"
        return 0
    fi

    echo "[ACTION] 正在部署文件到 $DEST_DIR/$name ..."
    $SUDO_CMD cp "$tmp_file" "$DEST_DIR/$name" || { echo "[ERROR] 拷贝失败，请检查权限。"; return 1; }
    $SUDO_CMD chmod +x "$DEST_DIR/$name"
    
    local m_time=$(date "+%Y-%m-%d %H:%M")
    echo -e "$m_time\t$url\t$new_hash" | $SUDO_CMD tee -a "$vfile" >/dev/null
    
    # 同步配套文档
    local doc_url="${url%.sh}.md"
    echo "[INFO] 尝试同步文档: $doc_url"
    curl_no_cache "$doc_url" "/tmp/$name.md"
    if [ -s "/tmp/$name.md" ]; then
        $SUDO_CMD cp "/tmp/$name.md" "$META_DIR/$name.md"
        echo "[INFO] 文档同步成功。"
    fi

    echo "[SUCCESS] $name 安装/更新完成。"
    rm -f "$tmp_file" "/tmp/$name.md"
}

# --- 业务流程入口 ---

# 调试日志：标识脚本启动
# echo "[DEBUG] 脚本已启动，参数1: '$1', 参数个数: $#"

# 1. 尝试捕获 URL
DETECTED_URL=$(get_download_url "$1")

# 2. 判断是否执行自安装 (逻辑加强)
# 判定逻辑：只要能捕获到 URL，且执行文件名不是最终的目标路径，就强制进入安装逻辑。
if [ -n "$DETECTED_URL" ]; then
    # 检查执行路径，防止在已安装的情况下重复触发安装分支
    if [[ "$0" != "$DEST_PATH" && "$BASH_SOURCE" != "$DEST_PATH" ]]; then
        echo ">>>>> 发现自安装/注册请求 <<<<<"
        do_install "$TOOL_NAME" "$DETECTED_URL"
        exit 0
    fi
fi

# 3. 基础指令
if [ "$1" = "help" ] || [ "$1" = "-v" ]; then
    grep "^# [0-9]." "$0"
    exit 0
fi

if [ "$1" = "-doc" ]; then
    show_doc
fi

# 4. 列出清单 (无参数)
if [ -z "$1" ]; then
    echo "已安装工具列表 ($META_DIR):"
    printf "%-15s %-20s %-6s %-s\n" "TOOL" "LAST_UPDATE" "DOC" "SHA256"
    if [ -d "$META_DIR" ]; then
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && continue
            T_NAME=$(basename "$vfile" .version)
            LAST_LINE=$(tail -n 1 "$vfile")
            m_time=$(echo "$LAST_LINE" | cut -f1)
            T_HASH=$(echo "$LAST_LINE" | cut -f3)
            DOC_STAT="[ ]"; [ -f "$META_DIR/$T_NAME.md" ] && DOC_STAT="[√]"
            printf "%-15s %-20s %-6s %-s\n" "$T_NAME" "$m_time" "$DOC_STAT" "${T_HASH:0:10}"
        done
    fi
    exit 0
fi

# 5. 指令: add
if [ "$1" = "add" ]; then
    [ -z "$2" ] && echo "用法: github-tools add <URL/Path>" && exit 1
    FINAL_URL=$(resolve_url "$2")
    NAME=$(basename "$2" .sh)
    do_install "$NAME" "$FINAL_URL"
    exit 0
fi

# 6. 指令: update
if [ "$1" = "update" ]; then
    if [ -n "$2" ]; then
        VFILE="$META_DIR/$2.version"
        [ ! -f "$VFILE" ] && echo "错误: 工具 $2 未记录 URL" && exit 1
        do_install "$2" "$(tail -n 1 "$VFILE" | cut -f2)"
    else
        echo "正在执行全局更新..."
        for vfile in "$META_DIR"/*.version; do
            [ ! -e "$vfile" ] && continue
            T_NAME=$(basename "$vfile" .version)
            [ "$T_NAME" = "$TOOL_NAME" ] && continue
            URL=$(tail -n 1 "$vfile" | cut -f2)
            do_install "$T_NAME" "$URL"
        done
        # 最后更新自己
        VSELF="$META_DIR/$TOOL_NAME.version"
        [ -f "$VSELF" ] && do_install "$TOOL_NAME" "$(tail -n 1 "$VSELF" | cut -f2)"
    fi
    exit 0
fi

# 捕获未知参数
echo "未知参数: $1"
grep "^# [0-9]." "$0"
exit 1