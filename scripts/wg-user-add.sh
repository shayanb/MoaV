#!/bin/bash
set -euo pipefail

# =============================================================================
# Add a new WireGuard peer
# Usage: ./scripts/wg-user-add.sh <username>
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 john"
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

WG_CONFIG_DIR="configs/wireguard"
STATE_DIR="${STATE_DIR:-./state}"
OUTPUT_DIR="outputs/bundles/$USERNAME"
WG_NETWORK="10.66.66.0/24"

# Check if WireGuard config exists
if [[ ! -f "$WG_CONFIG_DIR/wg0.conf" ]]; then
    log_error "WireGuard config not found. Run bootstrap first or enable WireGuard."
    exit 1
fi

# Create directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$STATE_DIR/users/$USERNAME"

# Check if peer already exists
if grep -q "# $USERNAME\$" "$WG_CONFIG_DIR/wg0.conf" 2>/dev/null; then
    log_error "WireGuard peer '$USERNAME' already exists."
    exit 1
fi

log_info "Adding WireGuard peer '$USERNAME'..."

# Find next available IP
# Get all used IPs from config
USED_IPS=$(grep -oP 'AllowedIPs = 10\.66\.66\.\K[0-9]+' "$WG_CONFIG_DIR/wg0.conf" 2>/dev/null || echo "")
NEXT_IP=2  # Start from .2 (server is .1)

for ip in $USED_IPS; do
    if [[ $ip -ge $NEXT_IP ]]; then
        NEXT_IP=$((ip + 1))
    fi
done

if [[ $NEXT_IP -gt 254 ]]; then
    log_error "No available IPs in WireGuard network"
    exit 1
fi

CLIENT_IP="10.66.66.$NEXT_IP"
log_info "Assigned IP: $CLIENT_IP"

# Generate client keys using wg command in wireguard container or locally
if docker compose ps wireguard --status running &>/dev/null; then
    # Use running WireGuard container
    CLIENT_PRIVATE_KEY=$(docker compose exec -T wireguard wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | docker compose exec -T wireguard wg pubkey)
elif command -v wg &>/dev/null; then
    # Use local wg command
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
else
    # Generate using docker
    CLIENT_PRIVATE_KEY=$(docker run --rm lscr.io/linuxserver/wireguard wg genkey 2>/dev/null)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | docker run --rm -i lscr.io/linuxserver/wireguard wg pubkey 2>/dev/null)
fi

# Save credentials
cat > "$STATE_DIR/users/$USERNAME/wireguard.env" <<EOF
WG_PRIVATE_KEY=$CLIENT_PRIVATE_KEY
WG_PUBLIC_KEY=$CLIENT_PUBLIC_KEY
WG_CLIENT_IP=$CLIENT_IP
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# Get server public key
SERVER_PUBLIC_KEY=$(cat "$WG_CONFIG_DIR/server.pub" 2>/dev/null || echo "")
if [[ -z "$SERVER_PUBLIC_KEY" ]]; then
    log_error "Server public key not found"
    exit 1
fi

# Get server IP
SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org || echo "YOUR_SERVER_IP")}"

# Add peer to server config file
cat >> "$WG_CONFIG_DIR/wg0.conf" <<EOF

[Peer]
# $USERNAME
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32
EOF

log_info "Added peer to wg0.conf"

# Generate client config
cat > "$OUTPUT_DIR/wireguard.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${SERVER_IP}:443
PersistentKeepalive = 25
EOF

log_info "Generated client config"

# Generate QR code
QR_GENERATED=false
if command -v qrencode &>/dev/null; then
    qrencode -o "$OUTPUT_DIR/wireguard-qr.png" -s 6 -r "$OUTPUT_DIR/wireguard.conf" 2>/dev/null && QR_GENERATED=true
fi

# Hot-add peer to running WireGuard if available
if docker compose ps wireguard --status running &>/dev/null; then
    log_info "Adding peer to running WireGuard..."

    # Use wg set to add peer dynamically
    if docker compose exec -T wireguard wg set wg0 peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_IP/32" 2>/dev/null; then
        log_info "Peer added to running WireGuard (hot reload)"
    else
        log_info "Hot reload failed, you may need to restart WireGuard"
        log_info "Run: docker compose --profile wireguard restart wireguard"
    fi
else
    log_info "WireGuard not running, config will apply on next start"
fi

# Display results
echo ""
log_info "=== WireGuard peer '$USERNAME' created ==="
echo ""
echo "Client IP: $CLIENT_IP"
echo "Config saved to: $OUTPUT_DIR/wireguard.conf"
echo ""

# Display QR code in terminal if possible
if command -v qrencode &>/dev/null; then
    echo "=== QR Code (scan with WireGuard app) ==="
    qrencode -t ANSIUTF8 -r "$OUTPUT_DIR/wireguard.conf" 2>/dev/null || true
    echo ""
fi

if [[ "$QR_GENERATED" == "true" ]]; then
    log_info "QR image saved to: $OUTPUT_DIR/wireguard-qr.png"
fi

echo ""
echo "=== Client Config ==="
cat "$OUTPUT_DIR/wireguard.conf"
