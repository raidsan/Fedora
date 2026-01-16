#!/bin/bash

# --- 1. Installation Logic ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_list"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    # Create the script file using Heredoc
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash

# --- 2. Business Logic ---

# Define Column Widths: ID(15), SHORT_NAME(45), IN_RAM(12), SIZE(10)
# This ensures deepseek-coder-v2:16b-lite-instruct-q4_K_M fits perfectly
FORMAT="%-15s %-45s %-12s %-10s %s\n"

# A. VRAM Statistics (Optimized for 96GB allocation on 128GB Strix Halo)
# Target VRAM is the 96GB you assigned to the GPU in BIOS
TARGET_VRAM=96.0

# Calculate current available system memory in GB
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
AVAIL_RAM_GB=$(echo "scale=1; $AVAIL_RAM_KB / 1024 / 1024" | bc)

# B. Get Running Models from Ollama PS
declare -A RUNNING_MEM
TOTAL_OLLAMA_RAM_GB=0

# Read ID, SIZE, and UNIT (e.g., 24 GB)
while read -r R_ID R_SIZE R_UNIT; do
    if [ -n "$R_ID" ]; then
        RUNNING_MEM[$R_ID]="$R_SIZE $R_UNIT"
        # Sum up total VRAM usage by Ollama
        if [[ "$R_UNIT" == "GB" ]]; then
            TOTAL_OLLAMA_RAM_GB=$(echo "$TOTAL_OLLAMA_RAM_GB + $R_SIZE" | bc)
        elif [[ "$R_UNIT" == "MB" ]]; then
            TOTAL_OLLAMA_RAM_GB=$(echo "scale=2; $TOTAL_OLLAMA_RAM_GB + $R_SIZE / 1024" | bc)
        fi
    fi
done < <(ollama ps | tail -n +2 | awk '{print $2, $3, $4}')

# C. Get Local Model List
MODELS_DATA=$(ollama list | tail -n +2 | awk '{print $1, $2, $3$4}')

if [ -z "$MODELS_DATA" ]; then
    echo "📭 No models found in local storage."
else
    # Print Header
    printf "\033[1m$FORMAT\033[0m" "ID" "SHORT_NAME" "IN_RAM" "SIZE" "MIRROR_URL"
    echo "--------------------------------------------------------------------------------------------------------------------"

    declare -A ID_MAP_SHORT
    declare -A ID_MAP_URL
    declare -A ID_MAP_SIZE

    # Group models by their Digest ID
    while read -r NAME ID SIZE; do
        if [[ "$NAME" == *"/"* ]]; then
            ID_MAP_URL[$ID]="${ID_MAP_URL[$ID]} $NAME"
        else
            ID_MAP_SHORT[$ID]="${ID_MAP_SHORT[$ID]} $NAME"
        fi
        ID_MAP_SIZE[$ID]=$SIZE
    done <<< "$MODELS_DATA"

    # Iterate through unique IDs
    for ID in "${!ID_MAP_SIZE[@]}"; do
        SHORT="${ID_MAP_SHORT[$ID]:-Unset}"
        URLS="${ID_MAP_URL[$ID]:-No_Mirror}"
        SIZE="${ID_MAP_SIZE[$ID]}"
        
        # Match against running models
        RAM_USAGE="-"
        for R_ID in "${!RUNNING_MEM[@]}"; do
            if [[ "$ID" == "$R_ID"* ]]; then
                RAM_USAGE="${RUNNING_MEM[$R_ID]}"
                break
            fi
        done

        # Output row with green highlight if model is running
        if [ "$RAM_USAGE" != "-" ]; then
            printf "\033[32m$FORMAT\033[0m" "${ID:0:12}" "$SHORT" "$RAM_USAGE" "$SIZE" "$URLS"
        else
            printf "$FORMAT" "${ID:0:12}" "$SHORT" "$RAM_USAGE" "$SIZE" "$URLS"
        fi
    done
fi

# D. Resource Summary Dashboard
# Remaining VRAM is Target (96) minus what Ollama is currently using
REMAIN_VRAM=$(echo "scale=1; $TARGET_VRAM - $TOTAL_OLLAMA_RAM_GB" | bc)

echo -e "\n\033[1;34m📊 VRAM Resource Summary (AMD Strix Halo Unified Memory)\033[0m"
echo "------------------------------------------------------------"
printf "🖥️  Total VRAM Pool:   %s GB (from 128G Physical RAM)\n" "$TARGET_VRAM"
printf "🧠 AI Models Loaded:   \033[1;32m%s GB\033[0m\n" "$TOTAL_OLLAMA_RAM_GB"
printf "🚀 VRAM Pool Free:     \033[1;36m%s GB\033[0m\n" "$REMAIN_VRAM"
printf "📉 System Avail Mem:   %s GB (OS + Background Apps)\n" "$AVAIL_RAM_GB"
echo "------------------------------------------------------------"

# E. Alias Suggestion Logic
for ID in "${!ID_MAP_SIZE[@]}"; do
    SHORT="${ID_MAP_SHORT[$ID]:-Unset}"
    if [[ "$SHORT" == "Unset" ]]; then
        URLS="${ID_MAP_URL[$ID]}"
        FIRST_URL=$(echo $URLS | awk '{print $1}')
        SUGGESTED_NAME=$(echo $FIRST_URL | awk -F'/' '{print $3}')
        [ -z "$SUGGESTED_NAME" ] && SUGGESTED_NAME=$(basename "$FIRST_URL")
        echo -e "\n💡 New mirror found. Suggestion: \033[33mollama cp $FIRST_URL $SUGGESTED_NAME\033[0m"
    fi
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Tool installed to $TARGET_PATH"
}

# Run installation
install_logic
# Execute the tool immediately
"$TARGET_PATH"
