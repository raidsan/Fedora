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
    # 1. 优先检查是否有环境变量设置 (手动指定)
    if [ -n "$OLLAMA_MODELS" ] && [ -d "$OLLAMA_MODELS" ]; then
        echo "$OLLAMA_MODELS"
        return
    fi

    # 2. 尝试从运行中的进程探测
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then
        echo "$env_path"
        return
    fi

    # 3. 常见路径硬编码兜底 (针对你的特殊路径)
    local common_paths=("/storage/models" "/usr/share/ollama/.ollama/models" "/var/lib/ollama/.ollama/models")
    for p in "${common_paths[@]}"; do
        [ -d "$p/manifests" ] && echo "$p" && return
    done

    # 4. 用户家目录兜底
    echo "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/.ollama/models"
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_ROOT="$MODELS_ROOT/manifests"
BLOBS_DIR="$MODELS_ROOT/blobs"

# --- 第四阶段: 核心搜索逻辑 ---

# 预检
if [ ! -d "$MANIFEST_ROOT" ]; then
    [ "$ONLY_PATH" = false ] && echo "错误: 无法定位 Manifests 目录 [$MANIFEST_ROOT]"
    exit 1
fi

results=$( {
    # 仅在 manifests 目录下递归查找文件
    find "$MANIFEST_ROOT" -type f | while read -r file; do
        # 提取模型名称
        # 处理逻辑：去掉前缀路径，保留 registry/name/tag，并将最后一个 / 换成 :
        rel_path=${file#$MANIFEST_ROOT/}
        # 去掉最前面的域名部分 (如 registry.ollama.ai/)
        model_tag=$(echo "$rel_path" | cut -d/ -f2-)
        # 统一格式：将最后一个 / 换成 :，去掉 library/
        model_tag=$(echo "$model_tag" | sed 's/\//:/g' | sed 's/^library://')
        
        # 1. 严格检查 model_tag 是否为空
        [ -z "$model_tag" ] && continue

        # 2. 关键字过滤
        if [ -n "$KEYWORD" ]; then
            if [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then
                continue
            fi
        fi

        # 3. 提取 GGUF 权重 Blob (严格匹配 image.model 类型)
        # 逻辑：在 manifests 文件里找到 image.model 标记，取其紧随其后的 digest
        raw_blob=$(grep -A 3 "image.model" "$file" | grep -m 1 -oP '"digest":"\K[^"]+' | sed 's/:/-/g')

        # 4. 只有当 tag 和 blob 同时存在时才输出
        if [ -n "$model_tag" ] && [ -n "$raw_blob" ]; then
            if [ "$ONLY_PATH" = true ]; then
                echo "$BLOBS_DIR/$raw_blob"
            else
                printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
            fi
        fi
    done
} | sort -u )

# --- 第五阶段: 最终输出 ---
if [ "$ONLY_PATH" = true ]; then
    [ -n "$results" ] && echo "$results"
else
    echo "使用模型根目录: $MODELS_ROOT"
    [ "$EUID" -ne 0 ] && echo "提示: 非 sudo 运行，如果结果不全，请尝试使用 sudo。"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG" "WEIGHTS BLOB (GGUF)"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    [ -n "$results" ] && echo "$results" || echo "(无匹配结果)"
fi
