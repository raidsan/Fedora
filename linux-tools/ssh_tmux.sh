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

# 环境初始化函数
do_init() {
    echo "--- 开始环境初始化: ssh_tmux ---"
    
    # 1. 依赖检查与安装
    if ! command -v tmux >/dev/null 2>&1; then
        echo "安装依赖: tmux..."
        if command -v dnf >/dev/null 2>&1; then dnf install -y tmux
        elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y tmux
        elif command -v opkg >/dev/null 2>&1; then opkg update && opkg install tmux
        fi
    fi

    # 2. 环境变量与历史同步配置 (幂等处理)
    local CONF_FILE="$HOME/.bashrc"
	# 适配 OpenWrt/ash 环境
    [ ! -f "$CONF_FILE" ] && [ -f "$HOME/.profile" ] && CONF_FILE="$HOME/.profile"
    
    if [ -f "$CONF_FILE" ]; then
        local shell_exe=$(readlink -f /proc/$$/exe 2>/dev/null || ps -p $$ -o comm= 2>/dev/null || echo "$SHELL")
        local shell_name=$(basename "$shell_exe")
		
		# 仅针对支持 PROMPT_COMMAND 的 Bash 进行注入
        if [ "$shell_name" = "bash" ]; then
            local line='export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"'
            if ! grep -Fxq "$line" "$CONF_FILE"; then
                echo "$line" >> "$CONF_FILE"
                echo "已向 $CONF_FILE 注入历史实时同步配置。"
            fi
        fi
    fi
    echo "✅ 初始化完成。"
}

# --- 参数解析 ---
case "$1" in
    -init|--init|install)
        [ "$(id -u)" -ne 0 ] && echo "错误: 操作需 root 权限。" && exit 1
        do_init
        exit 0
        ;;
esac

# --- 第一阶段: 兼容性安装逻辑 (非安装路径运行或手动安装时触发) ---
CURRENT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
if [ "$CURRENT_PATH" != "$DEST_PATH" ] && [[ "$0" != *"bash"* ]]; then
    echo "--- 检测到安装/更新需求 ---"
    if [ "$(id -u)" -ne 0 ]; then echo "错误: 安装需 root 权限。"; exit 1; fi
            
    # 1. 部署可执行文件
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
	echo "文件已部署至 $DEST_PATH"
    
    # 2. 调用自身的 init 逻辑完成剩下的依赖检查和环境配置
    "$DEST_PATH" -init
    
    echo "✅ ssh_tmux 完整安装/更新成功。"
    echo ""
    exit 0
fi

# --- 第二阶段: 运行时逻辑 ---
run_tmux() {
    # 仅在交互式终端且不在已有 tmux 会话中时执行
    if [ -z "$TMUX" ] && [ -t 0 ]; then
        local identifier=${1:-session}
        local session_name="ssh_$identifier"
        local hist_dir="$HOME/.tmux_history"
        local session_hist="$hist_dir/ssh_$identifier"
        
		# 确保历史记录目录存在
        [ ! -d "$hist_dir" ] && mkdir -p "$hist_dir"
        echo "接入会话: $session_name (历史路径: $session_hist)"

        # 启动会话并隔离历史文件
        exec tmux new-session -A -s "$session_name" \
            -e "HISTFILE=$session_hist" \
            "history -r $session_hist 2>/dev/null; exec ${SHELL:-/bin/sh}"
    fi
}

run_tmux "$1"