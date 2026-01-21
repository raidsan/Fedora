#!/bin/bash
# need sudo

# 确保即使在 sudo 下也能找到真正的用户家目录
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
INSTALL_DIR="$REAL_HOME/bin"
SCRIPT_NAME="ollama_blobs"
DEST_PATH="$INSTALL_DIR/$SCRIPT_NAME"

# --- 安装逻辑 (当直接通过 pipe 执行时) ---
if [[ "$0" == *"bash"* ]] || [[ "$0" == *"sh"* ]]; then
    echo "正在以 root 权限进行安装配置..."
    mkdir -p "$INSTALL_DIR"

    # 将功能代码写入目标文件
    cat << 'EOF' > "$DEST_PATH"
#!/bin/bash

# 自动探测模型路径
get_models_dir() {
    # 1. 探测 OLLAMA_MODELS 环境变量 (从服务进程中抓取)
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    [ -d "$env_path" ] && echo "$env_path" && return

    # 2. 默认系统服务路径
    [ -d "/usr/share/ollama/.ollama/models" ] && echo "/usr/share/ollama/.ollama/models" && return
    
    # 3. 默认用户路径 (需考虑 sudo 情况)
    local target_user=${SUDO_USER:-$USER}
    local user_home=$(getent passwd "$target_user" | cut -d: -f6)
    [ -d "$user_home/.ollama/models" ] && echo "$user_home/.ollama/models" && return
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_DIR="$MODELS_ROOT/manifests/registry.ollama.ai"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "错误: 找不到 Manifests 目录于: $MANIFEST_DIR"
    exit 1
fi

# 打印对齐格式的输出
printf "%-40s %-64s\n" "MODEL TAG (Short)" "BLOB HASH"
printf "%-40s %-64s\n" "----------------------------------------" "----------------------------------------------------------------"

find "$MANIFEST_DIR" -type f | while read -r file; do
    # 简称处理: 去掉前缀并格式化标签
    rel_path=${file#$MANIFEST_DIR/}
    model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
    
    # 提取 Config Blob
    blob=$(grep -oP '"digest":"sha256:\K[a-f0-9]{64}' "$file" | head -n 1)
    
    if [ -n "$blob" ]; then
        printf "%-40.40s %-64s\n" "$model_tag" "$blob"
    fi
done
EOF

    # 修正文件所属权为普通用户并设为可执行
    chown "$REAL_USER:$REAL_USER" "$DEST_PATH"
    chmod +x "$DEST_PATH"

    # 检查 PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "提示: $INSTALL_DIR 尚未加入 PATH。"
        echo "请手动执行: echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> $REAL_HOME/.bashrc"
    fi
    echo "安装完成！请执行 'sudo $SCRIPT_NAME' 来查看模型 Blobs。"
    exit 0
fi
