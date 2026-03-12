#!/bin/bash
# Xray-core entrypoint script (VLESS+XHTTP+Reality)
set -e

CONFIG_FILE="/etc/xray/config.json"

echo "[Xray] Starting Xray-core (VLESS+XHTTP+Reality)..."

# Check for config
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[Xray] ERROR: config.json not found at $CONFIG_FILE"
    exit 1
fi

echo "[Xray] Configuration:"
echo "  - Config: $CONFIG_FILE"
echo "  - Version: $(xray version | head -1)"

# Start Xray
exec xray run -c "$CONFIG_FILE"
