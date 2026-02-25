#!/bin/bash
set -euo pipefail

# =============================================================================
# Add a new user to sing-box (Reality, Trojan, Hysteria2)
# Usage: ./scripts/singbox-user-add.sh <username> [--no-reload]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

source scripts/lib/common.sh

# Parse arguments
USERNAME=""
NO_RELOAD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-reload)
            NO_RELOAD=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            USERNAME="$1"
            shift
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username> [--no-reload]"
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

# Generate ShadowTLS + SS2022 per-user credentials
SHADOWTLS_PASSWORD=$(openssl rand -hex 16)
SS_USER_KEY=$(openssl rand -base64 16)

# Save credentials
cat > "$STATE_DIR/users/$USERNAME/credentials.env" <<EOF
USER_ID=$USERNAME
USER_UUID=$USER_UUID
USER_PASSWORD=$USER_PASSWORD
SHADOWTLS_PASSWORD=$SHADOWTLS_PASSWORD
SS_USER_KEY=$SS_USER_KEY
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

# Add to VLESS WS users (CDN)
jq --arg name "$USERNAME" --arg uuid "$USER_UUID" \
    '.inbounds |= map(if .tag == "vless-ws-in" then .users += [{"name": $name, "uuid": $uuid}] else . end)' \
    "$TEMP_CONFIG" > "${TEMP_CONFIG}.2"
mv "${TEMP_CONFIG}.2" "$TEMP_CONFIG"

# Add to TUIC users
jq --arg name "$USERNAME" --arg uuid "$USER_UUID" --arg pass "$USER_PASSWORD" \
    '.inbounds |= map(if .tag == "tuic-in" then .users += [{"name": $name, "uuid": $uuid, "password": $pass}] else . end)' \
    "$TEMP_CONFIG" > "${TEMP_CONFIG}.2"
mv "${TEMP_CONFIG}.2" "$TEMP_CONFIG"

# Add to VMess-WS users
jq --arg name "$USERNAME" --arg uuid "$USER_UUID" \
    '.inbounds |= map(if .tag == "vmess-ws-in" then .users += [{"name": $name, "uuid": $uuid}] else . end)' \
    "$TEMP_CONFIG" > "${TEMP_CONFIG}.2"
mv "${TEMP_CONFIG}.2" "$TEMP_CONFIG"

# Add to ShadowTLS users
jq --arg name "$USERNAME" --arg pass "$SHADOWTLS_PASSWORD" \
    '.inbounds |= map(if .tag == "shadowtls-in" then .users += [{"name": $name, "password": $pass}] else . end)' \
    "$TEMP_CONFIG" > "${TEMP_CONFIG}.2"
mv "${TEMP_CONFIG}.2" "$TEMP_CONFIG"

# Add to Shadowsocks users
jq --arg name "$USERNAME" --arg pass "$SS_USER_KEY" \
    '.inbounds |= map(if .tag == "shadowsocks-in" then .users += [{"name": $name, "password": $pass}] else . end)' \
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
    # Try docker volume (load all keys including private for derivation fallback)
    REALITY_ENV_CONTENT=$(docker run --rm -v moav_moav_state:/state alpine cat /state/keys/reality.env 2>/dev/null || echo "")
    REALITY_PRIVATE_KEY=$(echo "$REALITY_ENV_CONTENT" | grep REALITY_PRIVATE_KEY | cut -d= -f2)
    REALITY_PUBLIC_KEY=$(echo "$REALITY_ENV_CONTENT" | grep REALITY_PUBLIC_KEY | cut -d= -f2)
    REALITY_SHORT_ID=$(echo "$REALITY_ENV_CONTENT" | grep REALITY_SHORT_ID | cut -d= -f2)
fi

