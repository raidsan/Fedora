#!/bin/bash

# ==============================================================================
# 名称: run_llama_server
# 用途: 自动查找 Ollama 模型并启动 llama-server
# 用法: run_llama_server <模型关键字> [-p 端口] [-c 上下文] [-v] [--bin 路径]
# ==============================================================================

DEST_PATH="/usr/local/bin/run_llama_server"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "run_llama_server 已成功安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 辅助函数 ---

parse_context_size() {
    local input=$1
    if [[ "$input" =~ ^([0-9]+)[kK]$ ]]; then
        local num=${BASH_REMATCH[1]}
        echo $((num * 1024))
    else
        echo "$input"
    fi
}

find_llama_bin() {
    if [ -f "/usr/local/bin/llama-server" ]; then
        echo "/usr/local/bin/llama-server"
    elif [ -f "$HOME/llama.cpp/build/bin/llama-server" ]; then
        echo "$HOME/llama.cpp/build/bin/llama-server"
    else
        echo ""
    fi
}

# --- 第三阶段: 参数解析 ---

MODEL_KEYWORD=""
PORT="8080"
CTX_INPUT="8k"
USER_BIN=""
VERBOSE_FLAG=""

# 提取第一个参数作为模型关键字 (如果它不是以 - 开头)
if [[ -n "$1" && ! "$1" =~ ^- ]]; then
    MODEL_KEYWORD="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p)
            PORT="$2"
            shift 2
            ;;
        -c)
            CTX_INPUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE_FLAG="--verbose"
            shift
            ;;
        --bin)
            USER_BIN="$2"
            shift 2
            ;;
        *)
            if [ -z "$MODEL_KEYWORD" ]; then
                MODEL_KEYWORD="$1"
                shift
            else
                echo "未知参数: $1"
                exit 1
            fi
            ;;
    esac
done

if [ -z "$MODEL_KEYWORD" ]; then
    echo "用法: run_llama_server <模型关键字> [-p 端口] [-c 上下文] [-v] [--bin 路径]"
    exit 1
fi

if [ -n "$USER_BIN" ]; then
    LLAMA_BIN="$USER_BIN"
else
    LLAMA_BIN=$(find_llama_bin)
fi

CTX_SIZE=$(parse_context_size "$CTX_INPUT")

# --- 第四阶段: 核心运行逻辑 ---

if ! command -v ollama_blobs >/dev/null 2>&1; then
    echo "错误: 未检测到 ollama_blobs 命令。"
    exit 1
fi

if [ -z "$LLAMA_BIN" ] || [ ! -f "$LLAMA_BIN" ]; then
    echo "错误: 找不到 llama-server 程序。"
    exit 1
fi

MODEL_PATH=$(ollama_blobs "$MODEL_KEYWORD" --blob-path)
COUNT=$(echo "$MODEL_PATH" | grep -c "sha256-")

if [ "$COUNT" -eq 0 ]; then
    echo "错误: 未找到匹配关键字 '$MODEL_KEYWORD' 的模型。"
    exit 1
elif [ "$COUNT" -gt 1 ]; then
    echo "错误: 匹配到多个模型:"
    echo "$MODEL_PATH"
    exit 1
fi

echo "--------------------------------------------------"
echo "程序路径: $LLAMA_BIN"
echo "模型路径: $MODEL_PATH"
echo "模型别名: $MODEL_KEYWORD"
echo "服务端口: $PORT"
echo "调试模式: ${VERBOSE_FLAG:-关闭}"
echo "--------------------------------------------------"

export LLAMA_ARG_HOST=0.0.0.0

# 仅在指定了 $VERBOSE_FLAG 时才会添加 --verbose 参数
exec "$LLAMA_BIN" \
    -m "$MODEL_PATH" \
    --alias "$MODEL_KEYWORD" \
    --n-gpu-layers 999 \
    --port "$PORT" \
    -c "$CTX_SIZE" \
    $VERBOSE_FLAG

echo ""
