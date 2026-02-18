#!/bin/bash
set -euo pipefail

# =============================================================================
# MoaV Bootstrap Script
# Initializes the stack on first run: generates keys, creates users, configs
# =============================================================================

source /app/lib/common.sh
source /app/lib/sing-box.sh
source /app/lib/wireguard.sh
source /app/lib/amneziawg.sh
source /app/lib/dnstt.sh

log_info "Starting MoaV bootstrap..."

# -----------------------------------------------------------------------------
# Validate required environment variables
# -----------------------------------------------------------------------------
required_vars=(
    "INITIAL_USERS"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit 1
    fi
done

# Check if DOMAIN is required (needed for TLS-based protocols)
# Domain is required if ANY of: Reality, Trojan, Hysteria2, or dnstt is enabled
# Note: Admin UI works without domain using self-signed certificates
domain_required=false
[[ "${ENABLE_REALITY:-true}" == "true" ]] && domain_required=true
[[ "${ENABLE_TROJAN:-true}" == "true" ]] && domain_required=true
[[ "${ENABLE_HYSTERIA2:-true}" == "true" ]] && domain_required=true
[[ "${ENABLE_DNSTT:-true}" == "true" ]] && domain_required=true
[[ "${ENABLE_TRUSTTUNNEL:-true}" == "true" ]] && domain_required=true

if [[ "$domain_required" == "true" ]] && [[ -z "${DOMAIN:-}" ]]; then
    log_error "DOMAIN is required when TLS-based protocols are enabled"
    log_error ""
    log_error "Option 1: Set a domain in .env"
    log_error "  DOMAIN=your-domain.com"
    log_error ""
    log_error "Option 2: Run in domain-less mode (WireGuard, Conduit, Snowflake, Admin)"
    log_error "  Add these lines to your .env file:"
    log_error "    ENABLE_REALITY=false"
    log_error "    ENABLE_TROJAN=false"
    log_error "    ENABLE_HYSTERIA2=false"
    log_error "    ENABLE_DNSTT=false"
    log_error "    ENABLE_TRUSTTUNNEL=false"
    log_error ""
    log_error "  Or run this command to disable them:"
    log_error "    sed -i 's/^ENABLE_REALITY=.*/ENABLE_REALITY=false/; s/^ENABLE_TROJAN=.*/ENABLE_TROJAN=false/; s/^ENABLE_HYSTERIA2=.*/ENABLE_HYSTERIA2=false/; s/^ENABLE_DNSTT=.*/ENABLE_DNSTT=false/; s/^ENABLE_TRUSTTUNNEL=.*/ENABLE_TRUSTTUNNEL=false/' .env"
    exit 1
fi

# Domain-less mode notice
if [[ -z "${DOMAIN:-}" ]]; then
    log_info "Running in domain-less mode (WireGuard, Conduit, Snowflake, Admin)"

    # Generate self-signed certificate for admin UI (if not exists)
    if [[ "${ENABLE_ADMIN_UI:-true}" == "true" ]]; then
        SELFSIGNED_DIR="/certs/selfsigned"
        if [[ ! -f "$SELFSIGNED_DIR/fullchain.pem" ]]; then
            log_info "Generating self-signed certificate for admin dashboard..."
            mkdir -p "$SELFSIGNED_DIR"
            openssl req -x509 -newkey rsa:4096 \
                -keyout "$SELFSIGNED_DIR/privkey.pem" \
                -out "$SELFSIGNED_DIR/fullchain.pem" \
                -days 365 -nodes \
                -subj "/CN=MoaV Admin" \
                2>/dev/null
            log_info "Self-signed certificate created (valid for 365 days)"
            log_info "Note: Browser will show security warning - this is expected"
        else
            log_info "Self-signed certificate already exists"
        fi
    fi
fi

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
# Generate Reality keys if not provided (only if Reality is enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_REALITY:-true}" == "true" ]]; then
    # Load existing Reality keys from state if available
    if [[ -f "$STATE_DIR/keys/reality.env" ]]; then
        log_info "Loading existing Reality keys from state..."
        source "$STATE_DIR/keys/reality.env"
    fi

    if [[ -z "${REALITY_PRIVATE_KEY:-}" ]]; then
        log_info "Generating Reality keypair..."
        REALITY_KEYS=$(sing-box generate reality-keypair)
        REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep "PrivateKey" | awk '{print $2}')
        REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep "PublicKey" | awk '{print $2}')
    else
        REALITY_PUBLIC_KEY=$(sing-box generate reality-keypair --private-key "$REALITY_PRIVATE_KEY" 2>/dev/null | grep "PublicKey" | awk '{print $2}' || echo "")
        log_info "Reality keypair already exists, skipping generation"
    fi

    if [[ -z "${REALITY_SHORT_ID:-}" ]]; then
        REALITY_SHORT_ID=$(openssl rand -hex 4)
    else
        log_info "Reality short ID already exists, skipping generation"
    fi

    # Save keys to state
    cat > "$STATE_DIR/keys/reality.env" <<EOF
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
EOF

    log_info "Reality keys saved to $STATE_DIR/keys/reality.env"
