#!/bin/bash
set -euo pipefail

# =============================================================================
# List all users across services
# Usage: ./scripts/user-list.sh
# =============================================================================

cd "$(dirname "$0")/.."

echo "========================================"
echo "         MoaV User List"
echo "========================================"
echo ""

# -----------------------------------------------------------------------------
# sing-box users (Reality, Trojan, Hysteria2)
# -----------------------------------------------------------------------------
echo "=== sing-box Users (Reality/Trojan/Hysteria2) ==="
if [[ -f configs/sing-box/config.json ]]; then
    SINGBOX_USERS=$(jq -r '.inbounds[] | select(.users != null) | .users[].name' configs/sing-box/config.json 2>/dev/null | sort | uniq)
    if [[ -n "$SINGBOX_USERS" ]]; then
        echo "$SINGBOX_USERS" | while read -r user; do
            bundle_status=""
            if [[ -d "outputs/bundles/$user" ]]; then
                bundle_status=" [bundle ready]"
            fi
            echo "  • $user$bundle_status"
        done
        SINGBOX_COUNT=$(echo "$SINGBOX_USERS" | wc -l | tr -d ' ')
        echo ""
        echo "  Total: $SINGBOX_COUNT users"
    else
        echo "  (no users)"
    fi
else
    echo "  (not configured - run bootstrap)"
fi

echo ""

# -----------------------------------------------------------------------------
# WireGuard peers
# -----------------------------------------------------------------------------
echo "=== WireGuard Peers ==="
if [[ -f configs/wireguard/wg0.conf ]]; then
    # Extract peer names: look for comments after [Peer] blocks
    WG_PEERS=$(awk '/^\[Peer\]/{getline; if(/^# /){sub(/^# /,""); print}}' configs/wireguard/wg0.conf 2>/dev/null || true)
    if [[ -n "$WG_PEERS" ]]; then
        WG_COUNT=0
        # Get IPs for each peer
        while IFS= read -r peer; do
            [[ -z "$peer" ]] && continue
            IP=$(grep -A2 "# $peer\$" configs/wireguard/wg0.conf 2>/dev/null | grep "AllowedIPs" | awk '{print $3}' | sed 's/\/32//' || echo "")
            if [[ -n "$IP" ]]; then
                echo "  • $peer ($IP)"
            else
                echo "  • $peer (no IP found)"
            fi
            ((WG_COUNT++)) || true
        done <<< "$WG_PEERS"
        echo ""
        echo "  Total: $WG_COUNT peers"
    else
        echo "  (no peers)"
    fi
else
    echo "  (not configured)"
fi

echo ""

# -----------------------------------------------------------------------------
# User bundles
# -----------------------------------------------------------------------------
echo "=== User Bundles ==="
if [[ -d outputs/bundles ]] && [[ "$(ls -A outputs/bundles 2>/dev/null)" ]]; then
    for bundle in outputs/bundles/*/; do
        username=$(basename "$bundle")
        files=$(ls "$bundle" 2>/dev/null | wc -l | tr -d ' ')
        echo "  • $username ($files files)"
    done
else
    echo "  (none)"
fi

echo ""
echo "========================================"
