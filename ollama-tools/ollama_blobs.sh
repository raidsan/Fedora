#!/bin/bash

# ==============================================================================
# 名称: ollama_blobs
# 功能: 列出模型及其GGUF权重Blob哈希；支持关键字过滤及路径输出
# 参数:
#   [关键字]        可选，匹配模型名称
#   --blob-path    可选，仅输出匹配到的 Blob 绝对路径 (需配合关键字使用)
# ==============================================================================

DEST_PATH="/usr/local/bin/ollama_blobs"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "ollama_blobs 已成功安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 参数处理 ---
KEYWORD=""
ONLY_PATH=false
for arg in "$@"; do
    if [ "$arg" == "--blob-path" ]; then ONLY_PATH=true; else KEYWORD="$arg"; fi
done

# --- 第三阶段: 核心逻辑 ---

get_models_dir() {
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then echo "$env_path"; return; fi
    [ -d "/usr/share/ollama/.ollama/models" ] && echo "/usr/share/ollama/.ollama/models" && return
    [ -d "/var/lib/ollama/.ollama/models" ] && echo "/var/lib/ollama/.ollama/models" && return
    echo "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/.ollama/models"
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_ROOT="$MODELS_ROOT/manifests"
BLOBS_DIR="$MODELS_ROOT/blobs"

if [ ! -d "$MANIFEST_ROOT" ]; then
    [ "$ONLY_PATH" = false ] && echo "错误: 无法定位 Manifests 目录。"
    exit 1
fi

results=$( {
    find "$MANIFEST_ROOT" -type f 2>/dev/null | while read -r file; do
        rel_name=$(echo "$file" | sed "s|^$MANIFEST_ROOT/||" | sed 's|[^/]*/||')
        model_tag=$(echo "$rel_name" | sed 's/\/\([^/]*\)$/:\1/')
        model_tag=${model_tag#library/}
        
        # 关键字过滤
        if [ -n "$KEYWORD" ]; then
            if [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then continue; fi
        fi

        # 【核心修正点】
        # 之前的逻辑可能抓到 config 层。
        # 现在我们通过定位 "image.model" 这个 mediaType 后面紧跟的第一个 digest 来提取。
        # 1. 找到包含 image.model 的行
        # 2. 找到该行之后的第一个 digest
        raw_blob=$(grep -A 5 "image.model" "$file" | grep -m 1 -oP '"digest":"\K[^"]+' | sed 's/:/-/g')
        
        if [ -n "$raw_blob" ]; then
            if [ "$ONLY_PATH" = true ]; then
                echo "$BLOBS_DIR/$raw_blob"
            else
                printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
            fi
        fi
    done
} | sort -u )

# --- 第四阶段: 输出 ---
if [ "$ONLY_PATH" = true ]; then
    [ -n "$results" ] && echo "$results"
else
    echo "Ollama 模型根目录: $MODELS_ROOT"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG" "WEIGHTS BLOB (GGUF)"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    [ -n "$results" ] && echo "$results" || echo "(无匹配结果)"
fi