# If public key is missing but private key exists, derive it
if [[ -z "${REALITY_PUBLIC_KEY:-}" ]] && [[ -n "${REALITY_PRIVATE_KEY:-}" ]]; then
    log_info "Reality public key missing, deriving from private key..."
    # x25519 uses the same curve as WireGuard — convert base64url→base64, use wg pubkey, convert back
    REALITY_KEY_B64=$(echo "${REALITY_PRIVATE_KEY}==" | tr '_-' '/+' | head -c 44)
    if docker compose ps wireguard --status running &>/dev/null; then
        REALITY_PUBLIC_KEY=$(echo "$REALITY_KEY_B64" | docker compose exec -T wireguard wg pubkey 2>/dev/null | tr '/+' '_-' | sed 's/=*$//' || echo "")
    elif command -v wg &>/dev/null; then
        REALITY_PUBLIC_KEY=$(echo "$REALITY_KEY_B64" | wg pubkey 2>/dev/null | tr '/+' '_-' | sed 's/=*$//' || echo "")
    fi
    if [[ -n "$REALITY_PUBLIC_KEY" ]]; then
        log_info "Derived Reality public key: ${REALITY_PUBLIC_KEY:0:10}..."
        # Save it back so future runs don't need to derive again
        if [[ -f "$STATE_DIR/keys/reality.env" ]]; then
            sed -i "s/^REALITY_PUBLIC_KEY=.*/REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY/" "$STATE_DIR/keys/reality.env"
        fi
        # Also update Docker volume
        docker run --rm -v moav_moav_state:/state alpine sh -c \
            "sed -i 's/^REALITY_PUBLIC_KEY=.*/REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY/' /state/keys/reality.env" 2>/dev/null || true
    else
        log_warn "Could not derive Reality public key - Reality links will be incomplete"
    fi
fi

# Load Hysteria2 obfuscation password
if [[ -f "$STATE_DIR/keys/clash-api.env" ]]; then
    source "$STATE_DIR/keys/clash-api.env"
else
    # Try docker volume
    HYSTERIA2_OBFS_PASSWORD=$(docker run --rm -v moav_moav_state:/state alpine cat /state/keys/clash-api.env 2>/dev/null | grep HYSTERIA2_OBFS_PASSWORD | cut -d= -f2 || echo "")
fi

# Get server IP
SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org || echo "YOUR_SERVER_IP")}"

