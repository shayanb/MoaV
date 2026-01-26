#!/bin/bash
set -euo pipefail

# =============================================================================
# Debug WireGuard configuration and state
# =============================================================================

cd "$(dirname "$0")/.."

echo "=========================================="
echo "       WireGuard Debug Info"
echo "=========================================="
echo ""

echo "=== 1. Host config file ==="
if [[ -f configs/wireguard/wg0.conf ]]; then
    echo "File exists: configs/wireguard/wg0.conf"
    echo "Permissions: $(ls -la configs/wireguard/wg0.conf)"
    echo "Peer count: $(grep -c '^\[Peer\]' configs/wireguard/wg0.conf || echo 0)"
    echo "Peers:"
    grep -A2 '^\[Peer\]' configs/wireguard/wg0.conf | head -30
else
    echo "ERROR: Config file not found!"
fi

echo ""
echo "=== 2. server.pub file ==="
if [[ -f configs/wireguard/server.pub ]]; then
    echo "Content: $(cat configs/wireguard/server.pub)"
else
    echo "ERROR: server.pub not found!"
fi

echo ""
echo "=== 3. Container status ==="
if docker compose ps wireguard --status running &>/dev/null; then
    echo "Container: RUNNING"

    echo ""
    echo "=== 4. Config inside container ==="
    docker compose exec -T wireguard cat /etc/wireguard/wg0.conf 2>/dev/null | sed 's/PrivateKey = .*/PrivateKey = [REDACTED]/' || echo "ERROR: Cannot read config inside container"

    echo ""
    echo "=== 5. Running WireGuard interface ==="
    docker compose exec -T wireguard wg show 2>/dev/null || echo "ERROR: wg show failed"

    echo ""
    echo "=== 6. Server public key comparison ==="
    RUNNING_KEY=$(docker compose exec -T wireguard wg show wg0 public-key 2>/dev/null | tr -d '\r\n')
    FILE_KEY=$(cat configs/wireguard/server.pub 2>/dev/null | tr -d '\r\n')
    echo "Running:  $RUNNING_KEY"
    echo "In file:  $FILE_KEY"
    if [[ "$RUNNING_KEY" == "$FILE_KEY" ]]; then
        echo "Status: MATCH ✓"
    else
        echo "Status: MISMATCH ✗"
    fi

    echo ""
    echo "=== 7. Peer comparison (config vs running) ==="
    CONFIG_PEERS=$(grep 'PublicKey' configs/wireguard/wg0.conf | awk '{print $3}' | sort)
    RUNNING_PEERS=$(docker compose exec -T wireguard wg show wg0 peers 2>/dev/null | sort)
    echo "Peers in config file:"
    echo "$CONFIG_PEERS" | head -10
    echo ""
    echo "Peers loaded in WireGuard:"
    echo "$RUNNING_PEERS" | head -10
    echo ""

    CONFIG_COUNT=$(echo "$CONFIG_PEERS" | grep -c . || echo 0)
    RUNNING_COUNT=$(echo "$RUNNING_PEERS" | grep -c . || echo 0)
    echo "Config peers: $CONFIG_COUNT"
    echo "Running peers: $RUNNING_COUNT"

    if [[ "$CONFIG_COUNT" == "$RUNNING_COUNT" ]]; then
        echo "Status: COUNTS MATCH ✓"
    else
        echo "Status: COUNTS MISMATCH ✗ - Peers not loaded properly!"
    fi
else
    echo "Container: NOT RUNNING"
    echo "Start with: docker compose --profile wireguard up -d wireguard"
fi

echo ""
echo "=========================================="