else
    log_info "Reality is disabled, skipping key generation"
    REALITY_PUBLIC_KEY=""
    REALITY_SHORT_ID=""
fi

# -----------------------------------------------------------------------------
# Generate Clash API secret (only if sing-box protocols are enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_REALITY:-true}" == "true" ]] || [[ "${ENABLE_TROJAN:-true}" == "true" ]] || [[ "${ENABLE_HYSTERIA2:-true}" == "true" ]]; then
    # Load existing secrets from state if available
    if [[ -f "$STATE_DIR/keys/clash-api.env" ]]; then
        source "$STATE_DIR/keys/clash-api.env"
    fi

    if [[ -z "${CLASH_API_SECRET:-}" ]]; then
        CLASH_API_SECRET=$(pwgen -s 32 1)
        log_info "Generated new Clash API secret"
    else
        log_info "Clash API secret already exists, skipping generation"
    fi

    # Generate Hysteria2 obfuscation password (for bypassing QUIC blocking)
    if [[ -z "${HYSTERIA2_OBFS_PASSWORD:-}" ]]; then
        HYSTERIA2_OBFS_PASSWORD=$(pwgen -s 24 1)
        log_info "Generated Hysteria2 obfuscation password"
    else
        log_info "Hysteria2 obfuscation password already exists, skipping generation"
    fi

    # Save to state
    cat > "$STATE_DIR/keys/clash-api.env" <<EOF
CLASH_API_SECRET=$CLASH_API_SECRET
HYSTERIA2_OBFS_PASSWORD=$HYSTERIA2_OBFS_PASSWORD
EOF

    # Parse Reality target
    REALITY_TARGET_HOST=$(echo "${REALITY_TARGET:-dl.google.com:443}" | cut -d: -f1)
    REALITY_TARGET_PORT=$(echo "${REALITY_TARGET:-dl.google.com:443}" | cut -d: -f2)
else
    CLASH_API_SECRET=""
    HYSTERIA2_OBFS_PASSWORD=""
    REALITY_TARGET_HOST=""
    REALITY_TARGET_PORT=""
fi

