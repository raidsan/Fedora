#!/bin/bash

# --- 1. 安装逻辑 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_list"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash

# --- 2. 业务逻辑 ---

# 定义列宽：ID(12), SHORT_NAME(45), IN_RAM(12), SIZE(10)
FORMAT="%-15s %-45s %-12s %-10s %s\n"

# A. 显存统计逻辑 (针对 96GB Strix Halo 优化)
# 使用 free -g 直接获取以 GB 为单位的整数，或用 meminfo 换算
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
# 如果 free -g 识别不到 96G（有时内核预留给显卡后系统只看剩的），改用精确换算
if [ "$TOTAL_RAM_GB" -lt 80 ]; then
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB / 1024 / 1024" | bc)
fi

AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
AVAIL_RAM_GB=$(echo "scale=1; $AVAIL_RAM_KB / 1024 / 1024" | bc)

# B. 获取运行中的模型
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
done < <(ollama ps | tail -n +2 | awk '{print $2, $3, $4}')

# C. 列表显示
MODELS_DATA=$(ollama list | tail -n +2 | awk '{print $1, $2, $3$4}')

if [ -z "$MODELS_DATA" ]; then
    echo "📭 暂无模型。"
else
    printf "$FORMAT" "ID" "SHORT_NAME" "IN_RAM" "SIZE" "MIRROR_URL"
    echo "------------------------------------------------------------------------------------------------------------"

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
        SHORT="${ID_MAP_SHORT[$ID]:-未创建}"
        URLS="${ID_MAP_URL[$ID]:-无镜像源}"
        SIZE="${ID_MAP_SIZE[$ID]}"
        
        RAM_USAGE="-"
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

# D. 总结看板
USED_SYSTEM_RAM=$(echo "scale=1; $TOTAL_RAM_GB - $AVAIL_RAM_GB" | bc)
echo -e "\n\033[1;34m📊 显存资源总结 (AMD Strix Halo 96GB 统一内存)\033[0m"
echo "------------------------------------------------"
printf "🖥️  系统总容量:   %s GB\n" "$TOTAL_RAM_GB"
printf "🧠 大模型已分配: \033[1;32m%s GB\033[0m\n" "$TOTAL_OLLAMA_RAM_GB"
printf "📉 总已用(系统+AI): %s GB\n" "$USED_SYSTEM_RAM"
printf "🚀 当前可分配剩余: \033[1;36m%s GB\033[0m\n" "$AVAIL_RAM_GB"
echo "------------------------------------------------"
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "🚀 优化版 ollama_list 已重新安装。"
}

install_logic
"$TARGET_PATH"
