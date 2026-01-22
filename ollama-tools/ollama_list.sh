#!/bin/bash

# ==============================================================================
# 名称: ollama_list
# 用途: 列出本地模型，关联镜像地址，并显示 GPU/系统内存看板
# ==============================================================================

DEST_PATH="/usr/local/bin/ollama_list"

# --- 第一阶段: 安装逻辑 ---
if [ "$(realpath "$0" 2>/dev/null)" != "$DEST_PATH" ] && [[ "$0" =~ (bash|sh|/tmp/.*)$ ]] || [ ! -f "$0" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误: 请使用 sudo 权限运行安装。"; exit 1; fi
    cat "$0" > "$DEST_PATH" && chmod +x "$DEST_PATH"
    echo "ollama_list 已成功安装。"
    exit 0
fi

# --- 第二阶段: 业务逻辑 ---

# 定义列宽
FORMAT="%-15s %-45s %-12s %-10s %s\n"

# A. 资源统计
TARGET_VRAM=96.0
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# 转换单位为 GB (带 1 位小数)
TOTAL_SYS_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB / 1048576" | bc)
AVAIL_SYS_RAM_GB=$(echo "scale=1; $AVAIL_RAM_KB / 1048576" | bc)

# 计算 OS + 应用开销 (处理 bc 可能产生的 .5 格式为 0.5)
OS_USAGE_GB=$(echo "scale=1; $TOTAL_SYS_RAM_GB - $AVAIL_SYS_RAM_GB" | bc | sed 's/^\./0./')

# B. 获取当前运行中的模型信息
declare -A RUNNING_MEM
TOTAL_OLLAMA_RAM_GB=0
while read -r R_ID R_SIZE R_UNIT; do
    if [ -n "$R_ID" ]; then
        RUNNING_MEM[$R_ID]="$R_SIZE $R_UNIT"
        if [[ "$R_UNIT" == "GB" ]]; then
            TOTAL_OLLAMA_RAM_GB=$(echo "$TOTAL_OLLAMA_RAM_GB + $R_SIZE" | bc)
        elif [[ "$R_UNIT" == "MB" ]]; then
            TOTAL_OLLAMA_RAM_GB=$(echo "scale=2; $TOTAL_OLLAMA_RAM_GB + $R_SIZE / 1024" | bc)
        fi
    fi
done < <(ollama ps 2>/dev/null | tail -n +2 | awk '{print $2, $3, $4}')

# C. 列出模型列表
MODELS_DATA=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1, $2, $3$4}')

if [ -z "$MODELS_DATA" ]; then
    echo "📭 未发现本地模型。"
else
    printf "\033[1m$FORMAT\033[0m" "ID" "SHORT_NAME" "IN_RAM" "SIZE" "MIRROR_URL"
    printf -- "--------------------------------------------------------------------------------------------------------------------\n"

    declare -A ID_MAP_SHORT
    declare -A ID_MAP_URL
    declare -A ID_MAP_SIZE
    
    while read -r NAME ID SIZE; do
        if [[ "$NAME" == *"/"* ]]; then
            ID_MAP_URL[$ID]="${ID_MAP_URL[$ID]} $NAME"
        else
            ID_MAP_SHORT[$ID]="${ID_MAP_SHORT[$ID]} $NAME"
        fi
        ID_MAP_SIZE[$ID]=$SIZE
    done <<< "$MODELS_DATA"

    for ID in "${!ID_MAP_SIZE[@]}"; do
        SHORT="${ID_MAP_SHORT[$ID]:-Unset}"
        URLS="${ID_MAP_URL[$ID]:-No_Mirror}"
        SIZE="${ID_MAP_SIZE[$ID]}"
        
        RAM_USAGE="-"
        # 通过前缀匹配 ID (支持短 ID 关联)
        for R_ID in "${!RUNNING_MEM[@]}"; do
            if [[ "$ID" == "$R_ID"* ]]; then
                RAM_USAGE="${RUNNING_MEM[$R_ID]}"
                break
            fi
        done

        if [ "$RAM_USAGE" != "-" ]; then
            printf "\033[32m$FORMAT\033[0m" "${ID:0:12}" "$SHORT" "$RAM_USAGE" "$SIZE" "$URLS"
        else
            printf "$FORMAT" "${ID:0:12}" "$SHORT" "$RAM_USAGE" "$SIZE" "$URLS"
        fi
    done
fi

# D. 资源 Dashboard 看板
# 处理小数显示格式
TOTAL_OLLAMA_RAM_GB=$(echo "$TOTAL_OLLAMA_RAM_GB" | sed 's/^\./0./;s/^$/0/')
REMAIN_VRAM=$(echo "scale=1; $TARGET_VRAM - $TOTAL_OLLAMA_RAM_GB" | bc | sed 's/^\./0./')

echo -e "\n\033[1;34m📊 资源概览 (128GB 物理内存)\033[0m"
printf -- "------------------------------------------------------------\n"
printf "🖥️  GPU VRAM 共享池:    %s GB\n" "$TARGET_VRAM"
printf "🧠 AI 模型当前占用:    \033[1;32m%s GB\033[0m (Active)\n" "$TOTAL_OLLAMA_RAM_GB"
printf "🚀 可用 VRAM 空间:     \033[1;36m%s GB\033[0m\n" "$REMAIN_VRAM"
printf -- "------------------------------------------------------------\n"
printf "📉 系统可用内存:       %s GB (OS+后台应用占用: %s GB)\n" "$AVAIL_SYS_RAM_GB" "$OS_USAGE_GB"
printf -- "------------------------------------------------------------\n"
