#!/bin/bash

# --- 安装逻辑 ---
# 检查是否以 sudo 执行安装
if [[ "$0" == *"bash"* ]] || [[ "$0" == *"sh"* ]]; then
    if [ "$EUID" -ne 0 ]; then
        echo "请使用 sudo 执行安装：curl -sL ... | sudo bash"
        exit 1
    fi

    DEST_PATH="/usr/local/bin/ollama_blobs"

    echo "--- 正在安装 ollama_blobs 到 $DEST_PATH ---"

    cat << 'EOF' > "$DEST_PATH"
#!/bin/bash

# 自动探测模型路径
get_models_dir() {
    # 1. 尝试从运行中的服务抓取环境变量
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then echo "$env_path"; return; fi

    # 2. 检查常见的系统服务路径
    if [ -d "/usr/share/ollama/.ollama/models" ]; then
        echo "/usr/share/ollama/.ollama/models"
    elif [ -d "/var/lib/ollama/.ollama/models" ]; then
        echo "/var/lib/ollama/.ollama/models"
    else
        # 3. 回退到当前用户家目录
        local target_user=${SUDO_USER:-$USER}
        local user_home=$(getent passwd "$target_user" | cut -d: -f6)
        echo "$user_home/.ollama/models"
    fi
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_DIR="$MODELS_ROOT/manifests/registry.ollama.ai"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "错误: 无法定位 Ollama 模型目录。"
    echo "探测到的路径为: $MODELS_ROOT"
    exit 1
fi

# 打印表头：简称列 50 字符，哈希列包含 sha256: 完整前缀
printf "%-50s %-75s\n" "MODEL TAG (Short)" "FULL BLOB HASH"
printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"

# 遍历 Manifests
find "$MANIFEST_DIR" -type f | while read -r file; do
    # 提取简称
    rel_path=${file#$MANIFEST_DIR/}
    # 处理层级结构，将最后一个 / 换成 : (例如 library/llama3/latest -> library/llama3:latest)
    model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
    
    # 提取完整的 digest (包含 sha256: 前缀)
    full_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1)
    
    if [ -n "$full_blob" ]; then
        # 使用 %-50.50s 确保对齐，超过 50 位则截断
        printf "%-50.50s %-75s\n" "$model_tag" "$full_blob"
    fi
done
EOF

    # 设置可执行权限
    chmod +x "$DEST_PATH"
    echo "安装成功！现在你可以直接在任何地方运行: sudo ollama_blobs"
    exit 0
fi
