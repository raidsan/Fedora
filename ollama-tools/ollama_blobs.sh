#!/bin/bash

# ==============================================================================
# 功能: 列出所有 Ollama 模型简称及其对应的原始 Blob 哈希 (sha256-xxx)
# 特点: 自动隐藏默认的 library/ 前缀，使输出与 ollama list 一致
# 管理: 建议通过 github-tools 安装及更新
# ==============================================================================

DEST_PATH="/usr/local/bin/ollama_blobs"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "ollama_blobs 已成功安装到 $DEST_PATH"
    exit 0
fi

# --- 第二阶段: 核心功能逻辑 ---

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

# 输出根目录信息
echo "Ollama 模型根目录: $MODELS_ROOT"
echo ""

if [ ! -d "$MANIFEST_ROOT" ]; then
    echo "错误: 无法定位 Manifests 目录。"
    exit 1
fi

# 打印表头
printf "%-50s %-75s\n" "MODEL TAG (Short)" "RAW BLOB HASH"
printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"

find "$MANIFEST_ROOT" -type f 2>/dev/null | while read -r file; do
    # 1. 切除域名路径
    rel_path=$(echo "$file" | sed -n 's|.*/manifests/[^/]\+/||p')
    [ -z "$rel_path" ] && continue
    
    # 2. 格式化标签 (最后斜杠换冒号)
    model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
    
    # 3. 核心改进：仿照 ollama list 逻辑，隐藏默认的 library/ 前缀
    # 只有当模型在 library 目录下时才切除，自定义用户目录保留
    model_tag=${model_tag#library/}
    
    # 4. 提取 Blob Hash
    raw_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1 | sed 's/:/-/g')
    
    if [ -n "$raw_blob" ]; then
        printf "%-50.50s %-75s\n" "$model_tag" "$raw_blob"
    fi
done
