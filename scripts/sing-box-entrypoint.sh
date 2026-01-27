#!/bin/sh

# =============================================================================
# sing-box entrypoint with logging
# =============================================================================

# Log with timestamp (MM-DD HH:MM:SS - SERVICE - MESSAGE)
log() {
    echo "$(date '+%m-%d %H:%M:%S') - sing-box - $*"
}

CONFIG_FILE="${CONFIG_FILE:-/etc/sing-box/config.json}"

log "Starting sing-box multi-protocol proxy"
log "Config: $CONFIG_FILE"

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: Config file not found at $CONFIG_FILE"
    log "Run bootstrap first to generate configuration"
    exit 1
fi

# Validate config
log "Validating configuration..."
if ! sing-box check -c "$CONFIG_FILE"; then
    log "ERROR: Configuration validation failed"
    exit 1
fi
log "Configuration valid"

# Show enabled inbounds
INBOUNDS=$(grep -o '"tag"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -10 | sed 's/"tag"[[:space:]]*:[[:space:]]*//g' | tr -d '"' | tr '\n' ', ' | sed 's/,$//')
log "Inbounds: $INBOUNDS"

# Run sing-box
log "Starting proxy server..."
exec sing-box run -c "$CONFIG_FILE"
