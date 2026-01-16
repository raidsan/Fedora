#!/bin/bash

# --- 1. 安装逻辑 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_pull"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# --- 变量初始化 ---
MODELS=()
MIRROR_NAME="dao" 
MIRROR_PREFIX="ollama.m.daocloud.io/library/" 

# --- 改进后的参数解析 ---
# 遍历所有参数，识别镜像设置
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
            # 只有不带 -p 的才被视为模型名
            MODELS+=("$arg")
            ;;
    esac
done

if [ ${#MODELS[@]} -eq 0 ]; then
    echo "Usage: ollama_pull <model1> <url2> ... [-p=dao|nju]"
    exit 1
fi

trap 'echo -e "\n🛑 User interrupted. Exiting..."; exit 1' SIGINT SIGTERM

# --- 批量下载循环 ---
for INPUT in "${MODELS[@]}"; do
    echo "----------------------------------------------------"
    
    # 路径校验逻辑
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

    echo "🚀 Model  : $SHORT_NAME"
    echo "🌐 Source : $FULL_URL"
    
    while true; do
        echo "🔄 Pulling data (Resume supported)..."
        if ollama pull "$FULL_URL"; then
            echo "✅ Pull success. Creating alias..."
            if ollama cp "$FULL_URL" "$SHORT_NAME"; then
                echo "✨ Alias '$SHORT_NAME' is ready."
                if [ "$FULL_URL" != "$SHORT_NAME" ]; then
                    ollama rm "$FULL_URL" > /dev/null 2>&1
                fi
            fi
            break
        else
            echo "⚠️  Connection failed. Retrying in 5s..."
            sleep 5
        fi
    done
done
echo "----------------------------------------------------"
echo "🎉 All tasks completed!"
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Ollama Pull Tool updated and fixed at $TARGET_PATH"
}

install_logic
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
