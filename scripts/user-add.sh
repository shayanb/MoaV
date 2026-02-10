#!/bin/bash
set -euo pipefail

# =============================================================================
# Add user(s) to ALL enabled services
# Usage: ./scripts/user-add.sh <username> [username2...] [options]
#        ./scripts/user-add.sh --batch N [--prefix NAME] [options]
#
# Options:
#   --package, -p     Create distributable zip with HTML guide for each user
#   --batch N         Create N users with auto-generated names
#   --prefix NAME     Prefix for batch usernames (default: "user")
#
# Examples:
#   ./scripts/user-add.sh alice bob charlie
#   ./scripts/user-add.sh --batch 5
#   ./scripts/user-add.sh --batch 10 --prefix team --package
#
# This is the master script that calls individual service scripts:
#   - singbox-user-add.sh (Reality, Trojan, Hysteria2)
#   - wg-user-add.sh (WireGuard)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

# Parse arguments
USERNAMES=()
CREATE_PACKAGE=false
BATCH_COUNT=0
BATCH_PREFIX="user"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package|-p)
            CREATE_PACKAGE=true
            shift
            ;;
        --batch|-b)
            BATCH_COUNT="${2:-0}"
            shift 2
            ;;
        --prefix)
            BATCH_PREFIX="${2:-user}"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            USERNAMES+=("$1")
            shift
            ;;
    esac
done

# Generate batch usernames if --batch was specified
if [[ "$BATCH_COUNT" -gt 0 ]]; then
    # Find the next available number for this prefix
    START_NUM=1
    while [[ -d "outputs/bundles/${BATCH_PREFIX}$(printf '%02d' $START_NUM)" ]]; do
        ((START_NUM++))
    done

    for ((i=0; i<BATCH_COUNT; i++)); do
        NUM=$((START_NUM + i))
        USERNAMES+=("${BATCH_PREFIX}$(printf '%02d' $NUM)")
    done
fi

