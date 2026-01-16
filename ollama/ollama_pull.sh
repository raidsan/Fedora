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

# --- 批量处理 ---
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

    echo "🔍 Validating: $FULL_URL"

    # --- 网站存在性检查逻辑 ---
    # 解析 URL 得到域名、镜像名和标签
    # 转换为典型的 Docker V2 Registry API 路径进行检查
    DOMAIN=$(echo "$FULL_URL" | cut -d'/' -f1)
    # 处理带 library 或不带的情况
    REPOS=$(echo "$FULL_URL" | cut -d'/' -f2-)
    # 替换冒号为标签路径 (manifests/tag)
    IMG_NAME=$(echo "${REPOS%:*}")
    IMG_TAG=$(echo "${REPOS#*:}")
    
    # 使用 curl 检查 Manifests 是否存在 (返回 200 即存在)
    CHECK_URL="https://${DOMAIN}/v2/${IMG_NAME}/manifests/${IMG_TAG}"
    
    # 发起 HEAD 请求验证
    HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" "$CHECK_URL")

    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "❌ Error: Model NOT found on registry!"
        echo "Status Code: $HTTP_CODE"
        echo "Checked URL: $CHECK_URL"
        echo "Please verify the model name or tag."
        # 验证失败，跳过该模型或报错停止
        exit 1
    fi

    echo "✅ Validation passed. Starting download..."
    echo "🚀 Model  : $SHORT_NAME"
    echo "🌐 Source : $FULL_URL"
    
    # 进入断点续传重试循环
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
    echo "✅ Ollama Pull Tool updated with Pre-flight Validation at $TARGET_PATH"
}

# --- 环境变量处理与立即执行 ---
install_logic
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
