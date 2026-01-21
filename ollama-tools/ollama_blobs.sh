#!/bin/bash

# ==============================================================================
# 功能: 列出所有 Ollama 模型简称及其对应的原始 Blob 哈希 (sha256-xxx)
# 兼容: 支持自定义 OLLAMA_MODELS 路径及各种镜像站域名路径清理
# 管理: 建议通过 github-tools 安装及更新
# ==============================================================================

# --- 第一阶段: 安装逻辑 (当通过 curl | bash 运行或不在目标路径时触发) ---
DEST_PATH="/usr/local/bin/ollama_blobs"

if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 请使用 sudo 权限运行安装。"
        exit 1
    fi
    
    # 将自身脚本内容写入目标路径
    cat "$0" > "$DEST_PATH"
    chmod +x "$DEST_PATH"
    
    echo "ollama_blobs 已成功安装到 $DEST_PATH"
    # 如果是由 github-tools 调用的，安装后会自动记录元数据
    exit 0
fi

# --- 第二阶段: 核心功能逻辑 (作为 /usr/local/bin/ollama_blobs 运行时) ---

# 1. 动态探测 Ollama 模型存储根目录
get_models_dir() {
    # 优先从运行中的 ollama 进程抓取环境变量
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    if [ -d "$env_path" ]; then
        echo "$env_path"
        return
    fi

    # 其次检查 Linux 系统服务默认路径
    if [ -d "/usr/share/ollama/.ollama/models" ]; then
        echo "/usr/share/ollama/.ollama/models"
    elif [ -d "/var/lib/ollama/.ollama/models" ]; then
        echo "/var/lib/ollama/.ollama/models"
    else
        # 最后检查当前用户的家目录
        local target_user=${SUDO_USER:-$USER}
        local user_home=$(getent passwd "$target_user" | cut -d: -f6)
        echo "$user_home/.ollama/models"
    fi
}

MODELS_ROOT=$(get_models_dir)
MANIFEST_ROOT="$MODELS_ROOT/manifests"

if [ ! -d "$MANIFEST_ROOT" ]; then
    echo "错误: 找不到 Ollama 模型目录 (探测路径: $MODELS_ROOT)"
    echo "请确认 Ollama 已安装且至少下载了一个模型。"
    exit 1
fi

# 2. 打印表头 (简称列 50 字符)
printf "%-50s %-75s\n" "MODEL TAG (Short)" "RAW BLOB HASH"
printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"

# 3. 扫描并格式化输出
# 逻辑：在 manifests 目录下寻找所有文件，通过 sed 彻底切除域名路径
find "$MANIFEST_ROOT" -type f 2>/dev/null | while read -r file; do
    
    # 动态切除前缀逻辑：
    # 匹配 .*/manifests/ 及其后的第一个目录(域名段)，只保留后面的模型标识
    # 例如: /.../manifests/ollama.m.daocloud.io/library/deepseek-r1/latest
    # 转换结果: library/deepseek-r1/latest
    rel_path=$(echo "$file" | sed -n 's|.*/manifests/[^/]\+/||p')
    
    # 如果路径解析为空（比如不是合法的 manifest 文件），则跳过
    [ -z "$rel_path" ] && continue
    
    # 格式化模型名称：将最后一个斜杠替换为冒号 (library/deepseek-r1:latest)
    model_tag=$(echo "$rel_path" | sed 's/\/\([^/]*\)$/:\1/')
    
    # 提取 Blob Hash：取 JSON 中的第一个 digest 值，并将冒号换成连字符
    # 匹配结果示例: sha256-c7f3ea903b50b3c9a42221b265ade4375d1bb5e3...
    raw_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1 | sed 's/:/-/g')
    
    if [ -n "$raw_blob" ]; then
        printf "%-50.50s %-75s\n" "$model_tag" "$raw_blob"
    fi
done
