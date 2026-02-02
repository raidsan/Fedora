#!/bin/bash

# ==============================================================================
# 名称: ollama_pull
# 用途: 快速拉取 Ollama 模型，支持多镜像源切换及断点续传。
# 管理: 由 github-tools 管理，安装于 /usr/local/bin/
# 文档: 支持 -doc 参数查看
# ==============================================================================

TOOL_NAME="ollama_pull"
DEST_PATH="/usr/local/bin/$TOOL_NAME"
META_DIR="/usr/local/share/github-tools-meta"

# --- 第一阶段: 安装逻辑 (适配 github-tools) ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "$TOOL_NAME 已成功安装至 $DEST_PATH。"
    exit 0
fi

# --- 第二阶段: 文档查阅逻辑 ---
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    if [ ! -f "$doc_file" ]; then
        echo "错误: 未找到对应的文档文件 ($doc_file)。"
        exit 1
    fi
    # 优先使用 glow 渲染，否则回退至 cat
    if command -v glow >/dev/null 2>&1; then
        glow "$doc_file"
    else
        echo -e "\n--- $TOOL_NAME 使用文档 ---\n"
        cat "$doc_file"
        echo -e "\n--- 文档结束 ---\n"
    fi
    exit 0
}

# 检查是否请求查看文档
[[ "$1" == "-doc" ]] && show_doc

# --- 第三阶段: 业务逻辑 ---

# 变量初始化
MODELS=()
MIRROR_NAME="dao" 
MIRROR_PREFIX="ollama.m.daocloud.io/library/" 

# 参数解析
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
            echo "错误: 不支持的镜像提供商: $arg"
            exit 1
            ;;
        *)
            MODELS+=("$arg")
            ;;
    esac
done

if [ ${#MODELS[@]} -eq 0 ]; then
    echo "使用方法: $TOOL_NAME <模型1> <模型2...> [-p=nju|dao]"
    echo "提示: 输入 '$TOOL_NAME -doc' 查看详细手册。"
    exit 1
fi

echo "----------------------------------------------------"
echo "🛠️  镜像源: $MIRROR_NAME ($MIRROR_PREFIX)"
echo "----------------------------------------------------"

for model in "${MODELS[@]}"; do
    SHORT_NAME=$(echo "$model" | awk -F'/' '{print $3}' | awk -F'@' '{print $1}')
    [ -z "$SHORT_NAME" ] && SHORT_NAME=$(echo "$model" | awk -F'/' '{print $NF}')
    
    FULL_URL="$MIRROR_PREFIX$model"
    
    echo "🚀 正在拉取: $SHORT_NAME"
    
    while true; do
        if ollama pull "$FULL_URL"; then
            echo "✅ 拉取成功，创建别名..."
            ollama cp "$FULL_URL" "$SHORT_NAME"
            echo "✨ 别名 '$SHORT_NAME' 已就绪。"
            break
        else
            echo "⚠️  连接失败，5秒后自动重试 (Ctrl+C 退出)..."
            sleep 5
        fi
    done
done

echo "----------------------------------------------------"
echo "🎉 所有任务执行完毕！"
