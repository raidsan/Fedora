#!/bin/bash

# ==============================================================================
# 名称: ollama_blobs
# 功能: 列出模型及其权重 Blob 哈希；支持关键字过滤及路径输出
# 参数:
#   [关键字]        可选，匹配模型名称
#   --blob-path    可选，仅输出匹配到的 Blob 绝对路径 (需配合关键字使用)
# ==============================================================================

DEST_PATH="/usr/local/bin/ollama_blobs"

# --- 第一阶段: 安装逻辑 (供 github-tools 使用) ---
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
    if [ "$arg" == "--blob-path" ]; then
        ONLY_PATH=true
    else
        KEYWORD="$arg"
    fi
done

# --- 第三阶段: 核心逻辑 ---

get_models_dir() {
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then echo "$env_path"; return; fi
    if [ -d "/usr/share/ollama/.ollama/models" ]; then
        echo "/usr/share/ollama/.ollama/models"
    elif [ -d "/var/lib/ollama/.ollama/models" ]; then
        echo "/var/lib/ollama/.ollama/models"
    else
        local user_home=$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)
        echo "$user_home/.ollama/models"
    fi
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_ROOT="$MODELS_ROOT/manifests"
BLOBS_DIR="$MODELS_ROOT/blobs"

if [ ! -d "$MANIFEST_ROOT" ]; then
    [ "$ONLY_PATH" = false ] && echo "错误: 无法定位 Manifests 目录。"
    exit 1
fi

# 收集匹配的结果
results=$( {
    find "$MANIFEST_ROOT" -type f 2>/dev/null | while read -r file; do
        # 1. 切除域名路径
        rel_path=$(echo "$file" | sed -n 's|.*/manifests/[^/]\+/||p')
        [ -z "$rel_path" ] && continue
        
        # 2. 格式化并去掉 library/
        model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
        model_tag=${model_tag#library/}
        
        # 3. 关键字过滤 (如果提供了关键字)
        if [ -n "$KEYWORD" ]; then
            if [[ ! "$model_tag" =~ "$KEYWORD" ]]; then
                continue
            fi
        fi

        # 4. 提取 Model 类型的 Blob
        raw_blob=$(grep -B 2 'image.model' "$file" | grep -oP '"digest":"\K[^"]+' | head -n 1 | sed 's/:/-/g')
        if [ -z "$raw_blob" ]; then
            raw_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1 | sed 's/:/-/g')
        fi
        
        if [ -n "$raw_blob" ]; then
            if [ "$ONLY_PATH" = true ]; then
                # 仅输出路径模式：输出绝对路径
                echo "$BLOBS_DIR/$raw_blob"
            else
                # 普通表格模式
                printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
            fi
        fi
    done
} | sort -u )

# --- 第四阶段: 输出控制 ---
if [ "$ONLY_PATH" = true ]; then
    # 直接输出路径列表，不带表头
    if [ -n "$results" ]; then
        echo "$results"
    fi
else
    # 输出完整表格
    echo "Ollama 模型根目录: $MODELS_ROOT"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG (Short)" "DATA BLOB HASH"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    if [ -n "$results" ]; then
        echo "$results"
    else
        echo "(无匹配模型)"
    fi
fi
