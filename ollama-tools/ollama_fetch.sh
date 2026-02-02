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

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "$TOOL_NAME 已成功安装至 $DEST_PATH。"
    exit 0
fi

# --- 第二阶段: 文档逻辑 ---
show_doc() {
    local doc_file="$META_DIR/$TOOL_NAME.md"
    [ ! -f "$doc_file" ] && echo "错误: 文档未找到。" && exit 1
    command -v glow >/dev/null 2>&1 && glow "$doc_file" || cat "$doc_file"
    exit 0
}
[[ "$1" == "-doc" ]] && show_doc

# --- 第三阶段: 业务逻辑 ---

# 1. 自动定位 Ollama 模型库存放目录
# 优先从环境变量获取，否则搜索系统默认路径
OLLAMA_BASE=$(systemctl show ollama.service --property=Environment 2>/dev/null | grep -oP 'OLLAMA_MODELS=\K[^ ]+' | sed 's/\"//g')

if [ -z "$OLLAMA_BASE" ]; then
    # 默认路径探测 (Fedora/Linux 标准)
    SEARCH_PATHS=("/usr/share/ollama/.ollama/models" "/var/lib/ollama/.ollama/models" "$HOME/.ollama/models")
    for p in "${SEARCH_PATHS[@]}"; do
        if [ -d "$p" ]; then OLLAMA_BASE="$p"; break; fi
    done
fi

# 如果还是没找到，回退到用户家目录
OLLAMA_BASE=${OLLAMA_BASE:-"$HOME/.ollama/models"}
# 定位其父目录作为下载中转站 (即 /storage/models -> /storage/tmp)
STORAGE_ROOT=$(dirname "$OLLAMA_BASE")
FETCH_TMP="$STORAGE_ROOT/tmp/ollama_fetch_$(date +%s)"

REPO=$1
FILE_PATTERN=$2
ALIAS=${3:-$(echo "$REPO" | awk -F'/' '{print $2}' | tr '[:upper:]' '[:lower:]')}

if [ -z "$REPO" ] || [ -z "$FILE_PATTERN" ]; then
    echo "使用方法: $TOOL_NAME <HF仓库> <文件匹配规则> [别名]"
    echo "示例: $TOOL_NAME unsloth/Qwen3-Coder-32B-Instruct-GGUF \"*Q8_0.gguf\""
    exit 1
fi

echo "----------------------------------------------------"
echo "📂 Ollama 库路径: $OLLAMA_BASE"
echo "🚀 下载中转目录: $FETCH_TMP (位于同一挂载点)"
echo "----------------------------------------------------"

mkdir -p "$FETCH_TMP"

# 调用 huggingface-cli 下载
if huggingface-cli download "$REPO" --local-dir "$FETCH_TMP" --local-dir-use-symlinks False --include "$FILE_PATTERN"; then
    GGUF_FILE=$(find "$FETCH_TMP" -name "*.gguf" | head -n 1)
    
    if [ -f "$GGUF_FILE" ]; then
        echo "✅ 下载成功: $(basename "$GGUF_FILE")"
        
        # 创建临时 Modelfile
        cat << EOF > "$FETCH_TMP/Modelfile"
FROM $GGUF_FILE
PARAMETER temperature 1.0
PARAMETER repeat_penalty 1.0
EOF
        
        echo "📦 正在注入 Ollama..."
        if ollama create "$ALIAS" -f "$FETCH_TMP/Modelfile"; then
            echo "🎉 模型 '$ALIAS' 注册成功！"
        fi
    fi
else
    echo "❌ 下载失败，请检查网络或 HF 仓库名。"
fi

# 清理同一挂载点下的临时目录
rm -rf "$FETCH_TMP"
echo "🧹 临时目录已清理。"
