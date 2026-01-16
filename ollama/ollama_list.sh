#!/bin/bash

# --- 1. Installation Logic ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_list"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash

# --- 2. Business Logic ---

# Define Column Widths
FORMAT="%-15s %-45s %-12s %-10s %s\n"

# A. Resource Statistics
TARGET_VRAM=96.0
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# Convert to GB
TOTAL_SYS_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB / 1024 / 1024" | bc)
AVAIL_SYS_RAM_GB=$(echo "scale=1; $AVAIL_RAM_KB / 1024 / 1024" | bc)

# Calculate OS + Apps overhead 
# (Total CPU-visible RAM minus Available RAM minus Ollama's share if running on CPU, 
# but since Ollama runs on GPU/VRAM, it's simpler:)
OS_USAGE_GB=$(echo "scale=1; $TOTAL_SYS_RAM_GB - $AVAIL_SYS_RAM_GB" | bc)

# B. Get Running Models
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

# C. List Models
MODELS_DATA=$(ollama list | tail -n +2 | awk '{print $1, $2, $3$4}')

if [ -z "$MODELS_DATA" ]; then
    echo "📭 No models found."
else
    printf "\033[1m$FORMAT\033[0m" "ID" "SHORT_NAME" "IN_RAM" "SIZE" "MIRROR_URL"
    echo "--------------------------------------------------------------------------------------------------------------------"

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

# D. Resource Dashboard
REMAIN_VRAM=$(echo "scale=1; $TARGET_VRAM - $TOTAL_OLLAMA_RAM_GB" | bc)

echo -e "\n\033[1;34m📊 Resource Summary (128GB Total Physical RAM)\033[0m"
echo "------------------------------------------------------------"
printf "🖥️  GPU VRAM Pool:     %s GB\n" "$TARGET_VRAM"
printf "🧠 AI Models Active:   \033[1;32m%s GB\033[0m (Used from Pool)\n" "$TOTAL_OLLAMA_RAM_GB"
printf "🚀 VRAM Pool Free:     \033[1;36m%s GB\033[0m\n" "$REMAIN_VRAM"
echo "------------------------------------------------------------"
printf "📉 System Avail Mem:   %s GB (OS + Background Apps: %s GB)\n" "$AVAIL_SYS_RAM_GB" "$OS_USAGE_GB"
echo "------------------------------------------------------------"
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Updated tool installed to $TARGET_PATH"
}

install_logic
"$TARGET_PATH"
