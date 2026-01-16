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
    echo "Usage: ollama_rm <model_name_or_url> [name2...]"
    exit 1
fi

# Step 1: Pre-process and parse the local model list
# We create a structured list in memory: [Full_Name] [ID] [Extracted_Short_Name]
raw_list=$(ollama list | tail -n +2 | awk '{print $1, $2}')
parsed_db=$(echo "$raw_list" | while read -r FULL_NAME ID; do
    # Correctly extract short name by taking the last part after any slashes
    if [[ "$FULL_NAME" == *"/"* ]]; then
        SHORT_NAME="${FULL_NAME##*/}"
    else
        SHORT_NAME="$FULL_NAME"
    fi
    echo "$FULL_NAME $ID $SHORT_NAME"
done)

for INPUT in "$@"; do
    echo "🔍 Processing input: $INPUT"
    
    # Step 2: Search for Digest ID
    # Using 'user_input' instead of 'in' to avoid awk reserved word error
    TARGET_ID=$(echo "$parsed_db" | awk -v user_input="$INPUT" '$1 == user_input || $3 == user_input {print $2; exit}')

    if [ -z "$TARGET_ID" ]; then
        echo "❌ Error: No local model matches '$INPUT'."
        continue
    fi

    echo "🆔 Linked to Digest ID: $TARGET_ID"

    # Step 3: Identify all associated tags
    NAMES_TO_DELETE=$(echo "$raw_list" | awk -v id="$TARGET_ID" '$2 == id {print $1}')

    echo "🗑️  Purging all associated tags:"
    echo "$NAMES_TO_DELETE"
    echo "-------------------------------------------"

    # Step 4: Batch Removal
    for NAME in $NAMES_TO_DELETE; do
        ollama rm "$NAME"
    done

    echo "✅ Successfully wiped all instances of ID ${TARGET_ID:0:12}"
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Fixed tool installed to $TARGET_PATH"
}

install_logic
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