# -----------------------------------------------------------------------------
# Export variables needed by generate-user.sh
# -----------------------------------------------------------------------------
export REALITY_PUBLIC_KEY
export REALITY_SHORT_ID
export REALITY_TARGET="${REALITY_TARGET:-dl.google.com:443}"
export HYSTERIA2_OBFS_PASSWORD
# In domain-less mode, DOMAIN stays empty; otherwise use as-is
export DOMAIN="${DOMAIN:-}"
export DNSTT_SUBDOMAIN="${DNSTT_SUBDOMAIN:-t}"
export ENABLE_REALITY="${ENABLE_REALITY:-true}"
export ENABLE_TROJAN="${ENABLE_TROJAN:-true}"
export ENABLE_HYSTERIA2="${ENABLE_HYSTERIA2:-true}"
export ENABLE_WIREGUARD="${ENABLE_WIREGUARD:-true}"
export ENABLE_AMNEZIAWG="${ENABLE_AMNEZIAWG:-true}"
export ENABLE_DNSTT="${ENABLE_DNSTT:-true}"
export ENABLE_TRUSTTUNNEL="${ENABLE_TRUSTTUNNEL:-true}"
# Construct CDN_DOMAIN from CDN_SUBDOMAIN + DOMAIN if not explicitly set
if [[ -z "${CDN_DOMAIN:-}" && -n "${CDN_SUBDOMAIN:-}" && -n "${DOMAIN:-}" ]]; then
    export CDN_DOMAIN="${CDN_SUBDOMAIN}.${DOMAIN}"
else
    export CDN_DOMAIN="${CDN_DOMAIN:-}"
fi
export CDN_WS_PATH="${CDN_WS_PATH:-/ws}"

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
# Generate AmneziaWG server config (before creating users)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_AMNEZIAWG:-true}" == "true" ]]; then
    log_info "Generating AmneziaWG server configuration..."
    generate_amneziawg_config

    # Verify keys are consistent
    if [[ -f "$STATE_DIR/keys/awg-server.key" ]] && [[ -f "/configs/amneziawg/server.pub" ]]; then
        DERIVED_PUB=$(cat "$STATE_DIR/keys/awg-server.key" | wg pubkey)
        SAVED_PUB=$(cat "/configs/amneziawg/server.pub")
        if [[ "$DERIVED_PUB" == "$SAVED_PUB" ]]; then
            log_info "AmneziaWG keys verified: public key matches private key"
        else
            log_error "AmneziaWG key mismatch! Fixing..."
            echo "$DERIVED_PUB" > "/configs/amneziawg/server.pub"
            echo "$DERIVED_PUB" > "$STATE_DIR/keys/awg-server.pub"
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
VLESS_WS_USERS_JSON="["
TRUSTTUNNEL_CREDENTIALS=""

for i in $(seq -w 1 "$INITIAL_USERS"); do
    # Use "demouser" for single user, otherwise "user01", "user02", etc.
    if [[ "$INITIAL_USERS" == "1" ]]; then
        USER_ID="demouser"
        export IS_DEMO_USER="true"
    else
        USER_ID="user$i"
        export IS_DEMO_USER="false"
    fi

    mkdir -p "$STATE_DIR/users/$USER_ID"

    # Load existing credentials if available, only generate if missing
    if [[ -f "$STATE_DIR/users/$USER_ID/credentials.env" ]]; then
        log_info "Loading existing credentials for user: $USER_ID"
        source "$STATE_DIR/users/$USER_ID/credentials.env"
    else
        USER_UUID=$(sing-box generate uuid)
        USER_PASSWORD=$(pwgen -s 24 1)
        log_info "Creating new user: $USER_ID"

        # Store user credentials
        cat > "$STATE_DIR/users/$USER_ID/credentials.env" <<EOF
USER_ID=$USER_ID
USER_UUID=$USER_UUID
USER_PASSWORD=$USER_PASSWORD
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    fi

    # Build JSON arrays for sing-box config
    [[ $i -gt 1 ]] && REALITY_USERS_JSON+=","
    [[ $i -gt 1 ]] && TROJAN_USERS_JSON+=","
    [[ $i -gt 1 ]] && HYSTERIA2_USERS_JSON+=","
    [[ $i -gt 1 ]] && VLESS_WS_USERS_JSON+=","

    REALITY_USERS_JSON+="{\"name\":\"$USER_ID\",\"uuid\":\"$USER_UUID\",\"flow\":\"xtls-rprx-vision\"}"
    TROJAN_USERS_JSON+="{\"name\":\"$USER_ID\",\"password\":\"$USER_PASSWORD\"}"
    HYSTERIA2_USERS_JSON+="{\"name\":\"$USER_ID\",\"password\":\"$USER_PASSWORD\"}"
    VLESS_WS_USERS_JSON+="{\"name\":\"$USER_ID\",\"uuid\":\"$USER_UUID\"}"

    # TrustTunnel credentials (TOML format - uses [[client]] not [[credentials]])
    TRUSTTUNNEL_CREDENTIALS+="[[client]]
