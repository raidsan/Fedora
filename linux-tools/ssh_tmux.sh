#!/bin/bash

# ==============================================================================
# 名称: ssh_tmux
# 用途: SSH 登录时自动启动/附加 tmux 会话，防止网络断开导致任务中断
# 管理: 建议通过 github-tools 安装/更新
# 用法: 
#   1. 直接运行: ssh_tmux [会话标识]
#   2. 自动触发: 在 .bashrc 中添加 [ -t 0 ] && ssh_tmux
#   3. 远程调用: ssh user@host -t "ssh_tmux [会话标识]"
# ==============================================================================

DEST_PATH="/usr/local/bin/ssh_tmux"

# --- 第一阶段: 安装逻辑 (供 github-tools 使用) ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "ssh_tmux 已成功安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 核心逻辑 ---

ensure_tmux_installed() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "未检测到 tmux，尝试安装..."
        if [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then
            sudo dnf install -y tmux
        elif [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y tmux
        else
            echo "不支持的系统，请手动安装 tmux。"
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
        
        echo "正在接入会话: $session_name ..."
        # -A: 存在则附加，不存在则创建
        exec tmux new-session -A -s "$session_name"
    fi
}

run_tmux "$1"
