#!/bin/bash

# ==============================================================================
# 名称: run_llama_server
# 用途: 自动查找 Ollama 模型并启动 llama-server (支持多路径搜索及单位换算)
# 用法: run_llama_server <模型关键字> [-p 端口] [-c 上下文] [--bin 程序路径]
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

# 将 k 格式转换为数字 (例如 8k -> 8192)
parse_context_size() {
    local input=$1
    if [[ "$input" =~ ^([0-9]+)[kK]$ ]]; then
        local num=${BASH_REMATCH[1]}
        echo $((num * 1024))
    else
        echo "$input"
    fi
}

# 自动探测 llama-server 程序位置
find_llama_bin() {
    if [ -f "/usr/local/bin/llama-server" ]; then
        echo "/usr/local/bin/llama-server"
    elif [ -f "$HOME/llama.cpp/build/bin/llama-server" ]; then
        echo "$HOME/llama.cpp/build/bin/llama-server"
    else
        # 默认返回空，由逻辑判断报错
        echo ""
    fi
}

# --- 第三阶段: 参数解析 ---

MODEL_KEYWORD=""
PORT="8080"
CTX_INPUT="8k"
USER_BIN=""

# 提取第一个参数作为模型关键字 (如果它不是以 - 开头)
if [[ -n "$1" && ! "$1" =~ ^- ]]; then
    MODEL_KEYWORD="$1"
    shift
fi

# 解析标志位参数
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
    echo "用法: run_llama_server <模型关键字> [-p 端口] [-c 上下文] [--bin 路径]"
    exit 1
fi

# 确定程序路径
if [ -n "$USER_BIN" ]; then
    LLAMA_BIN="$USER_BIN"
else
    LLAMA_BIN=$(find_llama_bin)
fi

# 转换上下文大小
CTX_SIZE=$(parse_context_size "$CTX_INPUT")

# --- 第四阶段: 核心运行逻辑 ---

# 1. 检查依赖
if ! command -v ollama_blobs >/dev/null 2>&1; then
    echo "错误: 未检测到 ollama_blobs 命令。"
    exit 1
fi

if [ -z "$LLAMA_BIN" ] || [ ! -f "$LLAMA_BIN" ]; then
    echo "错误: 找不到 llama-server 程序。"
    echo "请检查以下位置："
    echo "1. /usr/local/bin/llama-server"
    echo "2. $HOME/llama.cpp/build/bin/llama-server"
    echo "或者使用 --bin 手动指定路径。"
    exit 1
fi

# 2. 获取模型路径
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

# 3. 启动
echo "--------------------------------------------------"
echo "程序路径: $LLAMA_BIN"
echo "模型路径: $MODEL_PATH"
echo "服务端口: $PORT"
echo "上下文  : $CTX_INPUT ($CTX_SIZE)"
echo "--------------------------------------------------"

# 强制环境变量
export LLAMA_ARG_HOST=0.0.0.0

exec "$LLAMA_BIN" \
    -m "$MODEL_PATH" \
    --n-gpu-layers 999 \
    --port "$PORT" \
    -c "$CTX_SIZE" \
    --verbose
