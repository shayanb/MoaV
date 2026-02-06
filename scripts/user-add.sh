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
# Generate README.html from template
# -----------------------------------------------------------------------------
TEMPLATE_FILE="docs/client-guide-template.html"
OUTPUT_HTML="$OUTPUT_DIR/README.html"

if [[ -f "$TEMPLATE_FILE" ]]; then
    log_info "Generating HTML guide..."

    # Get server info
    SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")}"
    GENERATED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Read config values
    CONFIG_REALITY=$(cat "$OUTPUT_DIR/reality.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_HYSTERIA2=$(cat "$OUTPUT_DIR/hysteria2.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_TROJAN=$(cat "$OUTPUT_DIR/trojan.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_WIREGUARD=$(cat "$OUTPUT_DIR/wireguard.conf" 2>/dev/null || echo "")
    CONFIG_WIREGUARD_WSTUNNEL=$(cat "$OUTPUT_DIR/wireguard-wstunnel.conf" 2>/dev/null || echo "")

    # Read user password from trusttunnel.json or credentials
    if [[ -f "$OUTPUT_DIR/trusttunnel.json" ]]; then
        USER_PASSWORD=$(jq -r '.password // empty' "$OUTPUT_DIR/trusttunnel.json" 2>/dev/null || echo "")
    elif [[ -f "state/users/$USERNAME/credentials.env" ]]; then
        USER_PASSWORD=$(grep "^USER_PASSWORD=" "state/users/$USERNAME/credentials.env" 2>/dev/null | cut -d= -f2 || echo "")
    else
        USER_PASSWORD=""
    fi

    # Get dnstt info
    DNSTT_DOMAIN="${DNSTT_SUBDOMAIN:-t}.${DOMAIN}"
    DNSTT_PUBKEY=$(cat "outputs/dnstt/server.pub" 2>/dev/null || echo "")

    # Convert QR images to base64
    qr_to_base64() {
        local file="$1"
        if [[ -f "$file" ]]; then
            base64 < "$file" 2>/dev/null | tr -d '\n' || echo ""
        else
            echo ""
        fi
    }

    QR_REALITY_B64=$(qr_to_base64 "$OUTPUT_DIR/reality-qr.png")
    QR_HYSTERIA2_B64=$(qr_to_base64 "$OUTPUT_DIR/hysteria2-qr.png")
    QR_TROJAN_B64=$(qr_to_base64 "$OUTPUT_DIR/trojan-qr.png")
    QR_WIREGUARD_B64=$(qr_to_base64 "$OUTPUT_DIR/wireguard-qr.png")
    QR_WIREGUARD_WSTUNNEL_B64=$(qr_to_base64 "$OUTPUT_DIR/wireguard-wstunnel-qr.png")

    # Copy template
    cp "$TEMPLATE_FILE" "$OUTPUT_HTML"

    # Simple replacements (use .bak for portability, then clean up)
    sed -i.bak "s|{{USERNAME}}|$USERNAME|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{SERVER_IP}}|$SERVER_IP|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{DOMAIN}}|${DOMAIN:-YOUR_DOMAIN}|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{GENERATED_DATE}}|$GENERATED_DATE|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{DNSTT_DOMAIN}}|$DNSTT_DOMAIN|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{DNSTT_PUBKEY}}|$DNSTT_PUBKEY|g" "$OUTPUT_HTML"

    # TrustTunnel password (escape special chars)
    if [[ -n "${USER_PASSWORD:-}" ]]; then
        ESCAPED_PW=$(printf '%s' "$USER_PASSWORD" | sed -e 's/[&\|]/\\&/g')
        sed -i.bak "s|{{TRUSTTUNNEL_PASSWORD}}|${ESCAPED_PW}|g" "$OUTPUT_HTML"
    else
        sed -i.bak "s|{{TRUSTTUNNEL_PASSWORD}}|See trusttunnel.txt|g" "$OUTPUT_HTML"
    fi

    # Remove demo notice placeholders (not a demo user)
    sed -i.bak "s|{{DEMO_NOTICE_EN}}||g" "$OUTPUT_HTML"
    sed -i.bak "s|{{DEMO_NOTICE_FA}}||g" "$OUTPUT_HTML"

    # QR codes (base64)
    sed -i.bak "s|{{QR_REALITY}}|$QR_REALITY_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_HYSTERIA2}}|$QR_HYSTERIA2_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_TROJAN}}|$QR_TROJAN_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_WIREGUARD}}|$QR_WIREGUARD_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_WIREGUARD_WSTUNNEL}}|$QR_WIREGUARD_WSTUNNEL_B64|g" "$OUTPUT_HTML"

    # Config values - use sed with proper escaping for special characters
    # In sed replacement: & means "matched pattern", \ is escape char
    # We escape: & -> \&, \ -> \\, | -> \| (since we use | as delimiter)
    escape_for_sed() {
        printf '%s' "$1" | sed -e 's/[&\|]/\\&/g'
    }

    if [[ -n "$CONFIG_REALITY" ]]; then
        ESCAPED=$(escape_for_sed "$CONFIG_REALITY")
        sed -i.bak "s|{{CONFIG_REALITY}}|${ESCAPED}|g" "$OUTPUT_HTML"
    else
        sed -i.bak "s|{{CONFIG_REALITY}}|No Reality config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_HYSTERIA2" ]]; then
        ESCAPED=$(escape_for_sed "$CONFIG_HYSTERIA2")
        sed -i.bak "s|{{CONFIG_HYSTERIA2}}|${ESCAPED}|g" "$OUTPUT_HTML"
    else
        sed -i.bak "s|{{CONFIG_HYSTERIA2}}|No Hysteria2 config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_TROJAN" ]]; then
        ESCAPED=$(escape_for_sed "$CONFIG_TROJAN")
        sed -i.bak "s|{{CONFIG_TROJAN}}|${ESCAPED}|g" "$OUTPUT_HTML"
    else
        sed -i.bak "s|{{CONFIG_TROJAN}}|No Trojan config available|g" "$OUTPUT_HTML"
    fi

    # WireGuard configs (single line in HTML, original is multiline)
    if [[ -n "$CONFIG_WIREGUARD" ]]; then
        ESCAPED=$(escape_for_sed "$CONFIG_WIREGUARD")
        sed -i.bak "s|{{CONFIG_WIREGUARD}}|${ESCAPED}|g" "$OUTPUT_HTML"
    else
        sed -i.bak "s|{{CONFIG_WIREGUARD}}|No WireGuard config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_WIREGUARD_WSTUNNEL" ]]; then
        ESCAPED=$(escape_for_sed "$CONFIG_WIREGUARD_WSTUNNEL")
        sed -i.bak "s|{{CONFIG_WIREGUARD_WSTUNNEL}}|${ESCAPED}|g" "$OUTPUT_HTML"
    else
        sed -i.bak "s|{{CONFIG_WIREGUARD_WSTUNNEL}}|No WireGuard-wstunnel config available|g" "$OUTPUT_HTML"
    fi

    # Clean up backup files
    rm -f "$OUTPUT_HTML.bak"

    log_info "✓ README.html generated"
else
    log_warn "Template not found: $TEMPLATE_FILE - skipping HTML guide"
fi

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
