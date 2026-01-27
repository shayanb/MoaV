#!/bin/sh

# =============================================================================
# Simple WireGuard entrypoint - just runs wg-quick with the config
# =============================================================================

CONFIG_FILE="/etc/wireguard/wg0.conf"

echo "[wireguard] Starting WireGuard..."

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[wireguard] ERROR: Config file not found at $CONFIG_FILE"
    echo "[wireguard] Run bootstrap first to generate WireGuard configuration"
    exit 1
fi

# Show config info (without private keys)
echo "[wireguard] Config file: $CONFIG_FILE"
PEER_COUNT=$(grep -c '^\[Peer\]' "$CONFIG_FILE" || echo 0)
echo "[wireguard] Peer count: $PEER_COUNT"

# IP forwarding is set via docker-compose sysctls
echo "[wireguard] IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"

# Bring up WireGuard interface
echo "[wireguard] Running: wg-quick up wg0"
if ! wg-quick up wg0; then
    echo "[wireguard] ERROR: Failed to bring up WireGuard interface"
    echo "[wireguard] Config content:"
    cat "$CONFIG_FILE"
    exit 1
fi

# Show interface status
echo "[wireguard] Interface status:"
wg show wg0

# Keep container running and monitor for config changes
echo "[wireguard] WireGuard is running. Monitoring..."

# Trap SIGTERM to gracefully shutdown
cleanup() {
    echo "[wireguard] Shutting down..."
    wg-quick down wg0 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Keep running
while true; do
    sleep 60
    # Check if interface is still up
    if ! wg show wg0 > /dev/null 2>&1; then
        echo "[wireguard] Interface down, restarting..."
        wg-quick up wg0 || true
    fi
done
