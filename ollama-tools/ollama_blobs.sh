#!/bin/bash

# ==============================================================================
# 名称: ollama_blobs
# 功能: 列出模型及其GGUF权重Blob哈希；支持关键字过滤及路径输出
# 参数:
#   [关键字]        可选，匹配模型名称
#   --blob-path    可选，仅输出匹配到的 Blob 绝对路径 (需配合关键字使用)
# ==============================================================================

DEST_PATH="/usr/local/bin/ollama_blobs"

# --- 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "ollama_blobs 已成功安装。"
    exit 0
fi

# --- 参数处理 ---
KEYWORD=""
ONLY_PATH=false
for arg in "$@"; do
    if [ "$arg" == "--blob-path" ]; then ONLY_PATH=true; else KEYWORD="$arg"; fi
done

# --- 路径确定 ---
get_models_dir() {
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    [ -d "$env_path" ] && echo "$env_path" && return
    [ -d "/storage/models" ] && echo "/storage/models" && return
    echo "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/.ollama/models"
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_ROOT="$MODELS_ROOT/manifests"
BLOBS_DIR="$MODELS_ROOT/blobs"

# --- 核心搜索逻辑 ---
results=$( {
    # 限制最小深度为 3 (registry/user/model) 避开根目录干扰
    find "$MANIFEST_ROOT" -mindepth 3 -type f -not -path "*/sha256/*" | while read -r file; do
        
        # 提取相对路径
        rel_path=${file#$MANIFEST_ROOT/}
        IFS='/' read -r -a parts <<< "$rel_path"
        
        # 只要深度足够，取最后两段
        if [ ${#parts[@]} -ge 2 ]; then
            tag=${parts[-1]}
            model=${parts[-2]}
            model_tag="${model}:${tag}"
            
            # 过滤 library 前缀
            model_tag=${model_tag#library/}

            # 关键字过滤
            if [ -n "$KEYWORD" ] && [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then
                continue
            fi

            # 提取权重 Blob
            raw_blob=$(grep -A 5 "image.model" "$file" | grep -m 1 -oP 'sha256:[a-f0-9]+' | sed 's/:/-/g')

            # 终极校验：必须有名字、有标签、有哈希才输出
            if [[ "$model_tag" == *":"* ]] && [ -n "$raw_blob" ]; then
                if [ "$ONLY_PATH" = true ]; then
                    echo "$BLOBS_DIR/$raw_blob"
                else
                    printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
                fi
            fi
        fi
    done
} | sort -u )

# --- 输出 ---
if [ "$ONLY_PATH" = true ]; then
    [ -n "$results" ] && echo "$results"
else
    echo "使用模型根目录: $MODELS_ROOT"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG" "WEIGHTS BLOB (GGUF)"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    [ -n "$results" ] && echo "$results" || echo "(无匹配结果)"
fi
