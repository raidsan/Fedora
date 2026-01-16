#!/bin/bash

# --- 1. 安装逻辑 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_pull"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    
    # 写入工具核心脚本
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash
# 设置基础路径环境变量
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# --- 变量初始化 ---
MODELS=()
MIRROR_NAME="dao" 
MIRROR_PREFIX="ollama.m.daocloud.io/library/" 

# 第一遍参数扫描：提取镜像配置 --p
for arg in "$@"; do
    case $arg in
        --p=nju)
            MIRROR_PREFIX="docker.nju.edu.cn/ollama/"
            MIRROR_NAME="nju"
            ;;
        --p=dao)
            MIRROR_PREFIX="ollama.m.daocloud.io/library/"
            MIRROR_NAME="dao"
            ;;
        --p=*)
            echo "Error: Unsupported mirror provider: $arg (Use --p=dao or --p=nju)"
            exit 1
            ;;
        *)
            # 收集待下载的模型或 URL
            MODELS+=("$arg")
            ;;
    esac
done

# 校验是否有模型参数输入
if [ ${#MODELS[@]} -eq 0 ]; then
    echo "Usage: ollama_pull <model1> <url2> ... [--p=dao|nju]"
    exit 1
fi

# 捕获中断信号 (Ctrl+C)
trap 'echo -e "\n🛑 User interrupted. Exiting..."; exit 1' SIGINT SIGTERM

# --- 批量下载循环逻辑 ---
for INPUT in "${MODELS[@]}"; do
    echo "----------------------------------------------------"
    
    # 判断输入是否为完整 URL (包含斜杠)
    if [[ "$INPUT" == *"/"* ]]; then
        # 校验：输入 URL 必须与 --p 指定的源匹配
        if [[ "$INPUT" != "$MIRROR_PREFIX"* ]]; then
            echo "Conflict Error!"
            echo "Input URL : $INPUT"
            echo "Current Mirror Scope (--p=$MIRROR_NAME): $MIRROR_PREFIX"
            echo "Action: Aborting to prevent source mismatch."
            exit 1
        fi
        FULL_URL="$INPUT"
        # 提取斜杠后的模型名作为简称
        SHORT_NAME="${INPUT##*/}"
    else
        # 自动拼接前缀生成完整 URL
        FULL_URL="${MIRROR_PREFIX}${INPUT}"
        SHORT_NAME="$INPUT"
    fi

    echo "🚀 Model  : $SHORT_NAME"
    echo "🌐 Source : $FULL_URL"
    
    # 失败重试循环，应对大模型下载中断
    while true; do
        echo "🔄 Pulling data (Resume supported)..."
        if ollama pull "$FULL_URL"; then
            echo "✅ Pull success. Creating alias..."
            # 使用 ollama cp 创建简称，方便后续直接运行
            if ollama cp "$FULL_URL" "$SHORT_NAME"; then
                echo "✨ Alias '$SHORT_NAME' is ready."
                # 下载完成后清理冗长的镜像前缀标签
                if [ "$FULL_URL" != "$SHORT_NAME" ]; then
                    ollama rm "$FULL_URL" > /dev/null 2>&1
                fi
            fi
            break
        else
            echo "⚠️  Connection failed. Retrying in 5s (Ctrl+C to stop)..."
            sleep 5
        fi
    done
done

echo "----------------------------------------------------"
echo "🎉 All tasks completed successfully!"
INNER_EOF

    # 赋予工具可执行权限
    chmod +x "$TARGET_PATH"
    echo "✅ Ollama Pull Tool installed to $TARGET_PATH"

    # --- 2. 自动配置环境变量 PATH ---
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        
        # 检查是否已存在，避免重复追加
        if ! grep -q "$INSTALL_DIR" "$SHELL_RC"; then
            echo -e "\n# Path for custom ollama tools\nexport PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
            echo "📝 PATH added to $SHELL_RC. Run 'source $SHELL_RC' to update current session."
        fi
    fi
}

# 启动安装
install_logic

# --- 3. 参数穿透执行 ---
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