# Get server IPv6 if available
if [[ -z "${SERVER_IPV6:-}" ]] && [[ "${SERVER_IPV6:-}" != "disabled" ]]; then
    SERVER_IPV6=$(curl -6 -s --max-time 3 https://api6.ipify.org 2>/dev/null || echo "")
fi
[[ "${SERVER_IPV6:-}" == "disabled" ]] && SERVER_IPV6=""

# Parse Reality target
REALITY_TARGET="${REALITY_TARGET:-dl.google.com:443}"
REALITY_TARGET_HOST=$(echo "$REALITY_TARGET" | cut -d: -f1)

# -----------------------------------------------------------------------------
# Generate client configs
# -----------------------------------------------------------------------------

# Reality link (IPv4)
REALITY_LINK="vless://${USER_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET_HOST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#MoaV-Reality-${USERNAME}"
echo "$REALITY_LINK" > "$OUTPUT_DIR/reality.txt"

# Trojan link (IPv4)
TROJAN_LINK="trojan://${USER_PASSWORD}@${SERVER_IP}:8443?security=tls&sni=${DOMAIN}&type=tcp#MoaV-Trojan-${USERNAME}"
echo "$TROJAN_LINK" > "$OUTPUT_DIR/trojan.txt"

# Hysteria2 link (IPv4) - with obfuscation for censorship bypass
HY2_LINK="hysteria2://${USER_PASSWORD}@${SERVER_IP}:443?sni=${DOMAIN}&obfs=salamander&obfs-password=${HYSTERIA2_OBFS_PASSWORD}#MoaV-Hysteria2-${USERNAME}"
echo "$HY2_LINK" > "$OUTPUT_DIR/hysteria2.txt"

# Generate IPv6 links if available
if [[ -n "$SERVER_IPV6" ]]; then
    REALITY_LINK_V6="vless://${USER_UUID}@[${SERVER_IPV6}]:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET_HOST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#MoaV-Reality-${USERNAME}-IPv6"
    echo "$REALITY_LINK_V6" > "$OUTPUT_DIR/reality-ipv6.txt"

    TROJAN_LINK_V6="trojan://${USER_PASSWORD}@[${SERVER_IPV6}]:8443?security=tls&sni=${DOMAIN}&type=tcp#MoaV-Trojan-${USERNAME}-IPv6"
    echo "$TROJAN_LINK_V6" > "$OUTPUT_DIR/trojan-ipv6.txt"

    HY2_LINK_V6="hysteria2://${USER_PASSWORD}@[${SERVER_IPV6}]:443?sni=${DOMAIN}&obfs=salamander&obfs-password=${HYSTERIA2_OBFS_PASSWORD}#MoaV-Hysteria2-${USERNAME}-IPv6"
    echo "$HY2_LINK_V6" > "$OUTPUT_DIR/hysteria2-ipv6.txt"

    log_info "Generated IPv6 links (server: $SERVER_IPV6)"
fi

# Generate QR codes
if command -v qrencode &>/dev/null; then
    qrencode -o "$OUTPUT_DIR/reality-qr.png" -s 6 "$REALITY_LINK" 2>/dev/null || true
    qrencode -o "$OUTPUT_DIR/trojan-qr.png" -s 6 "$TROJAN_LINK" 2>/dev/null || true
    qrencode -o "$OUTPUT_DIR/hysteria2-qr.png" -s 6 "$HY2_LINK" 2>/dev/null || true

    # IPv6 QR codes
    if [[ -n "$SERVER_IPV6" ]]; then
        qrencode -o "$OUTPUT_DIR/reality-ipv6-qr.png" -s 6 "$REALITY_LINK_V6" 2>/dev/null || true
        qrencode -o "$OUTPUT_DIR/trojan-ipv6-qr.png" -s 6 "$TROJAN_LINK_V6" 2>/dev/null || true
        qrencode -o "$OUTPUT_DIR/hysteria2-ipv6-qr.png" -s 6 "$HY2_LINK_V6" 2>/dev/null || true
    fi
fi

# Generate CDN VLESS+WS link (if CDN configured)
# Construct CDN_DOMAIN from CDN_SUBDOMAIN + DOMAIN if not explicitly set
CDN_DOMAIN="${CDN_DOMAIN:-$(grep -E '^CDN_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")}"
if [[ -z "$CDN_DOMAIN" ]]; then
    CDN_SUBDOMAIN="${CDN_SUBDOMAIN:-$(grep -E '^CDN_SUBDOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")}"
    DOMAIN_FROM_ENV="${DOMAIN:-$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")}"
    if [[ -n "$CDN_SUBDOMAIN" && -n "$DOMAIN_FROM_ENV" ]]; then
        CDN_DOMAIN="${CDN_SUBDOMAIN}.${DOMAIN_FROM_ENV}"
    fi
fi
CDN_WS_PATH="${CDN_WS_PATH:-$(grep -E '^CDN_WS_PATH=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "/ws")}"
CDN_WS_PATH="${CDN_WS_PATH:-/ws}"

if [[ -n "$CDN_DOMAIN" ]]; then
    CDN_LINK="vless://${USER_UUID}@${CDN_DOMAIN}:443?security=tls&type=ws&path=${CDN_WS_PATH}&sni=${CDN_DOMAIN}&host=${CDN_DOMAIN}&fp=chrome&alpn=http/1.1#MoaV-CDN-${USERNAME}"
    echo "$CDN_LINK" > "$OUTPUT_DIR/cdn-vless-ws.txt"

    if command -v qrencode &>/dev/null; then
        qrencode -o "$OUTPUT_DIR/cdn-vless-ws-qr.png" -s 6 "$CDN_LINK" 2>/dev/null || true
    fi

    log_info "Generated CDN VLESS+WS link (domain: $CDN_DOMAIN)"
fi

