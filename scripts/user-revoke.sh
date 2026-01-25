#!/bin/bash
set -euo pipefail

# =============================================================================
# Revoke a user from ALL services
# Usage: ./scripts/user-revoke.sh <username>
#
# This is the master script that calls individual service scripts:
#   - singbox-user-revoke.sh
#   - wg-user-revoke.sh
#
# For individual services, use the specific scripts directly.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

USERNAME="${1:-}"
KEEP_BUNDLE="${2:-}"

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username> [--keep-bundle]"
    echo ""
    echo "This revokes a user from ALL services."
    echo ""
    echo "Options:"
    echo "  --keep-bundle    Don't delete the user's bundle folder"
    echo ""
    echo "For individual services:"
    echo "  ./scripts/singbox-user-revoke.sh <username>  # sing-box"
    echo "  ./scripts/wg-user-revoke.sh <username>       # WireGuard"
    exit 1
fi

# Load environment
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi

STATE_DIR="${STATE_DIR:-./state}"
OUTPUT_DIR="outputs/bundles/$USERNAME"

log_info "========================================"
log_info "Revoking user '$USERNAME' from all services"
log_info "========================================"
echo ""

REVOKED=false

# -----------------------------------------------------------------------------
# Revoke from sing-box
# -----------------------------------------------------------------------------
if [[ -f "configs/sing-box/config.json" ]] && grep -q "\"name\":\"$USERNAME\"" "configs/sing-box/config.json" 2>/dev/null; then
    log_info "[1/2] Revoking from sing-box..."
    if "$SCRIPT_DIR/singbox-user-revoke.sh" "$USERNAME"; then
        log_info "✓ Revoked from sing-box"
        REVOKED=true
    else
        log_error "✗ Failed to revoke from sing-box"
    fi
else
    log_info "[1/2] User not found in sing-box (skipping)"
fi

echo ""

# -----------------------------------------------------------------------------
# Revoke from WireGuard
# -----------------------------------------------------------------------------
if [[ -f "configs/wireguard/wg0.conf" ]] && grep -q "# $USERNAME\$" "configs/wireguard/wg0.conf" 2>/dev/null; then
    log_info "[2/2] Revoking from WireGuard..."
    if "$SCRIPT_DIR/wg-user-revoke.sh" "$USERNAME"; then
        log_info "✓ Revoked from WireGuard"
        REVOKED=true
    else
        log_error "✗ Failed to revoke from WireGuard"
    fi
else
    log_info "[2/2] User not found in WireGuard (skipping)"
fi

echo ""

# -----------------------------------------------------------------------------
# Clean up user files
# -----------------------------------------------------------------------------
if [[ "$KEEP_BUNDLE" != "--keep-bundle" ]] && [[ -d "$OUTPUT_DIR" ]]; then
    log_info "Removing user bundle: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
fi

if [[ -d "$STATE_DIR/users/$USERNAME" ]]; then
    log_info "Removing user state: $STATE_DIR/users/$USERNAME"
    rm -rf "$STATE_DIR/users/$USERNAME"
fi

# Also try docker volume path
docker run --rm -v moav_moav_state:/state alpine rm -rf "/state/users/$USERNAME" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
if [[ "$REVOKED" == "true" ]]; then
    log_info "========================================"
    log_info "User '$USERNAME' has been revoked"
    log_info "========================================"
else
    log_error "User '$USERNAME' was not found in any service"
    exit 1
fi
