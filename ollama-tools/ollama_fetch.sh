#!/bin/bash

# ==============================================================================
# 名称: ollama_fetch
# 用途: 从 Hugging Face 下载 GGUF 模型并自动注册至 Ollama
# 管理: 由 github-tools 管理，安装于 /usr/local/bin/
# 依赖: huggingface-cli, ollama
# ==============================================================================

TOOL_NAME="ollama_fetch"
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
    [ ! -f "$doc_file" ] && echo "错误: 文档未找到。" && exit 1
    command -v glow >/dev/null 2>&1 && glow "$doc_file" || cat "$doc_file"
    exit 0
}

[[ "$1" == "-doc" ]] && show_doc

# --- 第三阶段: 业务逻辑 ---

# 1. 依赖检查
if ! command -v huggingface-cli >/dev/null 2>&1; then
    echo "错误: 未找到 huggingface-cli，请执行 'pip install huggingface_hub'。"
    exit 1
fi

# 2. 自动定位模型库存储点，确保中转空间与存储空间在同一挂载点
# 优先级：环境变量 > Systemd 配置 > 常见预设路径
OLLAMA_BASE=$(systemctl show ollama.service --property=Environment 2>/dev/null | grep -oP 'OLLAMA_MODELS=\K[^ ]+' | sed 's/\"//g')

if [ -z "$OLLAMA_BASE" ]; then
    SEARCH_PATHS=("/usr/share/ollama/.ollama/models" "/var/lib/ollama/.ollama/models" "$HOME/.ollama/models")
    for p in "${SEARCH_PATHS[@]}"; do
        if [ -d "$p" ]; then OLLAMA_BASE="$p"; break; fi
    done
fi

OLLAMA_BASE=${OLLAMA_BASE:-"$HOME/.ollama/models"}
STORAGE_ROOT=$(dirname "$OLLAMA_BASE")
# 在存储根目录下创建 tmp，避免根分区 /tmp 溢出
FETCH_TMP="$STORAGE_ROOT/tmp/ollama_fetch_$(date +%s)"

REPO=$1
FILE_PATTERN=$2
# 如果未指定别名，则提取仓库名作为模型名
ALIAS=${3:-$(echo "$REPO" | awk -F'/' '{print $2}' | tr '[:upper:]' '[:lower:]')}

if [ -z "$REPO" ] || [ -z "$FILE_PATTERN" ]; then
    echo "使用方法: $TOOL_NAME <HF仓库名> <文件名匹配规则> [模型别名]"
    echo "示例: $TOOL_NAME ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF \"*.gguf\" qwen3-q8"
    exit 1
fi

echo "----------------------------------------------------"
echo "📂 检测到存储根目录: $STORAGE_ROOT"
echo "🚀 正在中转下载至: $FETCH_TMP"
echo "----------------------------------------------------"

mkdir -p "$FETCH_TMP"

# 下载逻辑：使用 local-dir 强制下载到大容量中转站
if huggingface-cli download "$REPO" --local-dir "$FETCH_TMP" --local-dir-use-symlinks False --include "$FILE_PATTERN"; then
    GGUF_FILE=$(find "$FETCH_TMP" -name "*.gguf" | head -n 1)
    
    if [ -f "$GGUF_FILE" ]; then
        echo "✅ 下载成功，正在通过 Modelfile 注入 Ollama..."
        
        # 针对 MoE 架构优化默认参数
        cat << EOF > "$FETCH_TMP/Modelfile"
FROM $GGUF_FILE
PARAMETER temperature 1.0
PARAMETER repeat_penalty 1.0
EOF
        
        # 注册模型
        if ollama create "$ALIAS" -f "$FETCH_TMP/Modelfile"; then
            echo "----------------------------------------------------"
            echo "🎉 成功! 模型 '$ALIAS' 已就绪。"
            echo "💡 执行: ollama run $ALIAS"
        fi
    fi
else
    echo "❌ 下载失败。"
fi

# 清理同一分区下的临时文件
rm -rf "$FETCH_TMP"
echo -e "🧹 临时目录已清理。\n"