# Generate TUIC link (if TUIC inbound exists in config)
if jq -e '.inbounds[] | select(.tag == "tuic-in")' "$CONFIG_FILE" &>/dev/null; then
    TUIC_LINK="tuic://${USER_UUID}:${USER_PASSWORD}@${SERVER_IP}:${PORT_TUIC:-8444}?congestion_control=bbr&alpn=h3&sni=${DOMAIN}&udp_relay_mode=native#MoaV-TUIC-${USERNAME}"
    echo "$TUIC_LINK" > "$OUTPUT_DIR/tuic.txt"

    # Generate IPv6 link if available
    if [[ -n "$SERVER_IPV6" ]]; then
        TUIC_LINK_V6="tuic://${USER_UUID}:${USER_PASSWORD}@[${SERVER_IPV6}]:${PORT_TUIC:-8444}?congestion_control=bbr&alpn=h3&sni=${DOMAIN}&udp_relay_mode=native#MoaV-TUIC-${USERNAME}-IPv6"
        echo "$TUIC_LINK_V6" > "$OUTPUT_DIR/tuic-ipv6.txt"
    fi

    if command -v qrencode &>/dev/null; then
        qrencode -o "$OUTPUT_DIR/tuic-qr.png" -s 6 "$TUIC_LINK" 2>/dev/null || true
        if [[ -n "$SERVER_IPV6" ]]; then
            qrencode -o "$OUTPUT_DIR/tuic-ipv6-qr.png" -s 6 "$TUIC_LINK_V6" 2>/dev/null || true
        fi
    fi

    log_info "Generated TUIC link"
fi

# Generate VMess+WS link (if VMess inbound exists in config)
if jq -e '.inbounds[] | select(.tag == "vmess-ws-in")' "$CONFIG_FILE" &>/dev/null; then
    VMESS_WS_PATH=$(jq -r '.inbounds[] | select(.tag == "vmess-ws-in") | .transport.path' "$CONFIG_FILE")
    VMESS_PORT=$(jq -r '.inbounds[] | select(.tag == "vmess-ws-in") | .listen_port' "$CONFIG_FILE")

    # VMess URI uses base64-encoded JSON
    VMESS_JSON="{\"v\":\"2\",\"ps\":\"MoaV-VMess-WS-${USERNAME}\",\"add\":\"${SERVER_IP}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${VMESS_WS_PATH}\",\"tls\":\"\"}"
    VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    echo "$VMESS_LINK" > "$OUTPUT_DIR/vmess-ws.txt"

    # CDN variant (if CDN domain is configured)
    if [[ -n "${CDN_DOMAIN:-}" ]]; then
        VMESS_CDN_JSON="{\"v\":\"2\",\"ps\":\"MoaV-VMess-CDN-${USERNAME}\",\"add\":\"${CDN_DOMAIN}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${CDN_DOMAIN}\",\"path\":\"${VMESS_WS_PATH}\",\"tls\":\"\"}"
        VMESS_CDN_LINK="vmess://$(echo -n "$VMESS_CDN_JSON" | base64 -w 0)"
        echo "$VMESS_CDN_LINK" > "$OUTPUT_DIR/vmess-cdn.txt"
    fi

    # IPv6 variant
    if [[ -n "$SERVER_IPV6" ]]; then
        VMESS_V6_JSON="{\"v\":\"2\",\"ps\":\"MoaV-VMess-WS-${USERNAME}-IPv6\",\"add\":\"${SERVER_IPV6}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${VMESS_WS_PATH}\",\"tls\":\"\"}"
        VMESS_V6_LINK="vmess://$(echo -n "$VMESS_V6_JSON" | base64 -w 0)"
        echo "$VMESS_V6_LINK" > "$OUTPUT_DIR/vmess-ws-ipv6.txt"
    fi

    # Generate QR codes
    if command -v qrencode &>/dev/null; then
        qrencode -o "$OUTPUT_DIR/vmess-ws-qr.png" -s 6 "$VMESS_LINK" 2>/dev/null || true
    fi

    log_info "Generated VMess+WS link"
fi

