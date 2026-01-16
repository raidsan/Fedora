#!/bin/bash

# --- 1. Installation Logic ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_rm"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash

# --- 2. Business Logic ---

if [ $# -eq 0 ]; then
    echo "Usage: ollama_rm <model_name_or_url> [model2...]"
    exit 1
fi

# Get current model list data
# Format: Name  ID
MODELS_DATA=$(ollama list | tail -n +2 | awk '{print $1, $2}')

for TARGET in "$@"; do
    echo "🔍 Searching for all instances of: $TARGET"
    
    # 1. Find the ID of the target model
    # Note: Using awk to find the exact match in the first column and return the second
    TARGET_ID=$(echo "$MODELS_DATA" | awk -v t="$TARGET" '$1 == t {print $2}')

    if [ -z "$TARGET_ID" ]; then
        echo "❌ Error: Model '$TARGET' not found in local storage."
        continue
    fi

    echo "🆔 Found Digest ID: $TARGET_ID"

    # 2. Find all names (aliases/URLs) sharing this same ID
    NAMES_TO_DELETE=$(echo "$MODELS_DATA" | awk -v id="$TARGET_ID" '$2 == id {print $1}')

    echo "🗑️  The following tags will be removed:"
    echo "$NAMES_TO_DELETE"
    echo "-------------------------------------------"

    # 3. Batch delete
    for NAME in $NAMES_TO_DELETE; do
        echo "Removing $NAME..."
        ollama rm "$NAME"
    done

    echo "✅ Successfully wiped all instances of ID ${TARGET_ID:0:12}"
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Tool installed to $TARGET_PATH"
}

# Run installation
install_logic
# If parameters were passed to the installer, run the script immediately
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
