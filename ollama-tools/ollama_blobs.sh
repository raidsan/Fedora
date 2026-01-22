#!/bin/bash

# ==============================================================================
# 名称: ollama_blobs
# 功能: 列出模型及其GGUF权重Blob哈希；支持关键字过滤及路径输出
# 参数:
#   [关键字]        可选，匹配模型名称
#   --blob-path    可选，仅输出匹配到的 Blob 绝对路径 (需配合关键字使用)
# ==============================================================================
#!/bin/bash

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
    # 优先检查探测到的进程环境，其次检查自定义路径
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
    # 遍历 manifests 目录下所有 JSON 文件
    find "$MANIFEST_ROOT" -type f | while read -r file; do
        
        # 1. 提取模型标签名 (处理路径，取最后两级)
        rel_path=${file#$MANIFEST_ROOT/}
        model_tag=$(echo "$rel_path" | awk -F'/' '{if(NF>=2) print $(NF-1)":"$NF}')
        
        [ -z "$model_tag" ] && continue
        model_tag=${model_tag#library/}

        # 2. 关键字过滤
        if [ -n "$KEYWORD" ] && [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then
            continue
        fi

        # 3. 【核心修复】精准提取 GGUF 权重哈希
        # 在 manifest 中，只有 layer 的 mediaType 为 image.model 的才是权重文件
        # 我们寻找匹配 image.model 后紧跟的 digest 行
        raw_blob=$(grep -B 2 "image.model" "$file" | grep "digest" | grep -oP 'sha256:[a-f0-9]+' | sed 's/:/-/g')
        
        # 如果上面的匹配不到（取决于 JSON 格式换行），尝试备选匹配
        if [ -z "$raw_blob" ]; then
            raw_blob=$(grep -A 3 "image.model" "$file" | grep "digest" | grep -oP 'sha256:[a-f0-9]+' | sed 's/:/-/g')
        fi

        # 4. 输出
        if [ -n "$raw_blob" ]; then
            if [ "$ONLY_PATH" = true ]; then
                echo "$BLOBS_DIR/$raw_blob"
            else
                printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
            fi
        fi
    done
} | sort -u )

# --- 最终输出 ---
if [ "$ONLY_PATH" = true ]; then
    [ -n "$results" ] && echo "$results"
else
    echo "使用模型根目录: $MODELS_ROOT"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG" "WEIGHTS BLOB (GGUF)"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    [ -n "$results" ] && echo "$results" || echo "(无匹配结果)"
fi
