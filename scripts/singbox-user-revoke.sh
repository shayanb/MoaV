#!/bin/bash
set -euo pipefail

# =============================================================================
# Revoke a user from sing-box (Reality, Trojan, Hysteria2)
# Usage: ./scripts/singbox-user-revoke.sh <username>
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

CONFIG_FILE="configs/sing-box/config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "sing-box config not found"
    exit 1
fi

# Check if user exists
if ! grep -q "\"name\":\"$USERNAME\"" "$CONFIG_FILE" 2>/dev/null; then
    log_error "User '$USERNAME' not found in sing-box config"
    exit 1
fi

log_info "Revoking user '$USERNAME' from sing-box..."

# Remove user from all inbounds using jq
TEMP_CONFIG=$(mktemp)

# Remove from Reality (vless)
jq --arg name "$USERNAME" \
    '.inbounds |= map(if .users then .users |= map(select(.name != $name)) else . end)' \
    "$CONFIG_FILE" > "$TEMP_CONFIG"

# Validate
if ! jq empty "$TEMP_CONFIG" 2>/dev/null; then
    log_error "Failed to generate valid config"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

mv "$TEMP_CONFIG" "$CONFIG_FILE"

log_info "Removed $USERNAME from sing-box config"

# Remove from TrustTunnel (if config exists)
TRUSTTUNNEL_CREDS="configs/trusttunnel/credentials.toml"
if [[ -f "$TRUSTTUNNEL_CREDS" ]]; then
    if grep -q "username = \"$USERNAME\"" "$TRUSTTUNNEL_CREDS" 2>/dev/null; then
        log_info "Removing $USERNAME from TrustTunnel..."

        # Use awk to remove the credential block for the user
        # The block starts with [[credentials]] followed by username and password
        awk -v user="$USERNAME" '
        BEGIN { skip=0; in_block=0; buffer="" }
        /^\[\[credentials\]\]/ {
            if (in_block && !skip) { print buffer }
            in_block=1; skip=0; buffer=$0 "\n"; next
        }
        in_block {
            buffer = buffer $0 "\n"
            if (/^username = /) {
                if (index($0, "\"" user "\"") > 0) { skip=1 }
            }
            if (/^$/ || /^\[/) {
                if (!skip) { print buffer }
                in_block=0; buffer=""
                if (/^\[/) { print }
            }
            next
        }
        { print }
        END { if (in_block && !skip) { printf "%s", buffer } }
        ' "$TRUSTTUNNEL_CREDS" > "${TRUSTTUNNEL_CREDS}.tmp" && mv "${TRUSTTUNNEL_CREDS}.tmp" "$TRUSTTUNNEL_CREDS"

        log_info "Removed $USERNAME from TrustTunnel credentials"
    fi
fi

# Reload sing-box
if docker compose ps sing-box --status running &>/dev/null; then
    log_info "Reloading sing-box..."
    if docker compose exec -T sing-box sing-box reload 2>/dev/null; then
        log_info "sing-box reloaded"
    else
        docker compose restart sing-box
    fi
fi

# Reload TrustTunnel (if running)
if [[ -f "$TRUSTTUNNEL_CREDS" ]]; then
    if docker compose ps trusttunnel --status running &>/dev/null; then
        log_info "Restarting TrustTunnel..."
        docker compose restart trusttunnel
    fi
fi

log_info "User '$USERNAME' revoked"
