#!/bin/bash
set -euo pipefail

# =============================================================================
# MoaV Bootstrap Script
# Initializes the stack on first run: generates keys, creates users, configs
# =============================================================================

source /app/lib/common.sh
source /app/lib/sing-box.sh
source /app/lib/wireguard.sh
source /app/lib/dnstt.sh

log_info "Starting MoaV bootstrap..."

# -----------------------------------------------------------------------------
# Validate required environment variables
# -----------------------------------------------------------------------------
required_vars=(
    "DOMAIN"
    "INITIAL_USERS"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit 1
    fi
done

# -----------------------------------------------------------------------------
# Detect server IP if not provided
# -----------------------------------------------------------------------------
if [[ -z "${SERVER_IP:-}" ]]; then
    log_info "SERVER_IP not set, detecting..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || echo "")
    if [[ -z "$SERVER_IP" ]]; then
        log_error "Could not detect server IP. Please set SERVER_IP in .env"
        exit 1
    fi
    log_info "Detected server IP: $SERVER_IP"
fi

export SERVER_IP

# -----------------------------------------------------------------------------
# Detect server IPv6 if not provided or disabled
# -----------------------------------------------------------------------------
if [[ "${SERVER_IPV6:-}" == "disabled" ]]; then
    log_info "IPv6 explicitly disabled"
    SERVER_IPV6=""
elif [[ -z "${SERVER_IPV6:-}" ]]; then
    log_info "SERVER_IPV6 not set, detecting..."
    SERVER_IPV6=$(curl -6 -s --max-time 5 https://api6.ipify.org 2>/dev/null || curl -6 -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    if [[ -n "$SERVER_IPV6" ]]; then
        log_info "Detected server IPv6: $SERVER_IPV6"
    else
        log_info "No IPv6 detected (this is normal, IPv6 is optional)"
    fi
fi

export SERVER_IPV6

# -----------------------------------------------------------------------------
# Initialize state directory
# -----------------------------------------------------------------------------
export STATE_DIR="/state"
mkdir -p "$STATE_DIR"/{users,keys}

# Check if already bootstrapped
if [[ -f "$STATE_DIR/.bootstrapped" ]]; then
    log_info "Already bootstrapped. To re-bootstrap, run:"
    log_info "  docker run --rm -v moav_moav_state:/state alpine rm /state/.bootstrapped"
    log_info "  docker compose --profile setup run --rm bootstrap"
    exit 0
fi

# -----------------------------------------------------------------------------
# Generate Reality keys if not provided
# -----------------------------------------------------------------------------
if [[ -z "${REALITY_PRIVATE_KEY:-}" ]]; then
    log_info "Generating Reality keypair..."
    REALITY_KEYS=$(sing-box generate reality-keypair)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep "PrivateKey" | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep "PublicKey" | awk '{print $2}')
else
    REALITY_PUBLIC_KEY=$(sing-box generate reality-keypair --private-key "$REALITY_PRIVATE_KEY" 2>/dev/null | grep "PublicKey" | awk '{print $2}' || echo "")
fi

if [[ -z "${REALITY_SHORT_ID:-}" ]]; then
    REALITY_SHORT_ID=$(openssl rand -hex 4)
fi

# Save keys to state
cat > "$STATE_DIR/keys/reality.env" <<EOF
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
EOF

log_info "Reality keys saved to $STATE_DIR/keys/reality.env"

# -----------------------------------------------------------------------------
# Generate Clash API secret
# -----------------------------------------------------------------------------
CLASH_API_SECRET=$(pwgen -s 32 1)
echo "CLASH_API_SECRET=$CLASH_API_SECRET" > "$STATE_DIR/keys/clash-api.env"

# -----------------------------------------------------------------------------
# Parse Reality target
# -----------------------------------------------------------------------------
REALITY_TARGET_HOST=$(echo "${REALITY_TARGET:-www.microsoft.com:443}" | cut -d: -f1)
REALITY_TARGET_PORT=$(echo "${REALITY_TARGET:-www.microsoft.com:443}" | cut -d: -f2)

# -----------------------------------------------------------------------------
# Export variables needed by generate-user.sh
# -----------------------------------------------------------------------------
export REALITY_PUBLIC_KEY
export REALITY_SHORT_ID
export REALITY_TARGET="${REALITY_TARGET:-www.microsoft.com:443}"
export DOMAIN="${DOMAIN:-example.com}"
export DNSTT_SUBDOMAIN="${DNSTT_SUBDOMAIN:-t}"
export ENABLE_WIREGUARD="${ENABLE_WIREGUARD:-true}"
export ENABLE_DNSTT="${ENABLE_DNSTT:-true}"

# -----------------------------------------------------------------------------
# Generate WireGuard server config (before creating users)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_WIREGUARD:-true}" == "true" ]]; then
    log_info "Generating WireGuard server configuration..."
    generate_wireguard_config

    # Verify keys are consistent
    if [[ -f "$STATE_DIR/keys/wg-server.key" ]] && [[ -f "/configs/wireguard/server.pub" ]]; then
        DERIVED_PUB=$(cat "$STATE_DIR/keys/wg-server.key" | wg pubkey)
        SAVED_PUB=$(cat "/configs/wireguard/server.pub")
        if [[ "$DERIVED_PUB" == "$SAVED_PUB" ]]; then
            log_info "WireGuard keys verified: public key matches private key"
        else
            log_error "WireGuard key mismatch! Fixing..."
            echo "$DERIVED_PUB" > "/configs/wireguard/server.pub"
            echo "$DERIVED_PUB" > "$STATE_DIR/keys/wg-server.pub"
            log_info "Fixed server.pub to match private key"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Generate dnstt server config (before creating users)
# -----------------------------------------------------------------------------
log_info "ENABLE_DNSTT=${ENABLE_DNSTT:-true}"
if [[ "${ENABLE_DNSTT:-true}" == "true" ]]; then
    log_info "Generating dnstt server configuration..."
    if generate_dnstt_config; then
        log_info "dnstt configuration complete"
        # Verify key file exists
        if [[ -f "$STATE_DIR/keys/dnstt-server.key.hex" ]]; then
            log_info "dnstt key file verified: $(wc -c < "$STATE_DIR/keys/dnstt-server.key.hex") bytes"
        else
            log_error "dnstt key file NOT found after generation!"
        fi
    else
        log_error "dnstt configuration FAILED"
    fi
else
    log_info "dnstt is disabled, skipping configuration"
fi

# -----------------------------------------------------------------------------
# Create initial users
# -----------------------------------------------------------------------------
log_info "Creating $INITIAL_USERS initial users..."

REALITY_USERS_JSON="["
TROJAN_USERS_JSON="["
HYSTERIA2_USERS_JSON="["

for i in $(seq -w 1 "$INITIAL_USERS"); do
    # Use "demouser" for single user, otherwise "user01", "user02", etc.
    if [[ "$INITIAL_USERS" == "1" ]]; then
        USER_ID="demouser"
        export IS_DEMO_USER="true"
    else
        USER_ID="user$i"
        export IS_DEMO_USER="false"
    fi
    USER_UUID=$(sing-box generate uuid)
    USER_PASSWORD=$(pwgen -s 24 1)

    log_info "Creating user: $USER_ID"

    # Store user credentials
    mkdir -p "$STATE_DIR/users/$USER_ID"
    cat > "$STATE_DIR/users/$USER_ID/credentials.env" <<EOF
USER_ID=$USER_ID
USER_UUID=$USER_UUID
USER_PASSWORD=$USER_PASSWORD
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    # Build JSON arrays for sing-box config
    [[ $i -gt 1 ]] && REALITY_USERS_JSON+=","
    [[ $i -gt 1 ]] && TROJAN_USERS_JSON+=","
    [[ $i -gt 1 ]] && HYSTERIA2_USERS_JSON+=","

    REALITY_USERS_JSON+="{\"name\":\"$USER_ID\",\"uuid\":\"$USER_UUID\",\"flow\":\"xtls-rprx-vision\"}"
    TROJAN_USERS_JSON+="{\"name\":\"$USER_ID\",\"password\":\"$USER_PASSWORD\"}"
    HYSTERIA2_USERS_JSON+="{\"name\":\"$USER_ID\",\"password\":\"$USER_PASSWORD\"}"

    # Generate user bundle
    /app/generate-user.sh "$USER_ID"
done

REALITY_USERS_JSON+="]"
TROJAN_USERS_JSON+="]"
HYSTERIA2_USERS_JSON+="]"

# -----------------------------------------------------------------------------
# Generate sing-box config
# -----------------------------------------------------------------------------
log_info "Generating sing-box configuration..."

export REALITY_USERS_JSON
export TROJAN_USERS_JSON
export HYSTERIA2_USERS_JSON
export REALITY_PRIVATE_KEY
export REALITY_SHORT_ID
export REALITY_TARGET_HOST
export REALITY_TARGET_PORT
export REALITY_SERVER_NAME="$REALITY_TARGET_HOST"
export CLASH_API_SECRET
export LOG_LEVEL="${LOG_LEVEL:-info}"

envsubst < /configs/sing-box/config.json.template > /configs/sing-box/config.json

log_info "sing-box configuration written to /configs/sing-box/config.json"

# -----------------------------------------------------------------------------
# Mark as bootstrapped
# -----------------------------------------------------------------------------
date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE_DIR/.bootstrapped"

log_info "Bootstrap complete!"
log_info "User bundles are in /outputs/bundles/"
log_info ""
log_info "Next steps:"
log_info "  1. Configure DNS records (see docs/DNS.md)"
log_info "  2. Start the stack: docker compose up -d"
log_info "  3. Distribute user bundles to your contacts"
