#!/bin/bash

# --- 1. 安装逻辑 ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_list"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash

# --- 2. 业务逻辑：识别管理与显存统计 ---

# A. 获取系统总内存和可用内存 (Fedora/Linux)
# 获取的是 kB，转换成 GB
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB / 1024 / 1024" | bc)
AVAIL_RAM_GB=$(echo "scale=1; $AVAIL_RAM_KB / 1024 / 1024" | bc)

# B. 获取当前正在运行的模型 (ID 和 占用内存)
declare -A RUNNING_MEM
TOTAL_OLLAMA_RAM_GB=0

while read -r R_ID R_SIZE R_UNIT; do
    if [ -n "$R_ID" ]; then
        RUNNING_MEM[$R_ID]="$R_SIZE $R_UNIT"
        # 统计总占用 (统一转换为 GB)
        if [[ "$R_UNIT" == "GB" ]]; then
            TOTAL_OLLAMA_RAM_GB=$(echo "$TOTAL_OLLAMA_RAM_GB + $R_SIZE" | bc)
        elif [[ "$R_UNIT" == "MB" ]]; then
            TOTAL_OLLAMA_RAM_GB=$(echo "scale=2; $TOTAL_OLLAMA_RAM_GB + $R_SIZE / 1024" | bc)
        fi
    fi
done < <(ollama ps | tail -n +2 | awk '{print $2, $3, $4}')

# C. 获取已下载模型列表
MODELS_DATA=$(ollama list | tail -n +2 | awk '{print $1, $2, $3$4}')

if [ -z "$MODELS_DATA" ]; then
    echo "📭 目前还没有下载任何模型。"
else
    # 打印表头
    echo -e "\033[1mID\t\tSHORT_NAME\t\tIN_RAM\t\tSIZE\t\tMIRROR_URL\033[0m"
    echo "--------------------------------------------------------------------------------------------"

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
            echo -e "\033[32m${ID:0:12}\t${SHORT}\t${RAM_USAGE}\t${SIZE}\t${URLS}\033[0m"
        else
            echo -e "${ID:0:12}\t${SHORT}\t${RAM_USAGE}\t${SIZE}\t${URLS}"
        fi
    done
fi

# D. 总结看板
USED_SYSTEM_RAM=$(echo "scale=1; $TOTAL_RAM_GB - $AVAIL_RAM_GB" | bc)

echo -e "\n\033[1;34m📊 显存资源总结 (AMD Strix Halo 统一内存)\033[0m"
echo "------------------------------------------------"
echo -e "🖥️  系统总显存: ${TOTAL_RAM_GB} GB"
echo -e "🧠 Ollama 模型占用: \033[1;32m${TOTAL_OLLAMA_RAM_GB} GB\033[0m"
echo -e "📉 系统总已用 (含Ollama): ${USED_SYSTEM_RAM} GB"
echo -e "🚀 当前可用剩余: \033[1;36m${AVAIL_RAM_GB} GB\033[0m"
echo "------------------------------------------------"

# E. 别名引导逻辑 (仅在没有参数时触发)
for ID in "${!ID_MAP_SIZE[@]}"; do
    SHORT="${ID_MAP_SHORT[$ID]:-未创建}"
    if [[ "$SHORT" == "未创建" ]]; then
        URLS="${ID_MAP_URL[$ID]}"
        FIRST_URL=$(echo $URLS | awk '{print $1}')
        SUGGESTED_NAME=$(echo $FIRST_URL | awk -F'/' '{print $3}')
        [ -z "$SUGGESTED_NAME" ] && SUGGESTED_NAME=$(basename "$FIRST_URL")
        echo -e "\n发现新镜像模型，建议创建别名: \033[33mollama cp $FIRST_URL $SUGGESTED_NAME\033[0m"
    fi
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "🚀 统计增强版 ollama_list 已安装。"
}

install_logic
"$TARGET_PATH"
