#!/bin/bash

# ==============================================================================
# 名称: ollama_blobs
# 功能: 列出模型及其权重 Blob 哈希；支持关键字过滤及路径输出
# 参数:
#   [关键字]        可选，匹配模型名称
#   --blob-path    可选，仅输出匹配到的 Blob 绝对路径 (需配合关键字使用)
# ==============================================================================

DEST_PATH="/usr/local/bin/ollama_blobs"

# --- 第一阶段: 安装逻辑 ---
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
        # 允许传入关键字，且不区分大小写进行匹配
        KEYWORD="$arg"
    fi
done

# --- 第三阶段: 核心逻辑 ---

get_models_dir() {
    # 尝试从进程获取 (需要 sudo)
    local env_path=$(strings /proc/$(pgrep -x ollama | head -n 1)/environ 2>/dev/null | grep OLLAMA_MODELS | cut -d= -f2)
    
    if [ -d "$env_path" ]; then
        echo "$env_path"
        return
    fi

    # 如果没找到且不是 root，提示用户
    if [ "$EUID" -ne 0 ] && [ "$ONLY_PATH" = false ]; then
        echo "提示: 非 root 运行，无法读取 Ollama 进程环境。尝试默认路径..." >&2
    fi

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
    [ "$ONLY_PATH" = false ] && echo "错误: 无法定位 Manifests 目录 [$MANIFEST_ROOT]"
    exit 1
fi

# 核心搜索与过滤
results=$( {
    # 这里的 -ipath 是为了兼容某些深层路径
    find "$MANIFEST_ROOT" -type f 2>/dev/null | while read -r file; do
        # 1. 获取相对路径并规范化标签
        # 去掉 manifests/ 及其后的域名层
        rel_name=$(echo "$file" | sed "s|^$MANIFEST_ROOT/||" | sed 's|[^/]*/||')
        
        # 将最后的斜杠换成冒号 (如 library/qwen/latest -> library/qwen:latest)
        model_tag=$(echo "$rel_name" | sed 's/\/\([^/]*\)$/:\1/')
        
        # 统一去掉 library/ 前缀
        model_tag=${model_tag#library/}
        
        # 2. 严格关键字过滤 (不区分大小写)
        if [ -n "$KEYWORD" ]; then
            if [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then
                continue
            fi
        fi

        # 3. 提取对应的权重 Blob
        raw_blob=$(grep -B 2 'image.model' "$file" | grep -oP '"digest":"\K[^"]+' | head -n 1 | sed 's/:/-/g')
        [ -z "$raw_blob" ] && raw_blob=$(grep -oP '"digest":"\K[^"]+' "$file" | head -n 1 | sed 's/:/-/g')
        
        if [ -n "$raw_blob" ]; then
            if [ "$ONLY_PATH" = true ]; then
                echo "$BLOBS_DIR/$raw_blob"
            else
                printf "%-50s %-75s\n" "$model_tag" "$raw_blob"
            fi
        fi
    done
} | sort -u )

# --- 第四阶段: 输出 ---
if [ "$ONLY_PATH" = true ]; then
    [ -n "$results" ] && echo "$results"
else
    echo "Ollama 模型根目录: $MODELS_ROOT"
    echo ""
    printf "%-50s %-75s\n" "MODEL TAG (Short)" "DATA BLOB HASH"
    printf "%-50s %-75s\n" "--------------------------------------------------" "---------------------------------------------------------------------------"
    [ -n "$results" ] && echo "$results" || echo "(无匹配结果)"
fi
