#!/bin/bash
set -euo pipefail

# =============================================================================
# Add a new user to ALL enabled services
# Usage: ./scripts/user-add.sh <username> [--package]
#
# Options:
#   --package, -p   Create a distributable zip with HTML guide
#
# This is the master script that calls individual service scripts:
#   - singbox-user-add.sh (Reality, Trojan, Hysteria2)
#   - wg-user-add.sh (WireGuard)
#
# For individual services, use the specific scripts directly.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

# Parse arguments
USERNAME=""
CREATE_PACKAGE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package|-p)
            CREATE_PACKAGE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            USERNAME="$1"
            shift
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username> [--package]"
    echo ""
    echo "Options:"
    echo "  --package, -p   Create a distributable zip with HTML guide"
    echo ""
    echo "This adds a user to ALL enabled services."
    echo ""
    echo "For individual services:"
    echo "  ./scripts/singbox-user-add.sh <username>  # Reality, Trojan, Hysteria2"
    echo "  ./scripts/wg-user-add.sh <username>       # WireGuard"
    exit 1
fi

# Validate username
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid username. Use only letters, numbers, underscores, and hyphens."
    exit 1
fi

# Load environment
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi

# Check if user bundle already exists
if [[ -d "outputs/bundles/$USERNAME" ]]; then
    log_error "User '$USERNAME' already exists. Use a different name or revoke first."
    log_error "To revoke: ./scripts/user-revoke.sh $USERNAME"
    exit 1
fi

OUTPUT_DIR="outputs/bundles/$USERNAME"
mkdir -p "$OUTPUT_DIR"

log_info "========================================"
log_info "Adding user '$USERNAME' to all services"
log_info "========================================"
echo ""

ERRORS=()

# -----------------------------------------------------------------------------
# Add to sing-box (Reality, Trojan, Hysteria2)
# -----------------------------------------------------------------------------
if [[ -f "configs/sing-box/config.json" ]]; then
    log_info "[1/2] Adding to sing-box (Reality, Trojan, Hysteria2)..."
    if "$SCRIPT_DIR/singbox-user-add.sh" "$USERNAME"; then
        log_info "✓ sing-box user added"
    else
        ERRORS+=("sing-box")
        log_error "✗ Failed to add sing-box user"
    fi
else
    log_info "[1/2] Skipping sing-box (not configured)"
fi

echo ""

# -----------------------------------------------------------------------------
# Add to WireGuard
# -----------------------------------------------------------------------------
if [[ "${ENABLE_WIREGUARD:-true}" == "true" ]] && [[ -f "configs/wireguard/wg0.conf" ]]; then
    log_info "[2/2] Adding to WireGuard..."
    if "$SCRIPT_DIR/wg-user-add.sh" "$USERNAME"; then
        log_info "✓ WireGuard peer added"
    else
        ERRORS+=("wireguard")
        log_error "✗ Failed to add WireGuard peer"
    fi
else
    log_info "[2/2] Skipping WireGuard (not enabled or not configured)"
fi

echo ""

# -----------------------------------------------------------------------------
# Generate dnstt instructions (shared for all users)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_DNSTT:-true}" == "true" ]] && [[ -f "outputs/dnstt/server.pub" ]]; then
    DNSTT_PUBKEY=$(cat "outputs/dnstt/server.pub" 2>/dev/null || echo "KEY_NOT_FOUND")
    DNSTT_DOMAIN="${DNSTT_SUBDOMAIN:-t}.${DOMAIN}"

    cat > "$OUTPUT_DIR/dnstt-instructions.txt" <<EOF
# dnstt DNS Tunnel Instructions
# =============================
# Use this as a LAST RESORT when other methods are blocked.
# DNS tunneling is SLOW but often works when everything else fails.

# Server Public Key (hex):
$DNSTT_PUBKEY

# Tunnel Domain:
$DNSTT_DOMAIN

# -------------------------
# Option 1: Using DoH (DNS over HTTPS) - RECOMMENDED
# -------------------------

# Download dnstt-client from: https://www.bamsoftware.com/software/dnstt/

# Run (creates a local SOCKS5 proxy on port 1080):
dnstt-client -doh https://1.1.1.1/dns-query -pubkey $DNSTT_PUBKEY $DNSTT_DOMAIN 127.0.0.1:1080

# Then configure your apps to use SOCKS5 proxy: 127.0.0.1:1080

# -------------------------
# Option 2: Using Plain UDP DNS
# -------------------------

# If DoH is blocked, try plain UDP (use a public resolver):
dnstt-client -udp 8.8.8.8:53 -pubkey $DNSTT_PUBKEY $DNSTT_DOMAIN 127.0.0.1:1080
EOF
    log_info "✓ dnstt instructions generated"
fi

# -----------------------------------------------------------------------------
# Generate README
# -----------------------------------------------------------------------------
SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")}"

cat > "$OUTPUT_DIR/README.md" <<EOF
# MoaV Connection Guide for ${USERNAME}

This bundle contains your personal credentials for connecting to the MoaV server.
**Do not share these files with anyone.**

Server: \`${SERVER_IP}\` / \`${DOMAIN:-YOUR_DOMAIN}\`

---

## Quick Start (Recommended Order)

Try these methods in order. If one doesn't work, try the next.

### 1. Reality (VLESS) - Primary, Most Reliable
- Config: \`reality.txt\`
- QR Code: \`reality-qr.png\`

### 2. Hysteria2 - Fast Alternative (UDP)
- Config: \`hysteria2.txt\`
- QR Code: \`hysteria2-qr.png\`

### 3. Trojan - Backup (Port 8443)
- Config: \`trojan.txt\`
- QR Code: \`trojan-qr.png\`

### 4. WireGuard - Full VPN Mode
- Config: \`wireguard.conf\`
- QR Code: \`wireguard-qr.png\`

### 5. DNS Tunnel - Last Resort
- Instructions: \`dnstt-instructions.txt\`

---

## Recommended Apps

| Platform | App |
|----------|-----|
| iOS | Shadowrocket, Streisand, Hiddify |
| Android | v2rayNG, NekoBox, Hiddify |
| macOS | V2rayU, NekoRay |
| Windows | v2rayN, NekoRay |

---

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
log_info "========================================"
log_info "User '$USERNAME' creation complete!"
log_info "========================================"
echo ""
log_info "Bundle location: $OUTPUT_DIR/"
echo ""
ls -la "$OUTPUT_DIR/"
echo ""

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    log_error "Some services failed: ${ERRORS[*]}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Create package if requested
# -----------------------------------------------------------------------------
if [[ "$CREATE_PACKAGE" == "true" ]]; then
    echo ""
    log_info "Creating distributable package..."
    if "$SCRIPT_DIR/user-package.sh" "$USERNAME"; then
        log_info "✓ Package created successfully"
    else
        log_error "✗ Failed to create package"
        exit 1
    fi
else
    log_info "Distribute the bundle securely to the user."
    log_info "Tip: Use --package to create a zip with HTML guide"
fi
