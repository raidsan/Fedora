#!/bin/bash

# ==============================================================================
# 名称: run_llama_server
# 用途: 自动查找 Ollama 模型并启动 llama-server (支持端口和上下文自定义)
# 管理: 建议通过 github-tools 安装/更新
# 用法: run_llama_server <模型关键字> [端口] [上下文] [程序路径]
# ==============================================================================

DEST_PATH="/usr/local/bin/run_llama_server"
DEFAULT_BIN="$HOME/llama.cpp/build/bin/llama-server"

# --- 第一阶段: 安装逻辑 (供 github-tools 使用) ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "run_llama_server 已成功安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 参数解析 ---
# 参数位说明：
# $1: 模型关键字 (必填)
# $2: 端口 (可选，缺省 8080)
# $3: 上下文长度 (可选，缺省 8192)
# $4: 程序路径 (可选，缺省 ~/llama.cpp/build/bin/llama-server)

if [ -z "$1" ] || [ "$1" == "help" ]; then
    echo "用法: run_llama_server <模型关键字> [端口] [上下文] [程序路径]"
    echo "示例: run_llama_server qwen 8081 16384"
    exit 1
fi

MODEL_KEYWORD="$1"
PORT="${2:-8080}"
CTX_SIZE="${3:-8192}"
LLAMA_BIN="${4:-$DEFAULT_BIN}"

# --- 第三阶段: 核心逻辑 ---

# 1. 检查依赖与程序
if ! command -v ollama_blobs >/dev/null 2>&1; then
    echo "错误: 未检测到 ollama_blobs，请先安装它。"
    exit 1
fi

if [ ! -f "$LLAMA_BIN" ]; then
    echo "错误: 找不到 llama-server 程序: $LLAMA_BIN"
    exit 1
fi

# 2. 获取模型路径
echo "正在搜索模型: $MODEL_KEYWORD ..."
MODEL_PATH=$(ollama_blobs "$MODEL_KEYWORD" --blob-path)
COUNT=$(echo "$MODEL_PATH" | grep -c "sha256-")

if [ "$COUNT" -eq 0 ]; then
    echo "错误: 未找到匹配关键字 '$MODEL_KEYWORD' 的模型。"
    exit 1
elif [ "$COUNT" -gt 1 ]; then
    echo "错误: 匹配到多个模型，请提供更精确的关键字:"
    echo "$MODEL_PATH"
    exit 1
fi

# 3. 配置并启动
echo "--------------------------------------------------"
echo "模型路径: $MODEL_PATH"
echo "监听端口: $PORT"
echo "上下文  : $CTX_SIZE"
echo "程序路径: $LLAMA_BIN"
echo "--------------------------------------------------"

# 强制环境变量
export LLAMA_ARG_HOST=0.0.0.0

# 启动程序
exec "$LLAMA_BIN" \
    -m "$MODEL_PATH" \
    --n-gpu-layers 999 \
    --port "$PORT" \
    -c "$CTX_SIZE" \
    --verbose