# Generate ShadowTLS + SS2022 config (if ShadowTLS inbound exists in config)
if jq -e '.inbounds[] | select(.tag == "shadowtls-in")' "$CONFIG_FILE" &>/dev/null; then
    # Load SS server password
    SS_SERVER_PASSWORD=""
    if [[ -f "$STATE_DIR/keys/shadowsocks.env" ]]; then
        source "$STATE_DIR/keys/shadowsocks.env"
    else
        SS_SERVER_PASSWORD=$(docker run --rm -v moav_moav_state:/state alpine cat /state/keys/shadowsocks.env 2>/dev/null | grep SS_SERVER_PASSWORD | cut -d= -f2 || echo "")
    fi

    if [[ -n "$SS_SERVER_PASSWORD" ]]; then
        # Generate sing-box client config (ShadowTLS + SS2022 requires chained outbounds)
        cat > "$OUTPUT_DIR/shadowtls-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "proxy",
      "detour": "shadowtls-out",
      "method": "2022-blake3-aes-128-gcm",
      "password": "${SS_SERVER_PASSWORD}:${SS_USER_KEY}",
      "multiplex": {
        "enabled": true,
        "padding": true
      }
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-out",
      "server": "${SERVER_IP}",
      "server_port": ${PORT_SHADOWTLS:-8445},
      "version": 3,
      "password": "${SHADOWTLS_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com"
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

        # Generate human-readable text config
        cat > "$OUTPUT_DIR/shadowtls.txt" <<EOF
ShadowTLS v3 + Shadowsocks 2022
================================
Server: ${SERVER_IP}
Port: ${PORT_SHADOWTLS:-8445}
ShadowTLS Password: ${SHADOWTLS_PASSWORD}
SS Method: 2022-blake3-aes-128-gcm
SS Server Key: ${SS_SERVER_PASSWORD}
SS User Key: ${SS_USER_KEY}
Handshake Server: www.microsoft.com
EOF

        # Generate QR code from sing-box JSON config (minified)
        if command -v qrencode &>/dev/null; then
            jq -c . "$OUTPUT_DIR/shadowtls-singbox.json" | qrencode -o "$OUTPUT_DIR/shadowtls-qr.png" -s 6 2>/dev/null || true
        fi

        # IPv6 variant
        if [[ -n "$SERVER_IPV6" ]]; then
            cat > "$OUTPUT_DIR/shadowtls-ipv6.txt" <<EOF
ShadowTLS v3 + Shadowsocks 2022 (IPv6)
========================================
Server: ${SERVER_IPV6}
Port: ${PORT_SHADOWTLS:-8445}
ShadowTLS Password: ${SHADOWTLS_PASSWORD}
SS Method: 2022-blake3-aes-128-gcm
SS Server Key: ${SS_SERVER_PASSWORD}
SS User Key: ${SS_USER_KEY}
Handshake Server: www.microsoft.com
EOF
        fi

        log_info "Generated ShadowTLS + SS2022 config"
    else
        log_warn "SS server password not found, skipping ShadowTLS config"
    fi
fi

# Add user to TrustTunnel (if config exists)
TRUSTTUNNEL_CREDS="configs/trusttunnel/credentials.toml"
if [[ -f "$TRUSTTUNNEL_CREDS" ]]; then
    log_info "Adding $USERNAME to TrustTunnel..."

    # Check if user already exists in TrustTunnel
    if grep -q "username = \"$USERNAME\"" "$TRUSTTUNNEL_CREDS" 2>/dev/null; then
        log_info "User '$USERNAME' already exists in TrustTunnel, skipping..."
    else
        # Append new user to credentials.toml
        cat >> "$TRUSTTUNNEL_CREDS" <<EOF

[[client]]
username = "$USERNAME"
password = "$USER_PASSWORD"
EOF
        log_info "Added $USERNAME to TrustTunnel credentials"
    fi

    # Get server IP if not set
    if [[ -z "${SERVER_IP:-}" ]]; then
        SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    fi

    # Generate full TOML config for CLI client
    cat > "$OUTPUT_DIR/trusttunnel.toml" <<EOF
# TrustTunnel Client Configuration for $USERNAME
# Generated by MoaV

loglevel = "info"
vpn_mode = "general"
killswitch_enabled = false
killswitch_allow_ports = []
post_quantum_group_enabled = true
exclusions = []
dns_upstreams = ["tls://1.1.1.1", "tls://8.8.8.8"]

