#!/bin/bash

# ==============================================================================
# 功能描述: 列出 Ollama 已安装模型的简称及其对应的完整 Blob 哈希值。
#          哈希值采用原始格式显示 (例如: sha256-xxxx...)。
#          模型名称处理：去掉所有 Manifest 根路径，保留模型完整标识。
#
# 用法:
#   1. 安装: curl -sL <GitHub_URL>/ollama_blobs.sh | sudo bash
#   2. 运行: sudo ollama_blobs
# ==============================================================================

# --- 安装逻辑 ---
if [[ "$0" == *"bash"* ]] || [[ "$0" == *"sh"* ]]; then
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 请使用 sudo 执行安装。"
        exit 1
    fi

    DEST_PATH="/usr/local/bin/ollama_blobs"
    echo "--- 正在安装/更新 ollama_blobs 到 $DEST_PATH ---"

    cat << 'EOF' > "$DEST_PATH"
#!/bin/bash

# 自动探测模型存储路径
get_models_dir() {
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then echo "$env_path"; return; fi

    if [ -d "/usr/share/ollama/.ollama/models" ]; then
        echo "/usr/share/ollama/.ollama/models"
    elif [ -d "/var/lib/ollama/.ollama/models" ]; then
        echo "/var/lib/ollama/.ollama/models"
    else
        local target_user=${SUDO_USER:-$USER}
        local user_home=$(getent passwd "$target_user" | cut -d: -f6)
        echo "$user_home/.ollama/models"
    fi
}

MODELS_ROOT=$(get_models_dir)
# 获取 registry 根目录 (如 .../registry.ollama.ai)
REGISTRY_ROOT=$(find "$MODELS_ROOT/manifests" -maxdepth 1 -type d -name "*registry*" | head -n 1)

if [ ! -d "$REGISTRY_ROOT" ]; then
    echo "错误: 无法定位 Manifest 注册表目录。"
    exit 1
fi

# 打印表头
printf "%-50s %-75s\n" "MODEL TAG (Short)" "RAW BLOB HASH"
printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"

# 遍历所有 Manifest 文件
find "$REGISTRY_ROOT" -type f | while read -r file; do
    # 1. 提取相对于注册表根目录的路径
    # 例如: /.../registry.ollama.ai/library/deepseek/latest -> library/deepseek/latest
    rel_path=${file#$REGISTRY_ROOT/}
    
    # 2. 处理简称：
    # 将最后一个斜杠替换为冒号，这样 library/deepseek/latest 变成 library/deepseek:latest
    # 同时保留中间的所有目录级（如 user/folder/model/tag -> user/folder/model:tag）
    model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
    
    # 3. 提取哈希并转换冒号为连字符 (sha256:xxx -> sha256-xxx)
    raw_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1 | sed 's/:/-/g')
    
    if [ -n "$raw_blob" ]; then
        printf "%-50.50s %-75s\n" "$model_tag" "$raw_blob"
    fi
done
EOF

    chmod +x "$DEST_PATH"
    echo "成功！你可以直接运行: sudo ollama_blobs"
    exit 0
fi
