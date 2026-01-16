#!/bin/bash

# --- 1. Installation Logic ---
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="ollama_pull"
TARGET_PATH="$INSTALL_DIR/$SCRIPT_NAME"

install_logic() {
    mkdir -p "$INSTALL_DIR"
    
    # Write the core tool logic
    cat << 'INNER_EOF' > "$TARGET_PATH"
#!/bin/bash
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

if [ -z "$1" ]; then
    echo "Usage: ollama_pull <model_name> [mirror_prefix]"
    echo "Default mirror: ollama.m.daocloud.io/library/"
    exit 1
fi

MODEL_NAME="$1"
MIRROR_PREFIX="${2:-ollama.m.daocloud.io/library/}"
[[ "$MIRROR_PREFIX" != */ ]] && MIRROR_PREFIX="${MIRROR_PREFIX}/"
FULL_URL="${MIRROR_PREFIX}${MODEL_NAME}"

trap 'echo -e "\n🛑 Stop requested. Exiting..."; exit 1' SIGINT SIGTERM

echo "🚀 Target: $MODEL_NAME"
echo "🌐 From  : $FULL_URL"
echo "----------------------------------------------------"

while true; do
    echo "🔄 Pulling model data..."
    if ollama pull "$FULL_URL"; then
        echo "✅ Download complete."
        echo "🏷️  Aliasing to '$MODEL_NAME'..."
        if ollama cp "$FULL_URL" "$MODEL_NAME"; then
            echo "✨ Success! Cleaning up long-name manifest..."
            ollama rm "$FULL_URL" > /dev/null 2>&1
        fi
        break
    else
        echo "⚠️  Pull failed. Retrying in 5 seconds (Ctrl+C to stop)..."
        sleep 5
    fi
done
INNER_EOF

    chmod +x "$TARGET_PATH"
    echo "✅ Tool installed to $TARGET_PATH"

    # --- 2. PATH Management ---
    # Check if INSTALL_DIR is already in the current PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        
        # Avoid duplicate entries in RC files
        if ! grep -q "$INSTALL_DIR" "$SHELL_RC"; then
            echo -e "\n# Added by ollama_pull installer\nexport PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
            echo "📝 Added $INSTALL_DIR to $SHELL_RC"
            echo "👉 Please run: source $SHELL_RC"
        fi
    fi
}

# Execute Installation
install_logic

# --- 3. Immediate Execution ---
if [ $# -gt 0 ]; then
    "$TARGET_PATH" "$@"
fi