username = \"$USER_ID\"
password = \"$USER_PASSWORD\"

"

    # Generate user bundle
    /app/generate-user.sh "$USER_ID"
done

# -----------------------------------------------------------------------------
# Re-add existing users that were created via 'moav user add' (not in INITIAL_USERS)
# On re-bootstrap, wg0.conf/awg0.conf are regenerated fresh with only INITIAL_USERS.
# This loop picks up any additional users from state and re-adds their peers + configs.
# -----------------------------------------------------------------------------
PROCESSED_USERS=""
# Build list of users already processed above
for i in $(seq -w 1 "$INITIAL_USERS"); do
    if [[ "$INITIAL_USERS" == "1" ]]; then
        PROCESSED_USERS="demouser"
    else
        PROCESSED_USERS="$PROCESSED_USERS user$i"
    fi
done

# Import users from host state dir (/host-state) into Docker volume (/state)
# Users created via 'moav user add' write to host ./state/ which is mounted as /host-state.
# The Docker volume /state only has users created by bootstrap. This step syncs them.
IMPORT_COUNT=0
if [[ -d "/host-state/users" ]]; then
    for host_user_dir in /host-state/users/*/; do
        [[ ! -d "$host_user_dir" ]] && continue
        IMPORT_USER_ID=$(basename "$host_user_dir")

        # Skip users already in Docker volume state
        if [[ -d "$STATE_DIR/users/$IMPORT_USER_ID" ]]; then
            continue
        fi

        # Skip users already processed in INITIAL_USERS loop
        if echo " $PROCESSED_USERS " | grep -q " $IMPORT_USER_ID "; then
            continue
        fi

        # Must have credentials to be a valid user
        if [[ ! -f "/host-state/users/$IMPORT_USER_ID/credentials.env" ]]; then
            continue
        fi

        log_info "Importing user from host state: $IMPORT_USER_ID"
        mkdir -p "$STATE_DIR/users/$IMPORT_USER_ID"
        cp -a "/host-state/users/$IMPORT_USER_ID/"* "$STATE_DIR/users/$IMPORT_USER_ID/" 2>/dev/null || true

        # Also import AWG credentials from output bundle if not already in state
        if [[ ! -f "$STATE_DIR/users/$IMPORT_USER_ID/amneziawg.env" ]] && \
           [[ -f "/outputs/bundles/$IMPORT_USER_ID/amneziawg.env" ]]; then
            cp "/outputs/bundles/$IMPORT_USER_ID/amneziawg.env" \
               "$STATE_DIR/users/$IMPORT_USER_ID/amneziawg.env"
        fi

        ((IMPORT_COUNT++)) || true
    done
fi

if [[ $IMPORT_COUNT -gt 0 ]]; then
    log_info "Imported $IMPORT_COUNT users from host state into Docker volume"
fi

EXTRA_USER_COUNT=0
for user_dir in "$STATE_DIR"/users/*/; do
    [[ ! -d "$user_dir" ]] && continue
    EXTRA_USER_ID=$(basename "$user_dir")

    # Skip users already processed in INITIAL_USERS loop
    if echo " $PROCESSED_USERS " | grep -q " $EXTRA_USER_ID "; then
        continue
    fi

    # Must have credentials to be a valid user
    if [[ ! -f "$STATE_DIR/users/$EXTRA_USER_ID/credentials.env" ]]; then
        continue
    fi

    log_info "Re-adding existing user: $EXTRA_USER_ID"
    source "$STATE_DIR/users/$EXTRA_USER_ID/credentials.env"

    # Add to sing-box JSON arrays (need comma separator)
    REALITY_USERS_JSON+=",{\"name\":\"$EXTRA_USER_ID\",\"uuid\":\"$USER_UUID\",\"flow\":\"xtls-rprx-vision\"}"
    TROJAN_USERS_JSON+=",{\"name\":\"$EXTRA_USER_ID\",\"password\":\"$USER_PASSWORD\"}"
    HYSTERIA2_USERS_JSON+=",{\"name\":\"$EXTRA_USER_ID\",\"password\":\"$USER_PASSWORD\"}"
    VLESS_WS_USERS_JSON+=",{\"name\":\"$EXTRA_USER_ID\",\"uuid\":\"$USER_UUID\"}"

    TRUSTTUNNEL_CREDENTIALS+="[[client]]
