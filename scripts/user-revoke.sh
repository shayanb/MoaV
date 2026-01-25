#!/bin/bash
set -euo pipefail

# =============================================================================
# Revoke a user from all services
# Usage: ./scripts/user-revoke.sh <username>
# =============================================================================

cd "$(dirname "$0")/.."

source scripts/lib/common.sh

USERNAME="${1:-}"
KEEP_BUNDLE="${2:-}"

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username> [--keep-bundle]"
    echo "Example: $0 john"
    echo "         $0 john --keep-bundle  # Don't delete the user's bundle"
    exit 1
fi

# Check if user exists in sing-box config
if ! grep -q "\"name\":\"$USERNAME\"" configs/sing-box/config.json 2>/dev/null; then
    log_warn "User '$USERNAME' not found in sing-box configuration"
fi

log_info "Revoking user: $USERNAME"

# Remove from sing-box config
if [[ -f configs/sing-box/config.json ]]; then
    # Remove user from all inbound user arrays
    jq --arg name "$USERNAME" '
        (.inbounds[] | select(.users != null) | .users) |= map(select(.name != $name))
    ' configs/sing-box/config.json > configs/sing-box/config.json.tmp
    mv configs/sing-box/config.json.tmp configs/sing-box/config.json
    log_info "Removed from sing-box configuration"
fi

# Remove from WireGuard config
if [[ -f configs/wireguard/wg0.conf ]]; then
    # Remove peer block for this user
    sed -i.bak "/# $USERNAME/,/^$/d" configs/wireguard/wg0.conf
    rm -f configs/wireguard/wg0.conf.bak
    log_info "Removed from WireGuard configuration"
fi

# Remove user state
if [[ -d "/var/lib/docker/volumes/moav_state/_data/users/$USERNAME" ]]; then
    docker compose run --rm -v moav_state:/state alpine rm -rf "/state/users/$USERNAME"
    log_info "Removed user state"
fi

# Remove bundle unless --keep-bundle specified
if [[ "$KEEP_BUNDLE" != "--keep-bundle" ]] && [[ -d "outputs/bundles/$USERNAME" ]]; then
    rm -rf "outputs/bundles/$USERNAME"
    log_info "Removed user bundle"
fi

# Reload services
log_info "Reloading services..."

docker compose exec sing-box sing-box reload 2>/dev/null || \
    docker compose restart sing-box

if docker compose ps wireguard --status running >/dev/null 2>&1; then
    docker compose exec wireguard wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || \
        docker compose restart wireguard
fi

log_info "User '$USERNAME' has been revoked!"
