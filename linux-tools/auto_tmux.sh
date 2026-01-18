#!/bin/bash

# =================================================================
# 名称: auto_tmux
# 用途: SSH 登录时自动启动 tmux，支持 -i 参数进行安装/手动更新
# 存储路径: ~/bin/auto_tmux
# =================================================================

GITHUB_URL="https://raw.githubusercontent.com/你的用户名/你的仓库名/main/auto_tmux"
SCRIPT_PATH="$HOME/bin/auto_tmux"

# 1. 安装与更新逻辑 (-i 参数触发)
install_or_update() {
    echo "--- 正在执行初始化/更新程序 ---"
    
    # 确保目录存在
    if [ ! -d "$HOME/bin" ]; then
        echo "创建 ~/bin 目录..."
        mkdir -p "$HOME/bin"
    fi

    # 检查远程更新
    echo "检查 GitHub 远程版本..."
    curl -s -L "$GITHUB_URL" -o "${SCRIPT_PATH}.tmp"
    
    if [ -f "${SCRIPT_PATH}.tmp" ]; then
        # 如果本地文件不存在，或者远程文件与本地不同，则覆盖
        if [ ! -f "${SCRIPT_PATH}" ] || ! diff "${SCRIPT_PATH}" "${SCRIPT_PATH}.tmp" >/dev/null 2>&1; then
            echo "发现新版本或首次安装，正在写入 $SCRIPT_PATH ..."
            mv "${SCRIPT_PATH}.tmp" "${SCRIPT_PATH}"
            chmod +x "${SCRIPT_PATH}"
            echo "安装/更新完成。"
        else
            rm -f "${SCRIPT_PATH}.tmp"
            echo "当前已是最新版本。"
        fi
    else
        echo "错误: 无法从 GitHub 获取脚本，请检查网络。"
    fi

    # 确保 tmux 已安装
    ensure_tmux_installed
}

# 2. 检查并安装 tmux 软件
ensure_tmux_installed() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "未检测到 tmux，尝试安装..."
        if [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then
            sudo dnf install -y tmux
        elif [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y tmux
        else
            echo "不支持的操作系统，请手动安装 tmux。"
        fi
    else
        echo "tmux 软件已就绪。"
    fi
}

# 3. 自动 Attach 逻辑 (SSH 登录时静默执行)
run_tmux_logic() {
    # 仅在 SSH 登录且不在已有 tmux 会话中时执行
    if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
        # 如果 tmux 没装，静默模式下不自动安装，避免阻塞登录，仅作提示
        if command -v tmux >/dev/null 2>&1; then
            exec tmux new-session -A -s ssh_session
        else
            echo "提示: tmux 未安装，请运行 'auto_tmux -i' 进行初始化。"
        fi
    fi
}

# =================================================================
# 逻辑入口
# =================================================================

if [ "$1" == "-i" ]; then
    # 带参数时：执行安装、创建目录、更新权限
    install_or_update
else
    # 不带参数时：SSH 登录自动 attach (通常由 .bashrc 调用)
    run_tmux_logic
fi
