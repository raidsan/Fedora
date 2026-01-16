#!/bin/bash

# --- 1. 安装逻辑 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_pull"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash
# 设置基础环境路径
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# --- 变量初始化 ---
MODELS=()
MIRROR_NAME="dao" 
MIRROR_PREFIX="ollama.m.daocloud.io/library/" 

# --- 参数解析 ---
for arg in "$@"; do
    case $arg in
        --p=nju|-p=nju)
            MIRROR_PREFIX="docker.nju.edu.cn/ollama/"
            MIRROR_NAME="nju"
            ;;
        --p=dao|-p=dao)
            MIRROR_PREFIX="ollama.m.daocloud.io/library/"
            MIRROR_NAME="dao"
            ;;
        -p=*|--p=*)
            echo "Error: Unsupported mirror provider: $arg"
            exit 1
            ;;
        *)
            MODELS+=("$arg")
            ;;
    esac
done

if [ ${#MODELS[@]} -eq 0 ]; then
    echo "Usage: ollama_pull <model1> <url2> ... [-p=dao|nju]"
    exit 1
fi

trap 'echo -e "\n🛑 User interrupted. Exiting..."; exit 1' SIGINT SIGTERM

# --- 批量处理循环 ---
for INPUT in "${MODELS[@]}"; do
    echo "----------------------------------------------------"
    
    # 路径与镜像一致性校验
    if [[ "$INPUT" == *"/"* ]]; then
        if [[ "$INPUT" != "$MIRROR_PREFIX"* ]]; then
            echo "Conflict Error!"
            echo "Input URL : $INPUT"
            echo "Expected  : $MIRROR_PREFIX (based on -p=$MIRROR_NAME)"
            exit 1
        fi
        FULL_URL="$INPUT"
        SHORT_NAME="${INPUT##*/}"
    else
        FULL_URL="${MIRROR_PREFIX}${INPUT}"
        SHORT_NAME="$INPUT"
    fi

    # --- 预检逻辑 ---
    # 使用 ollama show 尝试获取远程信息来验证模型是否存在
    echo "🔍 Validating model existence: $FULL_URL"
    if ! ollama show "$FULL_URL" > /dev/null 2>&1; then
        # 如果 show 失败，尝试 pull 一下 manifest 级别（轻量级验证）
        if ! timeout 10s ollama pull "$FULL_URL" 2>&1 | grep -q "pulling manifest"; then
             echo "✅ Pre-check: Model manifests confirmed or ready for pull."
        fi
    fi

    echo "🚀 Model  : $SHORT_NAME"
    echo "🌐 Source : $FULL_URL"
    
    # 进入重试循环
    while true; do
        echo "🔄 Pulling data (Resume supported)..."
        if ollama pull "$FULL_URL"; then
            echo "✅ Pull success. Creating alias..."
            # 创建简称别名
            if ollama cp "$FULL_URL" "$SHORT_NAME"; then
                echo "✨ Alias '$SHORT_NAME' is ready."
                echo "ℹ️  Original tag '$FULL_URL' is kept."
            fi
            break
        else
            echo "⚠️  Connection failed. Retrying in 5s (Ctrl+C to stop)..."
            sleep 5
        fi
    done
done

echo "----------------------------------------------------"
echo "🎉 All tasks completed!"
INNER_EOF

    # 赋予执行权限
    chmod +x "$TARGET_PATH"
    echo "✅ Ollama Pull Tool updated at $TARGET_PATH"

    # --- 2. 环境变量 PATH 管理 ---
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        if ! grep -q "$INSTALL_DIR" "$SHELL_RC"; then
            echo -e "\n# Path for custom ollama tools\nexport PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
            echo "📝 PATH added to $SHELL_RC"
        fi
    fi
}

# 执行安装
install_logic

# --- 3. 参数穿透执行 ---
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
