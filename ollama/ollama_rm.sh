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
# We create a temporary structured list: [Full_Name] [ID] [Extracted_Short_Name]
raw_list=$(ollama list | tail -n +2 | awk '{print $1, $2}')
parsed_db=$(echo "$raw_list" | while read -r FULL_NAME ID; do
    # Extract short name: if it's a URL, take the last part; otherwise, use it as is
    if [[ "$FULL_NAME" == *"/"* ]]; then
        SHORT_NAME=$(echo "$FULL_NAME" | awk -F'/' '{print $NF}')
    else
        SHORT_NAME="$FULL_NAME"
    fi
    echo "$FULL_NAME $ID $SHORT_NAME"
done)

for INPUT in "$@"; do
    echo "🔍 Processing input: $INPUT"
    
    # Step 2: Try to find the Digest ID by matching either Full_Name or Short_Name
    # $1 is Full_Name, $3 is Extracted_Short_Name
    TARGET_ID=$(echo "$parsed_db" | awk -v in="$INPUT" '$1 == in || $3 == in {print $2; exit}')

    if [ -z "$TARGET_ID" ]; then
        echo "❌ Error: No local model matches '$INPUT' (checked both Full Name and Short Name)."
        continue
    fi

    echo "🆔 Found matching Digest ID: $TARGET_ID"

    # Step 3: Identify ALL instances (tags) tied to this ID for deletion
    NAMES_TO_DELETE=$(echo "$raw_list" | awk -v id="$TARGET_ID" '$2 == id {print $1}')

    echo "🗑️  Purging all associated tags:"
    echo "$NAMES_TO_DELETE"
    echo "-------------------------------------------"

    # Step 4: Execution
    for NAME in $NAMES_TO_DELETE; do
        ollama rm "$NAME"
    done

    echo "✅ Successfully wiped ID ${TARGET_ID:0:12}"
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Rigorous cleanup tool installed to $TARGET_PATH"
}

install_logic
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
