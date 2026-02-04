#!/bin/sh

# =============================================================================
# sing-box entrypoint with logging
# =============================================================================

CONFIG_FILE="${CONFIG_FILE:-/etc/sing-box/config.json}"

echo "[sing-box] Starting sing-box multi-protocol proxy"
echo "[sing-box] Config: $CONFIG_FILE"

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[sing-box] ERROR: Config file not found at $CONFIG_FILE"
    echo "[sing-box] Run bootstrap first to generate configuration"
    exit 1
fi

# Validate config
echo "[sing-box] Validating configuration..."
if ! sing-box check -c "$CONFIG_FILE"; then
    echo "[sing-box] ERROR: Configuration validation failed"
    exit 1
fi
echo "[sing-box] Configuration valid"

# Show enabled inbounds
INBOUNDS=$(grep -o '"tag"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -10 | sed 's/"tag"[[:space:]]*:[[:space:]]*//g' | tr -d '"' | tr '\n' ', ' | sed 's/,$//')
echo "[sing-box] Inbounds: $INBOUNDS"

# Run sing-box
echo "[sing-box] Starting proxy server..."
exec sing-box run -c "$CONFIG_FILE"
