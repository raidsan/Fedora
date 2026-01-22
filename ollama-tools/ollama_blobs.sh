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

# --- 安装逻辑 (保留源码原始逻辑) ---
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
MODELS_ROOT="/storage/models"
[ ! -d "$MODELS_ROOT" ] && MODELS_ROOT="/usr/share/ollama/.ollama/models"
MANIFEST_ROOT="$MODELS_ROOT/manifests"
BLOBS_DIR="$MODELS_ROOT/blobs"

# --- 核心搜索逻辑 ---
results=$( {
    # 查找 manifests 目录下所有文件
    find "$MANIFEST_ROOT" -type f | while read -r file; do
        
        # 1. 解析模型标签
        rel_path=${file#$MANIFEST_ROOT/}
        # 提取最后两级目录作为 模型:标签
        model_tag=$(echo "$rel_path" | awk -F'/' '{if(NF>=2) print $(NF-1)":"$NF}')
        
        # 【关键修复：空串过滤】
        # 1. 检查是否为空 (使用双引号并移除空格干扰)
        # 2. 检查是否包含冒号 (合法标签必须包含 :)
        if [[ -z "${model_tag// }" ]] || [[ ! "$model_tag" == *":"* ]]; then
            continue
        fi

        # 移除 library/ 前缀简化输出
        model_tag=${model_tag#library/}

        # 2. 关键字过滤
        if [ -n "$KEYWORD" ]; then
            if [[ ! "${model_tag,,}" =~ "${KEYWORD,,}" ]]; then
                continue
            fi
        fi

        # 3. 精准提取权重哈希
        # 针对 Manifest JSON 结构，只提取 mediaType 为 application/vnd.ollama.image.model 的层
        raw_blob=$(cat "$file" | tr -d '\n' | grep -oP '\{[^{}]*?"mediaType":"application/vnd.ollama.image.model"[^{}]*?\}' | grep -oP 'sha256:[a-f0-9]+' | head -n 1 | sed 's/:/-/g')

        # 4. 打印保护：只有名字和哈希同时存在才输出
        if [ -n "$model_tag" ] && [ -n "$raw_blob" ]; then
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
