#!/bin/bash

# ==============================================================================
# 功能描述: 列出 Ollama 已安装模型的简称及其对应的完整 Blob 哈希值。
#          哈希值采用原始格式显示 (例如: sha256-xxxx...)。
#
# 用法:
#   1. 安装: curl -sL <GitHub_URL>/ollama_blobs.sh | sudo bash
#   2. 运行: sudo ollama_blobs
#
# 环境: 适用于 Fedora/Linux，需具备 sudo 权限以读取 Ollama 服务目录。
# ==============================================================================

# --- 安装逻辑 ---
if [[ "$0" == *"bash"* ]] || [[ "$0" == *"sh"* ]]; then
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 请使用 sudo 执行安装：curl -sL ... | sudo bash"
        exit 1
    fi

    DEST_PATH="/usr/local/bin/ollama_blobs"
    echo "--- 正在安装 ollama_blobs 到 $DEST_PATH ---"

    cat << 'EOF' > "$DEST_PATH"
#!/bin/bash

# ==============================================================================
# 功能: 列出 Ollama 模型及其原始 Blob 哈希 (sha256-...)
# 用法: sudo ollama_blobs
# ==============================================================================

# 自动探测模型存储路径
get_models_dir() {
    # 1. 从运行中的服务进程抓取环境变量
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then echo "$env_path"; return; fi

    # 2. 检查常见的 Linux 系统服务路径
    if [ -d "/usr/share/ollama/.ollama/models" ]; then
        echo "/usr/share/ollama/.ollama/models"
    elif [ -d "/var/lib/ollama/.ollama/models" ]; then
        echo "/var/lib/ollama/.ollama/models"
    else
        # 3. 回退到当前执行 sudo 的用户家目录
        local target_user=${SUDO_USER:-$USER}
        local user_home=$(getent passwd "$target_user" | cut -d: -f6)
        echo "$user_home/.ollama/models"
    fi
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_DIR="$MODELS_ROOT/manifests/registry.ollama.ai"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "错误: 无法定位 Ollama 模型目录。"
    echo "探测路径为: $MODELS_ROOT"
    exit 1
fi

# 打印表头：简称列 50 字符
printf "%-50s %-75s\n" "MODEL TAG (Short)" "RAW BLOB HASH"
printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"

# 遍历 Manifest 索引文件
find "$MANIFEST_DIR" -type f | while read -r file; do
    # 提取并格式化模型简称
    rel_path=${file#$MANIFEST_DIR/}
    model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
    
    # 提取 digest 并将冒号替换为连字符，符合原始文件名格式 (sha256:xxx -> sha256-xxx)
    raw_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1 | sed 's/:/-/g')
    
    if [ -n "$raw_blob" ]; then
        # 打印结果
        printf "%-50.50s %-75s\n" "$model_tag" "$raw_blob"
    fi
done
EOF

    # 设置可执行权限
    chmod +x "$DEST_PATH"
    echo "成功: 脚本已安装到 $DEST_PATH"
    echo "现在你可以直接输入命令运行: sudo ollama_blobs"
    exit 0
fi
