#!/bin/bash

# ==============================================================================
# 名称: ssh_tmux
# 用途: SSH 登录时自动启动/附加 tmux 会话，防止网络断开导致任务中断，实现每个会话独立的命令历史缓存
# 管理: 建议通过 github-tools 安装/更新
# 用法: 
#   1. 直接运行: ssh_tmux [会话标识]
#   2. 自动触发: 在 .bashrc 或 .profile 中添加 [ -t 0 ] && ssh_tmux
#   3. 远程调用: ssh user@host -t "ssh_tmux [会话标识]"
# ==============================================================================

DEST_PATH="/usr/local/bin/ssh_tmux"

# --- 第一阶段: 安装逻辑 (含 ash/bash 环境适配) ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    
    # 历史记录配套设置
    CONF_FILE="$HOME/.bashrc"
    [ ! -f "$CONF_FILE" ] && [ -f "$HOME/.profile" ] && CONF_FILE="$HOME/.profile"
    
    # 获取当前 Shell 的名称
    shell_name=$(basename "$(readlink -f /proc/$$/exe 2>/dev/null || ps -p $$ -o comm= 2>/dev/null || echo "$0")" 2>/dev/null)
    
    case "$shell_name" in
        ash|busybox)
            echo "当前是 ash (BusyBox)，不支持 history -a 实时保存"
            echo "提示: 可执行 'opkg install bash' 安装 bash 获得此功能"
            ;;
        bash)   # 如果是 bash，注入实时保存变量
            if [ -f "$CONF_FILE" ] && ! grep -q "history -a" "$CONF_FILE"; then
                echo 'export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"' >> "$CONF_FILE"
            fi
            ;;
        *)
            echo "当前 Shell: $shell_name, 不确定是否支持实时保存"
            ;;
    esac
    
    echo "ssh_tmux 已成功安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 核心逻辑 ---

ensure_tmux_installed() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "未检测到 tmux，尝试安装..."
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y tmux
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y tmux
        elif command -v opkg >/dev/null 2>&1; then
            opkg update && opkg install tmux
        else
            echo "不支持的自动安装环境，请手动安装 tmux。"
            exit 1
        fi
    fi
}

run_tmux() {
    # 仅在交互式终端且不在已有 tmux 会话中时执行
    if [ -z "$TMUX" ] && [ -t 0 ]; then
        ensure_tmux_installed
        
        # 处理会话名：前缀(ssh_) + 会话标识
        local identifier=${1:-session}
        local session_name="ssh_$identifier"
        local hist_dir="$HOME/.tmux_history"
        local session_hist="$hist_dir/ssh_$identifier"
        
        [ ! -d "$hist_dir" ] && mkdir -p "$hist_dir"

        echo "接入会话: $session_name (历史路径: $session_hist)"

        # 针对 ash 和 bash 环境通用处理
        exec tmux new-session -A -s "$session_name" \
            -e "HISTFILE=$session_hist" \
            "history -r $session_hist 2>/dev/null; exec ${SHELL:-/bin/sh}"
    fi
}

run_tmux "$1"