username = \"$EXTRA_USER_ID\"
password = \"$USER_PASSWORD\"

"

    # Regenerate user bundle (adds WG/AWG peers via guards + generates configs)
    export USER_ID="$EXTRA_USER_ID"
    export IS_DEMO_USER="false"
    /app/generate-user.sh "$EXTRA_USER_ID"

    ((EXTRA_USER_COUNT++)) || true
done

if [[ $EXTRA_USER_COUNT -gt 0 ]]; then
    log_info "Re-added $EXTRA_USER_COUNT existing users from previous sessions"
fi

REALITY_USERS_JSON+="]"
TROJAN_USERS_JSON+="]"
HYSTERIA2_USERS_JSON+="]"
VLESS_WS_USERS_JSON+="]"

# -----------------------------------------------------------------------------
# Generate TrustTunnel config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_TRUSTTUNNEL:-true}" == "true" ]]; then
    log_info "Generating TrustTunnel configuration..."

    export TRUSTTUNNEL_CREDENTIALS

    # Generate credentials.toml
    envsubst < /configs/trusttunnel/credentials.toml.template > /configs/trusttunnel/credentials.toml

    # Generate hosts.toml
    envsubst < /configs/trusttunnel/hosts.toml.template > /configs/trusttunnel/hosts.toml

    # Generate vpn.toml (no substitution needed but copy for consistency)
    envsubst < /configs/trusttunnel/vpn.toml.template > /configs/trusttunnel/vpn.toml

    log_info "TrustTunnel configuration written to /configs/trusttunnel/"
fi

# -----------------------------------------------------------------------------
# Generate sing-box config (only if TLS protocols are enabled)
# -----------------------------------------------------------------------------
singbox_needed=false
[[ "${ENABLE_REALITY:-true}" == "true" ]] && singbox_needed=true
[[ "${ENABLE_TROJAN:-true}" == "true" ]] && singbox_needed=true
[[ "${ENABLE_HYSTERIA2:-true}" == "true" ]] && singbox_needed=true

if [[ "$singbox_needed" == "true" ]]; then
    log_info "Generating sing-box configuration..."

    export REALITY_USERS_JSON
    export TROJAN_USERS_JSON
    export HYSTERIA2_USERS_JSON
    export VLESS_WS_USERS_JSON
    export REALITY_PRIVATE_KEY
    export REALITY_SHORT_ID
    export REALITY_TARGET_HOST
    export REALITY_TARGET_PORT
    export REALITY_SERVER_NAME="$REALITY_TARGET_HOST"
    export CLASH_API_SECRET
    export HYSTERIA2_OBFS_PASSWORD
    export CDN_WS_PATH="${CDN_WS_PATH:-/ws}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"

    envsubst < /configs/sing-box/config.json.template > /configs/sing-box/config.json

    log_info "sing-box configuration written to /configs/sing-box/config.json"
else
    log_info "sing-box not needed (no TLS protocols enabled)"
fi

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
