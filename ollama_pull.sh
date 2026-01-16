#!/bin/bash

# --- 1. 配置信息 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_pull"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

# --- 2. 自动化安装逻辑 ---
install_logic() {
    mkdir -p "$INSTALL_DIR"

    # 将下载和重命名的核心逻辑写入目标文件
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash
PREFIX="ollama.m.daocloud.io/library/"
DELAY=5

if [ $# -eq 0 ]; then
    echo "使用方法: ollama_pull <模型名1> <模型名2> ..."
    exit 1
fi

for INPUT in "$@"; do
    # 1. 确定下载地址和本地简称
    if [[ "$INPUT" == *"/"* ]]; then
        FULL_URL="$INPUT"
        # 如果输入是完整路径，尝试提取最后一部分作为简称
        SHORT_NAME=$(echo "$INPUT" | awk -F'/' '{print $3}')
        # 如果提取失败（比如不是三段式路径），则使用最后一段
        [ -z "$SHORT_NAME" ] && SHORT_NAME=$(basename "$INPUT")
    else
        FULL_URL="${PREFIX}${INPUT}"
        SHORT_NAME="$INPUT"
    fi

    echo "-------------------------------------------"
    echo "⏳ 正在从镜像下载: $FULL_URL"
    
    # 2. 带有重试机制的拉取过程
    while true; do
        ollama pull "$FULL_URL"
        if [ $? -eq 0 ]; then
            echo "✅ $INPUT 下载完成！"
            
            # 3. 自动重命名（cp）
            if [ "$FULL_URL" != "$SHORT_NAME" ]; then
                echo "🏷️  正在创建本地别名: $SHORT_NAME ..."
                ollama cp "$FULL_URL" "$SHORT_NAME"
                
                if [ $? -eq 0 ]; then
                    echo "✨ 重命名成功！以后可直接使用: ollama run $SHORT_NAME"
                    # 可选：删除带有长前缀的标签以节省 list 显示空间（数据不会丢）
                    # ollama rm "$FULL_URL"
                fi
            fi
            break
        else
            echo "❌ 失败，${DELAY}秒后重试..."
            sleep $DELAY
        fi
    done
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "🚀 脚本已安装至: $TARGET_PATH"

    # 处理 PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
        echo "📝 已更新 PATH，请运行 'source $SHELL_RC'"
    fi
}

install_logic
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
