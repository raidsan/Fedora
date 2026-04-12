#!/bin/bash

# ==============================================================================
# 名称: ssh_tmux
# 用途: SSH 登录时自动启动/附加 tmux 会话，实现每个会话独立的命令历史缓存。
#       支持第二个参数指定初始路径或启动命令，并在进入交互环境后执行。
# 管理: 建议通过 github-tools 安装/更新
# ==============================================================================

DEST_PATH="/usr/local/bin/ssh_tmux"
GLOBAL_CONF="/etc/profile.d/ssh_tmux.sh"

# --- 核心初始化模块 ---
do_init() {
    echo "--- 开始环境初始化: ssh_tmux ---"
    
    # 1. 依赖检查
    if ! command -v tmux >/dev/null 2>&1; then
        echo "安装依赖: tmux..."
        if command -v dnf >/dev/null 2>&1; then dnf install -y tmux
        elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y tmux
        elif command -v opkg >/dev/null 2>&1; then opkg update && opkg install tmux
        fi
    fi

    # 2. 全局环境变量注入 (迁移至 /etc/profile.d)
    echo "配置全局环境变量: $GLOBAL_CONF"
    
    # 构建配置内容：仅对 Bash 生效
    cat > "$GLOBAL_CONF" << 'EOF'
if [ -n "$BASH_VERSION" ]; then
    # 确保 PROMPT_COMMAND 包含历史实时同步逻辑
    if [[ ! "$PROMPT_COMMAND" =~ "history -a" ]]; then
        export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
    fi
fi
EOF

    chmod 644 "$GLOBAL_CONF"
    echo "✅ 全局配置已写入 $GLOBAL_CONF"
    echo "提示: 新登录的会话将自动生效，当前会话请执行 'source $GLOBAL_CONF'。"
    echo "✅ 初始化流程结束。"
}

# --- 参数解析 ---
case "$1" in
    -init|--init|install)
        [ "$(id -u)" -ne 0 ] && echo "错误: 操作需 root 权限。" && exit 1
        do_init
        exit 0
        ;;
esac

# --- 第一阶段: 兼容性安装逻辑 ---
CURRENT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
if [ "$CURRENT_PATH" != "$DEST_PATH" ] && [[ "$0" != *"bash"* ]]; then
    if [ "$(id -u)" -ne 0 ]; then echo "错误: 安装需 root 权限。"; exit 1; fi
    
    # 1. 部署可执行文件
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    
    # 2. 执行初始化
    "$DEST_PATH" -init
    
    echo "✅ ssh_tmux 全局安装成功。"
    exit 0
fi

# --- 第二阶段: 运行时逻辑 ---
run_tmux() {
    # 不在已有 tmux 会话中时执行
    if [ -z "$TMUX" ]; then
        local identifier=${1:-session}
        local extra_param=$2
        local session_name="ssh_$identifier"
        local hist_dir="$HOME/.tmux_history"
        local session_hist="$hist_dir/ssh_$identifier"
        
        [ ! -d "$hist_dir" ] && mkdir -p "$hist_dir"
        echo "接入会话: $session_name (历史路径: $session_hist)"

        # 构造 Bash 启动脚本：
        # 1. 首先加载全局环境和个人环境
        # 2. 加载该会话专属的历史记录
        # 3. 处理路径跳转或附加命令
        local init_cmd="[ -f /etc/profile ] && . /etc/profile; [ -f ~/.bashrc ] && . ~/.bashrc; "
        init_cmd="${init_cmd} history -r $session_hist 2>/dev/null; "

        if [ -n "$extra_param" ]; then
            if [ -d "$extra_param" ]; then
                init_cmd="${init_cmd} cd \"$extra_param\"; "
            else
                init_cmd="${init_cmd} $extra_param; "
            fi
        fi

        # 使用 bash --rcfile 启动，确保上述命令在交互界面准备就绪后生效
        exec tmux new-session -A -s "$session_name" \
            -e "HISTFILE=$session_hist" \
            "/bin/bash --rcfile <(echo '$init_cmd')"
    else
        echo "tmux会话中, 不要重复运行"
    fi
}

run_tmux "$@"