[endpoint]
hostname = "${DOMAIN}"
addresses = ["${SERVER_IP}:4443"]
has_ipv6 = false
username = "${USERNAME}"
password = "${USER_PASSWORD}"
client_random = ""
skip_verification = false
certificate = ""
upstream_protocol = "http2"
upstream_fallback_protocol = "http3"
anti_dpi = false

[listener.tun]
bound_if = ""
included_routes = ["0.0.0.0/0", "2000::/3"]
excluded_routes = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
mtu_size = 1280
EOF

    # Generate human-readable text file
    cat > "$OUTPUT_DIR/trusttunnel.txt" <<EOF
TrustTunnel Configuration for $USERNAME
======================================

IP Address: ${SERVER_IP}:4443
Domain: ${DOMAIN}
Username: ${USERNAME}
Password: ${USER_PASSWORD}
DNS Servers: tls://1.1.1.1

CLI Client:
-----------
1. Download from: https://github.com/TrustTunnel/TrustTunnelClient/releases
2. Run: trusttunnel_client trusttunnel.toml

Mobile/Desktop App:
-------------------
1. Download TrustTunnel from app store or https://trusttunnel.org/
2. Add new VPN with the settings above
3. Connect

Note: TrustTunnel supports HTTP/2 and HTTP/3 (QUIC) transports,
which look like regular HTTPS traffic to network observers.
EOF

    cat > "$OUTPUT_DIR/trusttunnel.json" <<EOF
{
  "ip_address": "${SERVER_IP}:4443",
  "domain": "${DOMAIN}",
  "username": "${USERNAME}",
  "password": "${USER_PASSWORD}",
  "dns_servers": ["tls://1.1.1.1", "tls://8.8.8.8"]
}
EOF

    log_info "Generated TrustTunnel client config (toml + txt + json)"
fi

# Try to reload sing-box (hot reload) unless --no-reload was passed
if [[ "$NO_RELOAD" != "true" ]]; then
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

    # Try to reload TrustTunnel (if running)
    if [[ -f "$TRUSTTUNNEL_CREDS" ]]; then
        if docker compose ps trusttunnel --status running &>/dev/null; then
            log_info "Restarting TrustTunnel to apply new credentials..."
            docker compose restart trusttunnel
        fi
    fi
fi

echo ""
log_info "=== User '$USERNAME' created ==="
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

if [[ -n "${SERVER_IPV6:-}" ]]; then
    echo "=== IPv6 Links ==="
    echo ""
    echo "Reality (IPv6):"
    echo "$REALITY_LINK_V6"
    echo ""
    echo "Trojan (IPv6):"
    echo "$TROJAN_LINK_V6"
    echo ""
    echo "Hysteria2 (IPv6):"
    echo "$HY2_LINK_V6"
    echo ""
fi

if [[ -n "${CDN_DOMAIN:-}" ]]; then
    echo "CDN VLESS+WS Link:"
    echo "$CDN_LINK"
    echo ""
fi

if [[ -f "$OUTPUT_DIR/tuic.txt" ]]; then
    echo "TUIC Link:"
    cat "$OUTPUT_DIR/tuic.txt"
    echo ""
fi

if [[ -f "$OUTPUT_DIR/vmess-ws.txt" ]]; then
    echo "VMess+WS Link:"
    cat "$OUTPUT_DIR/vmess-ws.txt"
    echo ""
fi

if [[ -f "$OUTPUT_DIR/vmess-cdn.txt" ]]; then
    echo "VMess CDN Link:"
    cat "$OUTPUT_DIR/vmess-cdn.txt"
    echo ""
fi

if [[ -f "$OUTPUT_DIR/shadowtls.txt" ]]; then
    echo "ShadowTLS + SS2022:"
    cat "$OUTPUT_DIR/shadowtls.txt"
    echo ""
fi

if [[ -f "$TRUSTTUNNEL_CREDS" ]]; then
    echo "TrustTunnel:"
    echo "  IP Address: ${SERVER_IP}:4443"
    echo "  Domain: ${DOMAIN}"
    echo "  Username: ${USERNAME}"
    echo "  Password: ${USER_PASSWORD}"
    echo "  DNS Servers: tls://1.1.1.1"
    echo ""
fi

log_info "Config files saved to: $OUTPUT_DIR/"
