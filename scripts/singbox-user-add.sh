#!/bin/bash
set -euo pipefail

# =============================================================================
# Add a new user to sing-box (Reality, Trojan, Hysteria2)
# Usage: ./scripts/singbox-user-add.sh <username>
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

CONFIG_FILE="configs/sing-box/config.json"
STATE_DIR="${STATE_DIR:-./state}"
OUTPUT_DIR="outputs/bundles/$USERNAME"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "sing-box config not found. Run bootstrap first."
    exit 1
fi

# Create directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$STATE_DIR/users/$USERNAME"

# Check if user already exists in config
if grep -q "\"name\":\"$USERNAME\"" "$CONFIG_FILE" 2>/dev/null; then
    log_error "User '$USERNAME' already exists in sing-box config."
    exit 1
fi

log_info "Adding user '$USERNAME' to sing-box..."

# Generate credentials
USER_UUID=$(docker compose exec -T sing-box sing-box generate uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')
USER_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)

# Save credentials
cat > "$STATE_DIR/users/$USERNAME/credentials.env" <<EOF
USER_ID=$USERNAME
USER_UUID=$USER_UUID
USER_PASSWORD=$USER_PASSWORD
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log_info "Generated credentials for $USERNAME"

# Add user to sing-box config using jq
# Create temp file with updated config
TEMP_CONFIG=$(mktemp)

# Add to Reality users (vless)
jq --arg name "$USERNAME" --arg uuid "$USER_UUID" \
    '.inbounds |= map(if .tag == "vless-reality-in" then .users += [{"name": $name, "uuid": $uuid, "flow": "xtls-rprx-vision"}] else . end)' \
    "$CONFIG_FILE" > "$TEMP_CONFIG"

# Add to Trojan users
jq --arg name "$USERNAME" --arg pass "$USER_PASSWORD" \
    '.inbounds |= map(if .tag == "trojan-tls-in" then .users += [{"name": $name, "password": $pass}] else . end)' \
    "$TEMP_CONFIG" > "${TEMP_CONFIG}.2"
mv "${TEMP_CONFIG}.2" "$TEMP_CONFIG"

# Add to Hysteria2 users
jq --arg name "$USERNAME" --arg pass "$USER_PASSWORD" \
    '.inbounds |= map(if .tag == "hysteria2-in" then .users += [{"name": $name, "password": $pass}] else . end)' \
    "$TEMP_CONFIG" > "${TEMP_CONFIG}.2"
mv "${TEMP_CONFIG}.2" "$TEMP_CONFIG"

# Validate the new config
if ! jq empty "$TEMP_CONFIG" 2>/dev/null; then
    log_error "Generated invalid JSON config"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# Apply the config
mv "$TEMP_CONFIG" "$CONFIG_FILE"

log_info "Added $USERNAME to sing-box config"

# Load keys for client config generation
if [[ -f "$STATE_DIR/keys/reality.env" ]]; then
    source "$STATE_DIR/keys/reality.env"
else
    # Try docker volume
    REALITY_PUBLIC_KEY=$(docker run --rm -v moav_moav_state:/state alpine cat /state/keys/reality.env 2>/dev/null | grep REALITY_PUBLIC_KEY | cut -d= -f2 || echo "")
    REALITY_SHORT_ID=$(docker run --rm -v moav_moav_state:/state alpine cat /state/keys/reality.env 2>/dev/null | grep REALITY_SHORT_ID | cut -d= -f2 || echo "")
fi

# Get server IP
SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org || echo "YOUR_SERVER_IP")}"

# Parse Reality target
REALITY_TARGET="${REALITY_TARGET:-www.microsoft.com:443}"
REALITY_TARGET_HOST=$(echo "$REALITY_TARGET" | cut -d: -f1)

# -----------------------------------------------------------------------------
# Generate client configs
# -----------------------------------------------------------------------------

# Reality link
REALITY_LINK="vless://${USER_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET_HOST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#MoaV-Reality-${USERNAME}"
echo "$REALITY_LINK" > "$OUTPUT_DIR/reality.txt"

# Trojan link
TROJAN_LINK="trojan://${USER_PASSWORD}@${SERVER_IP}:8443?security=tls&sni=${DOMAIN}&type=tcp#MoaV-Trojan-${USERNAME}"
echo "$TROJAN_LINK" > "$OUTPUT_DIR/trojan.txt"

# Hysteria2 link
HY2_LINK="hysteria2://${USER_PASSWORD}@${SERVER_IP}:443?sni=${DOMAIN}#MoaV-Hysteria2-${USERNAME}"
echo "$HY2_LINK" > "$OUTPUT_DIR/hysteria2.txt"

# Generate QR codes
if command -v qrencode &>/dev/null; then
    qrencode -o "$OUTPUT_DIR/reality-qr.png" -s 6 "$REALITY_LINK" 2>/dev/null || true
    qrencode -o "$OUTPUT_DIR/trojan-qr.png" -s 6 "$TROJAN_LINK" 2>/dev/null || true
    qrencode -o "$OUTPUT_DIR/hysteria2-qr.png" -s 6 "$HY2_LINK" 2>/dev/null || true
fi

# Try to reload sing-box (hot reload)
if docker compose ps sing-box --status running &>/dev/null; then
    log_info "Reloading sing-box..."
    if docker compose exec -T sing-box sing-box reload 2>/dev/null; then
        log_info "sing-box reloaded successfully"
    else
        log_info "Hot reload failed, restarting sing-box..."
        docker compose restart sing-box
    fi
else
    log_info "sing-box not running, config will apply on next start"
fi

echo ""
log_info "=== sing-box user '$USERNAME' created ==="
echo ""
echo "Reality Link:"
echo "$REALITY_LINK"
echo ""
echo "Trojan Link:"
echo "$TROJAN_LINK"
echo ""
echo "Hysteria2 Link:"
echo "$HY2_LINK"
echo ""
log_info "Config files saved to: $OUTPUT_DIR/"
