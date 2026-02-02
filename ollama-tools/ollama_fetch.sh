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
# 检查当前脚本是否已安装在目标路径，若不是则执行安装逻辑
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

# 1. 环境依赖预检
if ! command -v huggingface-cli >/dev/null 2>&1; then
    echo "错误: 未找到 huggingface-cli，请执行 'pip install huggingface_hub' 安装。"
    exit 1
fi

# 2. 自动定位 Ollama 模型库物理路径，确保中转空间充足
# 通过解析 systemd 服务或搜索常见路径，找到实际的模型存储位置
OLLAMA_BASE=$(systemctl show ollama.service --property=Environment 2>/dev/null | grep -oP 'OLLAMA_MODELS=\K[^ ]+' | sed 's/\"//g')

if [ -z "$OLLAMA_BASE" ]; then
    # 探测常见的本地及全局存储路径
    SEARCH_PATHS=("/usr/share/ollama/.ollama/models" "/var/lib/ollama/.ollama/models" "$HOME/.ollama/models")
    for p in "${SEARCH_PATHS[@]}"; do
        if [ -d "$p" ]; then OLLAMA_BASE="$p"; break; fi
    done
fi

OLLAMA_BASE=${OLLAMA_BASE:-"$HOME/.ollama/models"}
# 在模型库同级目录下创建 tmp 文件夹，利用相同的磁盘分区空间
STORAGE_ROOT=$(dirname "$OLLAMA_BASE")
FETCH_TMP="$STORAGE_ROOT/tmp/ollama_fetch_$(date +%s)"

REPO=$1
FILE_PATTERN=$2
# 如果未提供别名，则使用仓库名的后缀作为默认模型名
ALIAS=${3:-$(echo "$REPO" | awk -F'/' '{print $2}' | tr '[:upper:]' '[:lower:]')}

if [ -z "$REPO" ] || [ -z "$FILE_PATTERN" ]; then
    echo "使用方法: $TOOL_NAME <HF仓库名> <文件名匹配规则> [模型别名]"
    echo "示例: $TOOL_NAME unsloth/GLM-4.7-Flash-GGUF \"*Q8_0.gguf\""
    exit 1
fi

echo "----------------------------------------------------"
echo "📂 Ollama 存储根目录: $STORAGE_ROOT"
echo "🚀 临时中转路径: $FETCH_TMP"
echo "----------------------------------------------------"

mkdir -p "$FETCH_TMP"

# 执行下载任务，关闭符号链接以确保文件完整复制到目标位置
if huggingface-cli download "$REPO" --local-dir "$FETCH_TMP" --local-dir-use-symlinks False --include "$FILE_PATTERN"; then
    GGUF_FILE=$(find "$FETCH_TMP" -name "*.gguf" | head -n 1)
    
    if [ -f "$GGUF_FILE" ]; then
        echo "✅ 下载成功，准备注入 Ollama..."
        
        # 构造 Modelfile，注入针对本地 AI 主机的默认参数
        cat << EOF > "$FETCH_TMP/Modelfile"
FROM $GGUF_FILE
PARAMETER temperature 1.0
PARAMETER repeat_penalty 1.0
EOF
        
        # 使用 ollama create 进行最终注册
        if ollama create "$ALIAS" -f "$FETCH_TMP/Modelfile"; then
            echo "🎉 模型 '$ALIAS' 已成功导入模型库。"
        fi
    fi
else
    echo "❌ 从 Hugging Face 获取失败。"
fi

# 任务完成后清理该分区下的临时数据
rm -rf "$FETCH_TMP"
echo "🧹 清理完成。"
