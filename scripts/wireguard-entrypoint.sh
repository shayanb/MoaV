#!/bin/sh

# =============================================================================
# Simple WireGuard entrypoint - just runs wg-quick with the config
# =============================================================================

# Log with timestamp (MM-DD HH:MM:SS - SERVICE - MESSAGE)
log() {
    echo "$(date '+%m-%d %H:%M:%S') - wireguard - $*"
}

CONFIG_FILE="/etc/wireguard/wg0.conf"

log "Starting WireGuard..."

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    log " ERROR: Config file not found at $CONFIG_FILE"
    log " Run bootstrap first to generate WireGuard configuration"
    exit 1
fi

# Show config info (without private keys)
log " Config file: $CONFIG_FILE"
PEER_COUNT=$(grep -c '^\[Peer\]' "$CONFIG_FILE" || echo 0)
log " Peer count: $PEER_COUNT"

# IP forwarding is set via docker-compose sysctls
log " IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"

# Bring up WireGuard interface
log " Running: wg-quick up wg0"
if ! wg-quick up wg0; then
    log " ERROR: Failed to bring up WireGuard interface"
    log " Config content:"
    cat "$CONFIG_FILE"
    exit 1
fi

# Show interface status
log " Interface status:"
wg show wg0

# Keep container running and monitor for config changes
log " WireGuard is running. Monitoring..."

# Trap SIGTERM to gracefully shutdown
cleanup() {
    log " Shutting down..."
    wg-quick down wg0 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Keep running
while true; do
    sleep 60
    # Check if interface is still up
    if ! wg show wg0 > /dev/null 2>&1; then
        log " Interface down, restarting..."
        wg-quick up wg0 || true
    fi
done
