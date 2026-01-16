#!/bin/bash

# --- 1. 配置信息 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_pull"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"
PREFIX="ollama.m.daocloud.io/library/"
DELAY=5

# --- 2. 自动化安装逻辑 ---
install_logic() {
    # 确保 ~/bin 目录存在
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
        echo "📁 已创建目录: $INSTALL_DIR"
    fi

    # 将当前执行的内容写入到目标文件
    # 注意：从 stdin 读取内容并保存，这样 curl 执行时也能安装自己
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash
PREFIX="ollama.m.daocloud.io/library/"
DELAY=5

if [ $# -eq 0 ]; then
    echo "使用方法: ollama_pull <模型名1> <模型名2> ..."
    exit 1
fi

for INPUT in "$@"; do
    if [[ "$INPUT" == *"/"* ]]; then
        FULL_URL="$INPUT"
    else
        FULL_URL="${PREFIX}${INPUT}"
    fi

    echo "-------------------------------------------"
    echo "⏳ 正在拉取: $FULL_URL"
    while true; do
        ollama pull "$FULL_URL"
        if [ $? -eq 0 ]; then
            echo "✅ $INPUT 下载成功！"
            break
        else
            echo "❌ 失败，${DELAY}秒后重试..."
            sleep $DELAY
        fi
    done
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "🚀 脚本已成功安装至: $TARGET_PATH"

    # 自动处理 PATH 路径
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        SHELL_RC="$HOME/.bashrc"
        # 兼容 zsh
        [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        
        echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
        echo "📝 已将 ~/bin 添加到 $SHELL_RC"
        echo "🔔 请运行 'source $SHELL_RC' 使命令立即生效。"
    fi
}

# --- 3. 执行安装 ---
# 如果是直接运行且带了模型参数，先执行安装，再顺便执行下载任务
install_logic

if [ $# -gt 0 ]; then
    echo "📦 检测到参数，立即开始执行下载任务..."
    "$TARGET_PATH" "$@"
fi
