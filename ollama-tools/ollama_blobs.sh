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
    echo "ollama_blobs 已成功安装。"
    exit 0
fi

# --- 第二阶段: 参数处理 ---
KEYWORD=""
ONLY_PATH=false
for arg in "$@"; do
    if [ "$arg" == "--blob-path" ]; then ONLY_PATH=true; else KEYWORD="$arg"; fi
done

# --- 第三阶段: 路径探测 ---
get_models_dir() {
    # 1. 尝试从运行中的进程探测 (最准确)
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then echo "$env_path"; return; fi

    # 2. 硬编码探测 (针对你的自定义存储)
    local common_paths=("/storage/models" "/usr/share/ollama/.ollama/models" "/var/lib/ollama/.ollama/models")
    for p in "${common_paths[@]}"; do
        [ -d "$p/manifests" ] && echo "$p" && return
    done

    # 3. 用户家目录兜底
    echo "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/.ollama/models"
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_ROOT="$MODELS_ROOT/manifests"
BLOBS_DIR="$MODELS_ROOT/blobs"

if [ ! -d "$MANIFEST_ROOT" ]; then
    [ "$ONLY_PATH" = false ] && echo "错误: 无法定位模型目录 [$MODELS_ROOT]"
    exit 1
fi

# --- 第四阶段: 核心搜索逻辑 ---
results=$( {
    # 只查找文件，但排除掉内部的 sha256 校验文件夹
    find "$MANIFEST_ROOT" -type f -not -path "*/manifests/sha256/*" | while read -r file; do
        
        # 解析路径：registry.ollama.ai/library/deepseek-r1/70b
        # 我们需要提取最后两个部分作为 model:tag
        rel_path=${file#$MANIFEST_ROOT/}
        
        # 使用数组处理路径
        IFS='/' read -r -a parts <<< "$rel_path"
        
        # 正常的 Ollama 结构至少包含 domain/namespace/model/tag (4层)
        # 或者 domain/model/tag (3层)
        if [ ${#parts[@]} -ge 3 ]; then
            tag=${parts[-1]}
            model=${parts[-2]}
            model_tag="${model}:${tag}"
        else
            continue # 深度不足，说明不是真正的标签文件
        fi

        # 1. 关键字过滤 (不区分大小写)
        if [ -n "$KEYWORD" ]; then
            if [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then continue; fi
        fi

        # 2. 提取 GGUF 权重 Blob (严格匹配 image.model)
        raw_blob=$(grep -A 3 "image.model" "$file" | grep -m 1 -oP '"digest":"\K[^"]+' | sed 's/:/-/g')

        if [ -n "$raw_blob" ]; then
            if [ "$ONLY_PATH" = true ]; then
                echo "$BLOBS_DIR/$raw_blob"
            else
                # 统一输出格式，去除可能存在的冗余前缀
                printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
            fi
        fi
    done
} | sort -u )

# --- 第五阶段: 输出 ---
if [ "$ONLY_PATH" = true ]; then
    [ -n "$results" ] && echo "$results"
else
    echo "使用模型根目录: $MODELS_ROOT"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG" "WEIGHTS BLOB (GGUF)"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    [ -n "$results" ] && echo "$results" || echo "(无匹配结果)"
fi
