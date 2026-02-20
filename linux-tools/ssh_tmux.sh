#!/bin/bash

# ==============================================================================
# 名称: ssh_tmux
# 用途: SSH 登录时自动启动/附加 tmux 会话，防止网络断开导致任务中断，实现每个会话独立的命令历史缓存
# 依赖: tmux, bash/ash
# 管理: 建议通过 github-tools 安装/更新
# 用法: 
#   1. 直接运行: ssh_tmux [会话标识]
#   2. 自动触发: 在 .bashrc 或 .profile 中添加 [ -t 0 ] && ssh_tmux
#   3. 远程调用: ssh user@host -t "ssh_tmux [会话标识]"
# ==============================================================================

DEST_PATH="/usr/local/bin/ssh_tmux"

# 依赖检查函数 (安装与运行阶段共用)
ensure_tmux_installed() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "检测到缺失 tmux 依赖，开始执行安装..."
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y tmux
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y tmux
        elif command -v opkg >/dev/null 2>&1; then
            opkg update && opkg install tmux
        else
            echo "错误: 无法识别的包管理器，请手动安装 tmux。"
            exit 1
        fi
        echo "tmux 安装完成。"
    fi
}

# --- 第一阶段: 安装/更新逻辑 ---
# 判定条件：不在目标路径运行，或者是通过管道/临时目录运行
CURRENT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
if [ "$CURRENT_PATH" != "$DEST_PATH" ]; then
    # 权限检查 (OpenWrt root 适配)
    if [ "$(id -u)" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    
    echo "--- 开始安装/更新 ssh_tmux ---"
    
    # 1. 强制检查并安装依赖 (确保更新时依赖同步安装)
    ensure_tmux_installed
    
    # 2. 部署可执行文件
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    
    # 3. 环境变量与历史同步配置 (幂等处理)
    CONF_FILE="$HOME/.bashrc"
    [ ! -f "$CONF_FILE" ] && [ -f "$HOME/.profile" ] && CONF_FILE="$HOME/.profile"
    
    if [ -f "$CONF_FILE" ]; then
        shell_exe=$(readlink -f /proc/$$/exe 2>/dev/null || ps -p $$ -o comm= 2>/dev/null || echo "$SHELL")
        shell_name=$(basename "$shell_exe")
        
        if [ "$shell_name" = "bash" ]; then
            line_to_add='export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"'
            # 只有不存在时才写入，防止重复定义
            if ! grep -Fxq "$line_to_add" "$CONF_FILE"; then
                echo "$line_to_add" >> "$CONF_FILE"
                echo "已在 $CONF_FILE 中配置历史记录实时同步。"
            fi
        fi
    fi
    
    echo "✅ ssh_tmux 已成功安装/更新至 $DEST_PATH"
    echo ""
    exit 0
fi

# --- 第二阶段: 运行时逻辑 ---

run_tmux() {
    # 仅在交互式终端且不在已有 tmux 会话中时执行
    if [ -z "$TMUX" ] && [ -t 0 ]; then
        # 运行时兜底检查，防止 tmux 被意外卸载
        ensure_tmux_installed
        
        local identifier=${1:-session}
        local session_name="ssh_$identifier"
        local hist_dir="$HOME/.tmux_history"
        local session_hist="$hist_dir/ssh_$identifier"
        
        [ ! -d "$hist_dir" ] && mkdir -p "$hist_dir"

        echo "接入会话: $session_name (历史路径: $session_hist)"

        # 启动会话并隔离历史文件
        exec tmux new-session -A -s "$session_name" \
            -e "HISTFILE=$session_hist" \
            "history -r $session_hist 2>/dev/null; exec ${SHELL:-/bin/sh}"
    fi
}

run_tmux "$1"