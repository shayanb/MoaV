#!/bin/bash
set -euo pipefail

# =============================================================================
# Sync WireGuard keys between running container and config files
# Run this if you have key mismatch issues after container restarts
# Usage: ./scripts/wg-sync-keys.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

WG_CONFIG_DIR="configs/wireguard"

log_info "Checking WireGuard key consistency..."

# Check if WireGuard is running
if ! docker compose ps wireguard --status running &>/dev/null; then
    log_error "WireGuard container is not running"
    log_info "Start it with: docker compose --profile wireguard up -d wireguard"
    exit 1
fi

# Get keys from different sources
RUNNING_PUBKEY=$(docker compose exec -T wireguard wg show wg0 public-key 2>/dev/null | tr -d '\r\n')
RUNNING_PRIVKEY=$(docker compose exec -T wireguard grep PrivateKey /config/wg0.conf 2>/dev/null | awk '{print $3}' | tr -d '\r\n')
FILE_PUBKEY=$(cat "$WG_CONFIG_DIR/server.pub" 2>/dev/null | tr -d '\r\n' || echo "")
CONFIG_PRIVKEY=$(grep PrivateKey "$WG_CONFIG_DIR/wg0.conf" 2>/dev/null | awk '{print $3}' | tr -d '\r\n' || echo "")

echo ""
echo "=== Key Status ==="
echo "Running public key:  $RUNNING_PUBKEY"
echo "server.pub file:     $FILE_PUBKEY"
echo "Running private key: ${RUNNING_PRIVKEY:0:10}... (truncated)"
echo "Config private key:  ${CONFIG_PRIVKEY:0:10}... (truncated)"
echo ""

# Check for mismatches
MISMATCH=false

if [[ "$RUNNING_PUBKEY" != "$FILE_PUBKEY" ]]; then
    log_info "MISMATCH: server.pub doesn't match running WireGuard"
    MISMATCH=true
fi

if [[ "$RUNNING_PRIVKEY" != "$CONFIG_PRIVKEY" ]]; then
    log_info "MISMATCH: Config file private key doesn't match running WireGuard"
    MISMATCH=true
fi

if [[ "$MISMATCH" == "false" ]]; then
    log_info "All keys are in sync!"
    exit 0
fi

echo ""
log_info "Syncing keys from running WireGuard..."

# Backup existing files
cp "$WG_CONFIG_DIR/wg0.conf" "$WG_CONFIG_DIR/wg0.conf.backup.$(date +%s)" 2>/dev/null || true
cp "$WG_CONFIG_DIR/server.pub" "$WG_CONFIG_DIR/server.pub.backup.$(date +%s)" 2>/dev/null || true

# Get the full config from container (preserves peers)
docker compose exec -T wireguard cat /config/wg0.conf > "$WG_CONFIG_DIR/wg0.conf"

# Update server.pub with running public key
echo "$RUNNING_PUBKEY" > "$WG_CONFIG_DIR/server.pub"

log_info "Keys synced successfully!"
echo ""
echo "Updated files:"
echo "  - $WG_CONFIG_DIR/wg0.conf"
echo "  - $WG_CONFIG_DIR/server.pub"
echo ""
echo "New users created with wg-user-add.sh will now work correctly."
echo "Existing users may need to be regenerated if they have the old server public key."
