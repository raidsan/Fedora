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
    echo "Usage: ollama_rm <name_or_url> [name2...]"
    exit 1
fi

# Get current model list data
MODELS_DATA=$(ollama list | tail -n +2 | awk '{print $1, $2}')

for INPUT in "$@"; do
    echo "🔍 Searching for: $INPUT"
    
    # 1. Try exact match first
    TARGET_ID=$(echo "$MODELS_DATA" | awk -v t="$INPUT" '$1 == t {print $2}')

    # 2. If not found, try to match the short name within URL strings
    if [ -z "$TARGET_ID" ]; then
        # Look for a URL that ends with the input (e.g., .../library/qwen2.5-coder:32b)
        # We use a regex that matches either exactly or after a slash
        TARGET_ID=$(echo "$MODELS_DATA" | awk -v t="$INPUT" '$1 ~ "/"t"$" {print $2; exit}')
    fi

    if [ -z "$TARGET_ID" ]; then
        echo "❌ Error: Could not find any model matching '$INPUT'."
        continue
    fi

    echo "🆔 Linked to Digest ID: $TARGET_ID"

    # 3. Find ALL tags (aliases and URLs) sharing this same ID
    NAMES_TO_DELETE=$(echo "$MODELS_DATA" | awk -v id="$TARGET_ID" '$2 == id {print $1}')

    echo "🗑️  The following instances will be purged:"
    echo "$NAMES_TO_DELETE"
    echo "-------------------------------------------"

    # 4. Batch delete
    for NAME in $NAMES_TO_DELETE; do
        ollama rm "$NAME"
    done

    echo "✅ Successfully removed all instances of ID ${TARGET_ID:0:12}"
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Smart tool installed to $TARGET_PATH"
}

install_logic
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