if [[ ${#USERNAMES[@]} -eq 0 ]]; then
    echo "Usage: $0 <username> [username2...] [--package]"
    echo "       $0 --batch N [--prefix NAME] [--package]"
    echo ""
    echo "Options:"
    echo "  --package, -p     Create distributable zip with HTML guide"
    echo "  --batch N         Create N users with auto-generated names"
    echo "  --prefix NAME     Prefix for batch usernames (default: \"user\")"
    echo ""
    echo "Examples:"
    echo "  $0 alice bob charlie        # Add three users"
    echo "  $0 --batch 5                # Create user01, user02, ..., user05"
    echo "  $0 --batch 10 --prefix team # Create team01, team02, ..., team10"
    echo ""
    echo "For individual services:"
    echo "  ./scripts/singbox-user-add.sh <username>  # Reality, Trojan, Hysteria2"
    echo "  ./scripts/wg-user-add.sh <username>       # WireGuard"
    exit 1
fi

# Determine if we're in batch mode (multiple users)
BATCH_MODE=false
if [[ ${#USERNAMES[@]} -gt 1 ]]; then
    BATCH_MODE=true
fi

# Validate all usernames first
for USERNAME in "${USERNAMES[@]}"; do
    if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid username '$USERNAME'. Use only letters, numbers, underscores, and hyphens."
        exit 1
    fi
    if [[ -d "outputs/bundles/$USERNAME" ]]; then
        log_error "User '$USERNAME' already exists. Use a different name or revoke first."
        log_error "To revoke: ./scripts/user-revoke.sh $USERNAME"
        exit 1
    fi
done

# Load environment
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi

# Display batch info
if [[ "$BATCH_MODE" == "true" ]]; then
    log_info "========================================"
    log_info "Batch creating ${#USERNAMES[@]} users"
    log_info "========================================"
    echo ""
    echo "Users to create:"
    for u in "${USERNAMES[@]}"; do
        echo "  • $u"
    done
    echo ""
fi

# Track created users for summary
CREATED_USERS=()
FAILED_USERS=()

# -----------------------------------------------------------------------------
# Create each user
# -----------------------------------------------------------------------------
for USERNAME in "${USERNAMES[@]}"; do
    OUTPUT_DIR="outputs/bundles/$USERNAME"
    mkdir -p "$OUTPUT_DIR"

    log_info "========================================"
    log_info "Adding user '$USERNAME' to all services"
    log_info "========================================"
    echo ""

    ERRORS=()

    # Determine reload flag for sub-scripts
    RELOAD_FLAG=""
    if [[ "$BATCH_MODE" == "true" ]]; then
        RELOAD_FLAG="--no-reload"
    fi

    # -------------------------------------------------------------------------
    # Add to sing-box (Reality, Trojan, Hysteria2)
    # -------------------------------------------------------------------------
    if [[ -f "configs/sing-box/config.json" ]]; then
        log_info "[1/2] Adding to sing-box (Reality, Trojan, Hysteria2)..."
        if "$SCRIPT_DIR/singbox-user-add.sh" "$USERNAME" $RELOAD_FLAG; then
            log_info "✓ sing-box user added"
        else
            ERRORS+=("sing-box")
            log_error "✗ Failed to add sing-box user"
        fi
    else
        log_info "[1/2] Skipping sing-box (not configured)"
    fi

    echo ""

    # -------------------------------------------------------------------------
    # Add to WireGuard
    # -------------------------------------------------------------------------
    if [[ "${ENABLE_WIREGUARD:-true}" == "true" ]] && [[ -f "configs/wireguard/wg0.conf" ]]; then
        log_info "[2/2] Adding to WireGuard..."
        if "$SCRIPT_DIR/wg-user-add.sh" "$USERNAME" $RELOAD_FLAG; then
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
    CONFIG_CDN=$(cat "$OUTPUT_DIR/cdn-vless-ws.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_WIREGUARD=$(cat "$OUTPUT_DIR/wireguard.conf" 2>/dev/null || echo "")
    CONFIG_WIREGUARD_WSTUNNEL=$(cat "$OUTPUT_DIR/wireguard-wstunnel.conf" 2>/dev/null || echo "")

    # Get CDN domain from .env
    CDN_DOMAIN="${CDN_DOMAIN:-$(grep -E '^CDN_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")}"

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

    # Python-based placeholder replacement - handles special chars and multiline safely
    replace_placeholder() {
        local placeholder="$1"
        local value="$2"
        python3 -c "
import sys
placeholder = sys.argv[1]
value = sys.argv[2]
filepath = sys.argv[3]
with open(filepath, 'r') as f:
    content = f.read()
content = content.replace(placeholder, value)
with open(filepath, 'w') as f:
    f.write(content)
" "$placeholder" "$value" "$OUTPUT_HTML"
    }

    # TrustTunnel password
    if [[ -n "${USER_PASSWORD:-}" ]]; then
        replace_placeholder "{{TRUSTTUNNEL_PASSWORD}}" "$USER_PASSWORD"
    else
        replace_placeholder "{{TRUSTTUNNEL_PASSWORD}}" "See trusttunnel.txt"
    fi

    # Remove demo notice placeholders (not a demo user)
    replace_placeholder "{{DEMO_NOTICE_EN}}" ""
    replace_placeholder "{{DEMO_NOTICE_FA}}" ""

    # QR codes (base64) - these are safe for sed (no special chars in base64)
    sed -i.bak "s|{{QR_REALITY}}|$QR_REALITY_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_HYSTERIA2}}|$QR_HYSTERIA2_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_TROJAN}}|$QR_TROJAN_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_WIREGUARD}}|$QR_WIREGUARD_B64|g" "$OUTPUT_HTML"
    sed -i.bak "s|{{QR_WIREGUARD_WSTUNNEL}}|$QR_WIREGUARD_WSTUNNEL_B64|g" "$OUTPUT_HTML"

    if [[ -n "$CONFIG_REALITY" ]]; then
        replace_placeholder "{{CONFIG_REALITY}}" "$CONFIG_REALITY"
    else
        replace_placeholder "{{CONFIG_REALITY}}" "No Reality config available"
    fi

    if [[ -n "$CONFIG_HYSTERIA2" ]]; then
        replace_placeholder "{{CONFIG_HYSTERIA2}}" "$CONFIG_HYSTERIA2"
    else
        replace_placeholder "{{CONFIG_HYSTERIA2}}" "No Hysteria2 config available"
    fi

    if [[ -n "$CONFIG_TROJAN" ]]; then
        replace_placeholder "{{CONFIG_TROJAN}}" "$CONFIG_TROJAN"
    else
        replace_placeholder "{{CONFIG_TROJAN}}" "No Trojan config available"
    fi

    # CDN VLESS+WS config
    if [[ -n "$CONFIG_CDN" ]]; then
        replace_placeholder "{{CONFIG_CDN}}" "$CONFIG_CDN"
        replace_placeholder "{{CDN_DOMAIN}}" "$CDN_DOMAIN"
        # CDN QR code
        QR_CDN_B64=$(qr_to_base64 "$OUTPUT_DIR/cdn-vless-ws-qr.png")
        sed -i.bak "s|{{QR_CDN}}|$QR_CDN_B64|g" "$OUTPUT_HTML"
    else
        replace_placeholder "{{CONFIG_CDN}}" "CDN not configured"
        replace_placeholder "{{CDN_DOMAIN}}" "Not configured"
        sed -i.bak "s|{{QR_CDN}}||g" "$OUTPUT_HTML"
    fi

    # WireGuard configs (multiline)
    if [[ -n "$CONFIG_WIREGUARD" ]]; then
        replace_placeholder "{{CONFIG_WIREGUARD}}" "$CONFIG_WIREGUARD"
    else
        replace_placeholder "{{CONFIG_WIREGUARD}}" "No WireGuard config available"
    fi

    if [[ -n "$CONFIG_WIREGUARD_WSTUNNEL" ]]; then
        replace_placeholder "{{CONFIG_WIREGUARD_WSTUNNEL}}" "$CONFIG_WIREGUARD_WSTUNNEL"
    else
        replace_placeholder "{{CONFIG_WIREGUARD_WSTUNNEL}}" "No WireGuard-wstunnel config available"
    fi

    # Clean up backup files
    rm -f "$OUTPUT_HTML.bak"

    log_info "✓ README.html generated"
else
    log_warn "Template not found: $TEMPLATE_FILE - skipping HTML guide"
fi

    # -------------------------------------------------------------------------
    # Summary for this user
    # -------------------------------------------------------------------------
    echo ""
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        log_error "User '$USERNAME' failed: ${ERRORS[*]}"
        FAILED_USERS+=("$USERNAME")
    else
        log_info "✓ User '$USERNAME' created successfully"
        CREATED_USERS+=("$USERNAME")
    fi

    # -------------------------------------------------------------------------
    # Create package if requested
    # -------------------------------------------------------------------------
    if [[ "$CREATE_PACKAGE" == "true" ]]; then
        log_info "Creating package for $USERNAME..."
        if "$SCRIPT_DIR/user-package.sh" "$USERNAME"; then
            log_info "✓ Package created: outputs/bundles/$USERNAME.zip"
        else
            log_error "✗ Failed to create package for $USERNAME"
        fi
    fi

    echo ""
done
# End of user creation loop

# -----------------------------------------------------------------------------
# Reload services once (for batch mode)
# -----------------------------------------------------------------------------
if [[ "$BATCH_MODE" == "true" ]] && [[ ${#CREATED_USERS[@]} -gt 0 ]]; then
    echo ""
    log_info "========================================"
    log_info "Reloading services..."
    log_info "========================================"

    # Reload sing-box
    if [[ -f "configs/sing-box/config.json" ]]; then
        if docker compose ps sing-box --status running &>/dev/null; then
            log_info "Reloading sing-box..."
            if docker compose exec -T sing-box sing-box reload 2>/dev/null; then
                log_info "✓ sing-box reloaded"
            else
                log_info "Hot reload failed, restarting sing-box..."
                docker compose restart sing-box
            fi
        fi
    fi

    # Reload WireGuard (needs to sync peers)
    if [[ "${ENABLE_WIREGUARD:-true}" == "true" ]] && [[ -f "configs/wireguard/wg0.conf" ]]; then
        if docker compose ps wireguard --status running &>/dev/null; then
            log_info "Syncing WireGuard peers..."
            docker compose exec -T wireguard wg syncconf wg0 <(docker compose exec -T wireguard wg-quick strip wg0) 2>/dev/null || \
                docker compose restart wireguard
            log_info "✓ WireGuard synced"
        fi
    fi

    # Reload TrustTunnel
    if [[ -f "configs/trusttunnel/credentials.toml" ]]; then
        if docker compose ps trusttunnel --status running &>/dev/null; then
            log_info "Restarting TrustTunnel..."
            docker compose restart trusttunnel
            log_info "✓ TrustTunnel restarted"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Final Summary
# -----------------------------------------------------------------------------
echo ""
log_info "========================================"
log_info "Batch Creation Summary"
log_info "========================================"
echo ""

if [[ ${#CREATED_USERS[@]} -gt 0 ]]; then
    log_info "✓ Created ${#CREATED_USERS[@]} users:"
    for u in "${CREATED_USERS[@]}"; do
        echo "    • $u"
    done
fi

if [[ ${#FAILED_USERS[@]} -gt 0 ]]; then
    log_error "✗ Failed ${#FAILED_USERS[@]} users:"
    for u in "${FAILED_USERS[@]}"; do
        echo "    • $u"
    done
fi

echo ""
log_info "Bundles location: outputs/bundles/"

if [[ "$CREATE_PACKAGE" != "true" ]] && [[ ${#CREATED_USERS[@]} -gt 0 ]]; then
    log_info "Tip: Use --package to create zip files with HTML guides"
fi

# Exit with error if any users failed
if [[ ${#FAILED_USERS[@]} -gt 0 ]]; then
    exit 1
fi
