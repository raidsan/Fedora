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

# 初始化环境：确保元数据和二进制目录存在
[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR" 2>/dev/null
[ ! -d "$META_DIR" ] && mkdir -p "$META_DIR" 2>/dev/null

# 权限识别逻辑：检测当前运行身份，确定是否需要 sudo 提权
CURRENT_UID=$(id -u)
SUDO_CMD=""
if [ "$CURRENT_UID" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && SUDO_CMD="sudo"
fi

# 获取下载 URL
# 实现逻辑：用于自注册安装。优先识别命令行传参；若无，则追溯进程树读取 /proc/PID/cmdline 
# 捕获管道安装（curl | bash）时的原始下载链接。
get_download_url() {
    if [[ "$1" == http* ]]; then echo "$1"; return; fi
    
    local pid=$$
    for i in 1 2 3 4 5; do
        local ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        if [ -f "/proc/$ppid/cmdline" ]; then
            local cline=$(cat "/proc/$ppid/cmdline" 2>/dev/null | tr '\0' ' ')
            local url=$(echo "$cline" | grep -oE 'https?://[^[:space:]"]+(\.sh|github|gh-proxy)[^[:space:]]*' | head -1)
            [ -n "$url" ] && echo "$url" && return
        fi
        pid=$ppid
    done
}

# 提取基准 URL (Base URL)
# 实现逻辑：提供相对路径解析的根地址。优先读取 github-tools 自身的版本记录；
# 若本地尚无记录（初次安装），则动态利用捕获到的 DETECTED_URL。
get_base_url() {
    local vfile="$META_DIR/$TOOL_NAME.version"
    local raw_url=""
    
    if [ -f "$vfile" ]; then
        raw_url=$(tail -n 1 "$vfile" | cut -f2)
    elif [ -n "$DETECTED_URL" ]; then
        raw_url="$DETECTED_URL"
    fi

    if [ -n "$raw_url" ]; then
        # 剥离文件名，保留目录路径
        echo "$(echo "$raw_url" | rev | cut -d/ -f2- | rev)"
    fi
}

# 解析输入参数 (URL 或 相对路径)
# 实现逻辑：根据工具名或路径合成完整的下载 URL。
# 增加后缀自适应逻辑：支持自动补全 .sh 但避免重复叠加。
resolve_url() {
    local input=$1
    local full_url=""
    
    if [[ "$input" == http* ]]; then
        full_url="$input"
    else
        local base=$(get_base_url)
        if [ -z "$base" ]; then
            echo "错误: 无法确定仓库基准路径。" >&2
            exit 1
        fi
        # 如果输入不带 .sh 且非目录形式，尝试补全后缀
        if [[ "$input" != *.sh ]]; then
            full_url="$base/${input#/}.sh"
        else
            full_url="$base/${input#/}"
        fi
    fi
    echo "$full_url"
}

# 文档查阅逻辑
# 实现逻辑：查阅本地存储的 .md 文档。末尾增加空行以优化终端视读。
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    [ ! -f "$doc_file" ] && echo "错误: 文档未找到。" && exit 1
    command -v glow >/dev/null 2>&1 && glow "$doc_file" || cat "$doc_file"
    echo "" # 交互空行
    exit 0
}

# 核心安装与更新单元
# 实现逻辑：下载 -> 状态码判定 -> HASH 比对 -> 部署 -> 元数据记录 -> 文档同步。
do_install() {
    local raw_name="$1"
    local url="$2"
    # 工具名：提取纯文件名，剥离 .sh 后缀作为本地存储标识
    local safe_name=$(basename "$raw_name" .sh)
    local tmp_sh="/tmp/${safe_name}.sh"
    local vfile="$META_DIR/${safe_name}.version"

    echo ">> 正在同步: $raw_name"

    # 使用 curl 获取 HTTP 响应码，并捕获 stderr 以诊断网络故障
    # 增加 --max-time 防止网络僵死导致脚本挂起
    local curl_err_file="/tmp/github_tools_curl.err"
    local http_code=$(curl -L -k -s -H "Cache-Control: no-cache" \
        --connect-timeout 10 --max-time 30 \
        "$url" -o "$tmp_sh" -w "%{http_code}" 2>"$curl_err_file")
    local exit_status=$?

    # 诊断逻辑：处理 000 或 curl 非零退出码情况（如连接被重置或超时）
    if [ "$exit_status" -ne 0 ] || [ "$http_code" = "000" ]; then
        echo "   [错误] 网络请求失败。可能由于 DNS 污染或连接被重置。"
        echo "   [状态] Exit Code: $exit_status / HTTP Code: $http_code"
        [ -s "$curl_err_file" ] && echo "   [诊断] $(cat "$curl_err_file")"
        rm -f "$tmp_sh" "$curl_err_file"
        return 1
    fi

    if [ "$http_code" -ne 200 ]; then
        echo "   [错误] 服务器响应异常 (HTTP: $http_code): $url"
        rm -f "$tmp_sh" "$curl_err_file"
        return 1
    fi

    # 校验本地文件是否存在及是否为空
    if [ ! -f "$tmp_sh" ]; then
        echo "   [错误] 本地 I/O 错误：文件未能成功创建于 /tmp。"
        rm -f "$curl_err_file"
        return 1
    elif [ ! -s "$tmp_sh" ]; then
        echo "   [错误] 下载失败：远程返回内容为空。"
        rm -f "$tmp_sh" "$curl_err_file"
        return 1
    fi

    local new_hash=$(sha256sum "$tmp_sh" | awk '{print $1}')
    local old_hash=""
    [ -f "$vfile" ] && old_hash=$(tail -n 1 "$vfile" | cut -f3)

    if [ "$new_hash" = "$old_hash" ] && [ -x "$DEST_DIR/$safe_name" ]; then
        echo "   [信息] HASH 无变化，无需更新。"
        rm -f "$tmp_sh" "$curl_err_file"
        return 0
    fi

    # 部署文件并设置执行权限
    $SUDO_CMD cp "$tmp_sh" "$DEST_DIR/$safe_name" && $SUDO_CMD chmod +x "$DEST_DIR/$safe_name"
    
    local m_time=$(date "+%Y-%m-%d %H:%M")
    # 记录元数据：时间 \t URL \t HASH
    echo -e "$m_time\t$url\t$new_hash" | $SUDO_CMD tee -a "$vfile" >/dev/null
    
    # 自动尝试同步配套文档 (.md)
    local doc_url="${url%.sh}.md"
    curl -sfL "$doc_url" -o "/tmp/${safe_name}.md" && [ -s "/tmp/${safe_name}.md" ] && $SUDO_CMD cp "/tmp/${safe_name}.md" "$META_DIR/${safe_name}.md"

    echo "   [成功] $safe_name 同步部署完成。"
    rm -f "$tmp_sh" "/tmp/${safe_name}.md" "$curl_err_file"
}

# --- 程序执行逻辑 ---

# 1. 识别并捕获当前安装源（支持管道模式自注册）
DETECTED_URL=$(get_download_url "$1")

# 2. 判定安装/自注册请求
if [ -n "$DETECTED_URL" ] && [[ "$0" != "$DEST_PATH" && "$BASH_SOURCE" != "$DEST_PATH" ]]; then
    do_install "$TOOL_NAME" "$DETECTED_URL"
    echo "" # 终端视觉优化空行
    exit 0
fi

# 3. 解析具体指令
case "$1" in
    help|-v) 
        grep "^# [0-9]." "$0"
        echo "" # 视觉分隔
        exit 0 
        ;;
    -doc)    
        show_doc 
        ;;
    add)     
        [ -z "$2" ] && echo "用法: add <URL/相对路径>" && exit 1
        # 提取基名并移除 .sh 后缀进行安装
        do_install "$(basename "$2" .sh)" "$(resolve_url "$2")"
        echo "" # 视觉分隔
        exit 0 
        ;;
    update)
        if [ -n "$2" ]; then
            # 识别本地已安装工具：剥离路径和可能输入的 .sh 后缀
            N_IDX=$(basename "$2" .sh)
            VF="$META_DIR/$N_IDX.version"
            if [ -f "$VF" ]; then
                # 针对特定工具的更新逻辑：优先核对本地版本记录中的原始安装链接
                TARGET_URL=$(tail -n 1 "$VF" | cut -f2)
            else
                # 若无记录，尝试按当前输入合成 URL
                TARGET_URL=$(resolve_url "$2")
            fi
            do_install "$N_IDX" "$TARGET_URL"
        else
            echo "正在启动全局同步..."
            for vfile in "$META_DIR"/*.version; do
                [ ! -e "$vfile" ] && continue
                N=$(basename "$vfile" .version)
                [ "$N" = "$TOOL_NAME" ] && continue
                do_install "$N" "$(tail -n 1 "$vfile" | cut -f2)"
            done
            # 管理器自身放在最后同步
            VSELF="$META_DIR/$TOOL_NAME.version"
            [ -f "$VSELF" ] && do_install "$TOOL_NAME" "$(tail -n 1 "$VSELF" | cut -f2)"
        fi
        echo "" # 交互后输出空行，确保命令提示符（Prompt）整洁分隔
        exit 0
        ;;
esac

# 4. 默认列表显示：查阅所有已管理工具的状态
if [ -z "$1" ]; then
    printf "%-15s %-20s %-6s %-s\n" "TOOL" "LAST_UPDATE" "DOC" "SHA256"
    ls "$META_DIR"/*.version >/dev/null 2>&1 || { echo "未发现已管理工具。"; echo ""; exit 0; }
    for vfile in "$META_DIR"/*.version; do
        [ ! -e "$vfile" ] && continue
        L=$(tail -n 1 "$vfile")
        T_NAME=$(basename "$vfile" .version)
        printf "%-15s %-20s %-6s %-s\n" "$T_NAME" "$(echo "$L" | cut -f1)" \
               "$([ -f "$META_DIR/$T_NAME.md" ] && echo "[√]" || echo "[ ]")" \
               "$(echo "$L" | awk '{print substr($3,1,10)}')"
    done
    # 重要：输出列表后的空行，用于保持终端界面的清晰层次感，请勿删除。
    echo ""
    exit 0
fi

# 5. 未知输入兜底
echo "无效指令: $1"
grep "^# [0-9]." "$0"
echo ""
exit 1