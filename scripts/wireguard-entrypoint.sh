#!/bin/sh
set -e

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

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "[wireguard] IP forwarding enabled"

# Bring up WireGuard interface
echo "[wireguard] Running: wg-quick up wg0"
wg-quick up wg0

# Show interface status
echo "[wireguard] Interface status:"
wg show wg0

# Keep container running and monitor for config changes
echo "[wireguard] WireGuard is running. Monitoring..."

# Trap SIGTERM to gracefully shutdown
trap "echo '[wireguard] Shutting down...'; wg-quick down wg0; exit 0" SIGTERM SIGINT

# Keep running
while true; do
    sleep 60
    # Optional: Check if interface is still up
    if ! wg show wg0 > /dev/null 2>&1; then
        echo "[wireguard] Interface down, restarting..."
        wg-quick up wg0
    fi
done
