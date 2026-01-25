#!/bin/bash
set -euo pipefail

# =============================================================================
# Generate a single new user (called by user-add.sh)
# =============================================================================

source /app/lib/common.sh
source /app/lib/wireguard.sh
source /app/lib/dnstt.sh

USER_ID="${1:-}"

if [[ -z "$USER_ID" ]]; then
    log_error "Usage: generate-single-user.sh <user_id>"
    exit 1
fi

# Load state
STATE_DIR="/state"
source "$STATE_DIR/keys/reality.env"

# Check if user already exists
if [[ -d "$STATE_DIR/users/$USER_ID" ]]; then
    log_error "User $USER_ID already exists"
    exit 1
fi

# Generate credentials
USER_UUID=$(sing-box generate uuid)
USER_PASSWORD=$(pwgen -s 24 1)

# Store credentials
mkdir -p "$STATE_DIR/users/$USER_ID"
cat > "$STATE_DIR/users/$USER_ID/credentials.env" <<EOF
USER_ID=$USER_ID
USER_UUID=$USER_UUID
USER_PASSWORD=$USER_PASSWORD
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log_info "Created credentials for $USER_ID"

# Add to sing-box config
CONFIG_FILE="/configs/sing-box/config.json"

if [[ -f "$CONFIG_FILE" ]]; then
    # Add to Reality inbound
    jq --arg name "$USER_ID" --arg uuid "$USER_UUID" \
        '(.inbounds[] | select(.tag == "vless-reality-in") | .users) += [{"name": $name, "uuid": $uuid, "flow": "xtls-rprx-vision"}]' \
        "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    # Add to Trojan inbound
    jq --arg name "$USER_ID" --arg password "$USER_PASSWORD" \
        '(.inbounds[] | select(.tag == "trojan-tls-in") | .users) += [{"name": $name, "password": $password}]' \
        "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    # Add to Hysteria2 inbound
    jq --arg name "$USER_ID" --arg password "$USER_PASSWORD" \
        '(.inbounds[] | select(.tag == "hysteria2-in") | .users) += [{"name": $name, "password": $password}]' \
        "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    log_info "Added $USER_ID to sing-box config"
fi

# Generate bundle
export STATE_DIR
export USER_ID USER_UUID USER_PASSWORD
export REALITY_PUBLIC_KEY REALITY_SHORT_ID
export SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org)}"
export DOMAIN="${DOMAIN:-example.com}"
export REALITY_TARGET="${REALITY_TARGET:-www.microsoft.com:443}"
export ENABLE_WIREGUARD="${ENABLE_WIREGUARD:-true}"
export ENABLE_DNSTT="${ENABLE_DNSTT:-true}"
export DNSTT_SUBDOMAIN="${DNSTT_SUBDOMAIN:-t}"

/app/generate-user.sh "$USER_ID"

log_info "User $USER_ID bundle generated at /outputs/bundles/$USER_ID/"
