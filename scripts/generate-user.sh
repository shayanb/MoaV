#!/bin/bash
set -euo pipefail

# =============================================================================
# Generate user bundle with all client configurations
# Usage: generate-user.sh <user_id>
# =============================================================================

source /app/lib/common.sh
source /app/lib/wireguard.sh
source /app/lib/amneziawg.sh
source /app/lib/dnstt.sh

# Default state directory if not set
STATE_DIR="${STATE_DIR:-/state}"

USER_ID="${1:-}"

if [[ -z "$USER_ID" ]]; then
    log_error "Usage: generate-user.sh <user_id>"
    exit 1
fi

# Load user credentials
USER_CREDS_FILE="$STATE_DIR/users/$USER_ID/credentials.env"
if [[ ! -f "$USER_CREDS_FILE" ]]; then
    log_error "User credentials not found: $USER_CREDS_FILE"
    exit 1
fi

source "$USER_CREDS_FILE"

# Load Reality keys (only if Reality is enabled)
if [[ "${ENABLE_REALITY:-true}" == "true" ]] && [[ -f "$STATE_DIR/keys/reality.env" ]]; then
    source "$STATE_DIR/keys/reality.env"
fi

# Load Hysteria2 obfuscation password
if [[ "${ENABLE_HYSTERIA2:-true}" == "true" ]] && [[ -f "$STATE_DIR/keys/clash-api.env" ]]; then
    source "$STATE_DIR/keys/clash-api.env"
fi

# Create output directory
OUTPUT_DIR="/outputs/bundles/$USER_ID"
ensure_dir "$OUTPUT_DIR"

# Parse Reality target (only if Reality is enabled)
if [[ "${ENABLE_REALITY:-true}" == "true" ]]; then
    REALITY_TARGET_HOST=$(echo "${REALITY_TARGET:-dl.google.com:443}" | cut -d: -f1)
    REALITY_TARGET_PORT=$(echo "${REALITY_TARGET:-dl.google.com:443}" | cut -d: -f2)
fi

log_info "Generating bundle for $USER_ID..."

# -----------------------------------------------------------------------------
# Generate Reality (VLESS) client config (sing-box 1.12+ format)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_REALITY:-true}" == "true" ]]; then
    cat > "$OUTPUT_DIR/reality-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": 443,
      "uuid": "${USER_UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_TARGET_HOST}",
        "utls": {"enabled": true, "fingerprint": "chrome"},
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUBLIC_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    # Generate v2rayN/NekoBox compatible link (IPv4)
    REALITY_LINK="vless://${USER_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET_HOST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#MoaV-Reality-${USER_ID}"
    echo "$REALITY_LINK" > "$OUTPUT_DIR/reality.txt"

    # Generate QR code
    qrencode -o "$OUTPUT_DIR/reality-qr.png" -s 6 "$REALITY_LINK" 2>/dev/null || true

    # Generate IPv6 link if available
    if [[ -n "${SERVER_IPV6:-}" ]]; then
        REALITY_LINK_V6="vless://${USER_UUID}@[${SERVER_IPV6}]:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET_HOST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#MoaV-Reality-${USER_ID}-IPv6"
        echo "$REALITY_LINK_V6" > "$OUTPUT_DIR/reality-ipv6.txt"
        qrencode -o "$OUTPUT_DIR/reality-ipv6-qr.png" -s 6 "$REALITY_LINK_V6" 2>/dev/null || true
    fi

    log_info "  - Reality config generated"
fi

# -----------------------------------------------------------------------------
# Generate Trojan client config (sing-box 1.12+ format)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_TROJAN:-true}" == "true" ]]; then
    cat > "$OUTPUT_DIR/trojan-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "trojan",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": 8443,
      "password": "${USER_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "utls": {"enabled": true, "fingerprint": "chrome"}
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    # Generate Trojan URI (IPv4)
    TROJAN_LINK="trojan://${USER_PASSWORD}@${SERVER_IP}:8443?security=tls&sni=${DOMAIN}&type=tcp#MoaV-Trojan-${USER_ID}"
    echo "$TROJAN_LINK" > "$OUTPUT_DIR/trojan.txt"
    qrencode -o "$OUTPUT_DIR/trojan-qr.png" -s 6 "$TROJAN_LINK" 2>/dev/null || true

    # Generate IPv6 link if available
    if [[ -n "${SERVER_IPV6:-}" ]]; then
        TROJAN_LINK_V6="trojan://${USER_PASSWORD}@[${SERVER_IPV6}]:8443?security=tls&sni=${DOMAIN}&type=tcp#MoaV-Trojan-${USER_ID}-IPv6"
        echo "$TROJAN_LINK_V6" > "$OUTPUT_DIR/trojan-ipv6.txt"
        qrencode -o "$OUTPUT_DIR/trojan-ipv6-qr.png" -s 6 "$TROJAN_LINK_V6" 2>/dev/null || true
    fi

    log_info "  - Trojan config generated"
fi

# -----------------------------------------------------------------------------
# Generate Hysteria2 client config
# -----------------------------------------------------------------------------
if [[ "${ENABLE_HYSTERIA2:-true}" == "true" ]]; then
    cat > "$OUTPUT_DIR/hysteria2.yaml" <<EOF
server: ${SERVER_IP}:443
auth: ${USER_PASSWORD}

obfs:
  type: salamander
  salamander:
    password: ${HYSTERIA2_OBFS_PASSWORD}

tls:
  sni: ${DOMAIN}

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
EOF

    cat > "$OUTPUT_DIR/hysteria2-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": 443,
      "password": "${USER_PASSWORD}",
      "obfs": {
        "type": "salamander",
        "password": "${HYSTERIA2_OBFS_PASSWORD}"
      },
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}"
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    # Hysteria2 URI (IPv4) - includes obfs parameter
    HY2_LINK="hysteria2://${USER_PASSWORD}@${SERVER_IP}:443?sni=${DOMAIN}&obfs=salamander&obfs-password=${HYSTERIA2_OBFS_PASSWORD}#MoaV-Hysteria2-${USER_ID}"
    echo "$HY2_LINK" > "$OUTPUT_DIR/hysteria2.txt"
    qrencode -o "$OUTPUT_DIR/hysteria2-qr.png" -s 6 "$HY2_LINK" 2>/dev/null || true

    # Generate IPv6 link if available
    if [[ -n "${SERVER_IPV6:-}" ]]; then
        HY2_LINK_V6="hysteria2://${USER_PASSWORD}@[${SERVER_IPV6}]:443?sni=${DOMAIN}&obfs=salamander&obfs-password=${HYSTERIA2_OBFS_PASSWORD}#MoaV-Hysteria2-${USER_ID}-IPv6"
        echo "$HY2_LINK_V6" > "$OUTPUT_DIR/hysteria2-ipv6.txt"
        qrencode -o "$OUTPUT_DIR/hysteria2-ipv6-qr.png" -s 6 "$HY2_LINK_V6" 2>/dev/null || true
    fi

    log_info "  - Hysteria2 config generated (with obfuscation)"
fi

# -----------------------------------------------------------------------------
# Generate CDN VLESS+WS client config (if CDN_DOMAIN is set)
# -----------------------------------------------------------------------------
if [[ -n "${CDN_DOMAIN:-}" ]]; then
    CDN_WS_PATH="${CDN_WS_PATH:-/ws}"

    cat > "$OUTPUT_DIR/cdn-vless-ws-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${CDN_DOMAIN}",
      "server_port": 443,
      "uuid": "${USER_UUID}",
      "tls": {
        "enabled": true,
        "server_name": "${CDN_DOMAIN}",
        "utls": {"enabled": true, "fingerprint": "chrome"},
        "alpn": ["http/1.1"]
      },
      "transport": {
        "type": "ws",
        "path": "${CDN_WS_PATH}",
        "headers": {"Host": "${CDN_DOMAIN}"}
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    CDN_LINK="vless://${USER_UUID}@${CDN_DOMAIN}:443?security=tls&type=ws&path=${CDN_WS_PATH}&sni=${CDN_DOMAIN}&host=${CDN_DOMAIN}&fp=chrome&alpn=http/1.1#MoaV-CDN-${USER_ID}"
    echo "$CDN_LINK" > "$OUTPUT_DIR/cdn-vless-ws.txt"
    qrencode -o "$OUTPUT_DIR/cdn-vless-ws-qr.png" -s 6 "$CDN_LINK" 2>/dev/null || true

    log_info "  - CDN VLESS+WS config generated (domain: $CDN_DOMAIN)"
fi

# -----------------------------------------------------------------------------
# Generate TUIC client config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_TUIC:-true}" == "true" ]]; then
    cat > "$OUTPUT_DIR/tuic-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "tuic",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${PORT_TUIC:-8444},
      "uuid": "${USER_UUID}",
      "password": "${USER_PASSWORD}",
      "congestion_control": "bbr",
      "udp_relay_mode": "native",
      "zero_rtt_handshake": false,
      "heartbeat": "10s",
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "alpn": ["h3"]
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    # TUIC URI (IPv4)
    TUIC_LINK="tuic://${USER_UUID}:${USER_PASSWORD}@${SERVER_IP}:${PORT_TUIC:-8444}?congestion_control=bbr&alpn=h3&sni=${DOMAIN}&udp_relay_mode=native#MoaV-TUIC-${USER_ID}"
    echo "$TUIC_LINK" > "$OUTPUT_DIR/tuic.txt"
    qrencode -o "$OUTPUT_DIR/tuic-qr.png" -s 6 "$TUIC_LINK" 2>/dev/null || true

    # Generate IPv6 link if available
    if [[ -n "${SERVER_IPV6:-}" ]]; then
        TUIC_LINK_V6="tuic://${USER_UUID}:${USER_PASSWORD}@[${SERVER_IPV6}]:${PORT_TUIC:-8444}?congestion_control=bbr&alpn=h3&sni=${DOMAIN}&udp_relay_mode=native#MoaV-TUIC-${USER_ID}-IPv6"
        echo "$TUIC_LINK_V6" > "$OUTPUT_DIR/tuic-ipv6.txt"
        qrencode -o "$OUTPUT_DIR/tuic-ipv6-qr.png" -s 6 "$TUIC_LINK_V6" 2>/dev/null || true
    fi

    log_info "  - TUIC config generated"
fi

# -----------------------------------------------------------------------------
# Generate VMess+WS client config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_VMESS:-true}" == "true" ]]; then
    VMESS_WS_PATH="${CDN_VMESS_WS_PATH:-/vmws}"
    VMESS_PORT="${PORT_VMESS_WS:-2086}"

    cat > "$OUTPUT_DIR/vmess-ws-singbox.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true}
  ],
  "outbounds": [
    {
      "type": "vmess",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${VMESS_PORT},
      "uuid": "${USER_UUID}",
      "security": "auto",
      "transport": {
        "type": "ws",
        "path": "${VMESS_WS_PATH}"
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    # VMess URI (base64-encoded JSON) - Direct IPv4
    VMESS_JSON="{\"v\":\"2\",\"ps\":\"MoaV-VMess-WS-${USER_ID}\",\"add\":\"${SERVER_IP}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${VMESS_WS_PATH}\",\"tls\":\"\"}"
    VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    echo "$VMESS_LINK" > "$OUTPUT_DIR/vmess-ws.txt"
    qrencode -o "$OUTPUT_DIR/vmess-ws-qr.png" -s 6 "$VMESS_LINK" 2>/dev/null || true

    # CDN variant (if CDN domain is configured)
    if [[ -n "${CDN_DOMAIN:-}" ]]; then
        VMESS_CDN_JSON="{\"v\":\"2\",\"ps\":\"MoaV-VMess-CDN-${USER_ID}\",\"add\":\"${CDN_DOMAIN}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${CDN_DOMAIN}\",\"path\":\"${VMESS_WS_PATH}\",\"tls\":\"\"}"
        VMESS_CDN_LINK="vmess://$(echo -n "$VMESS_CDN_JSON" | base64 -w 0)"
        echo "$VMESS_CDN_LINK" > "$OUTPUT_DIR/vmess-cdn.txt"
    fi

    # Generate IPv6 link if available
    if [[ -n "${SERVER_IPV6:-}" ]]; then
        VMESS_V6_JSON="{\"v\":\"2\",\"ps\":\"MoaV-VMess-WS-${USER_ID}-IPv6\",\"add\":\"${SERVER_IPV6}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${VMESS_WS_PATH}\",\"tls\":\"\"}"
        VMESS_V6_LINK="vmess://$(echo -n "$VMESS_V6_JSON" | base64 -w 0)"
        echo "$VMESS_V6_LINK" > "$OUTPUT_DIR/vmess-ws-ipv6.txt"
    fi

    log_info "  - VMess+WS config generated"
fi

# -----------------------------------------------------------------------------
# Generate ShadowTLS v3 + Shadowsocks 2022 client config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_SHADOWTLS:-true}" == "true" ]]; then
    # Load SS server key
    if [[ -z "${SS_SERVER_PASSWORD:-}" ]] && [[ -f "$STATE_DIR/keys/shadowsocks.env" ]]; then
        source "$STATE_DIR/keys/shadowsocks.env"
    fi

    # Load per-user ShadowTLS/SS credentials
    if [[ -z "${SHADOWTLS_PASSWORD:-}" ]] && [[ -f "$STATE_DIR/users/$USER_ID/credentials.env" ]]; then
        SHADOWTLS_PASSWORD=$(grep "^SHADOWTLS_PASSWORD=" "$STATE_DIR/users/$USER_ID/credentials.env" | cut -d= -f2 || true)
        SS_USER_KEY=$(grep "^SS_USER_KEY=" "$STATE_DIR/users/$USER_ID/credentials.env" | cut -d= -f2 || true)
    fi

    if [[ -n "${SS_SERVER_PASSWORD:-}" ]] && [[ -n "${SHADOWTLS_PASSWORD:-}" ]] && [[ -n "${SS_USER_KEY:-}" ]]; then
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

        # Human-readable text config
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

        # QR code from sing-box JSON config (minified)
        if command -v qrencode &>/dev/null; then
            jq -c . "$OUTPUT_DIR/shadowtls-singbox.json" | qrencode -o "$OUTPUT_DIR/shadowtls-qr.png" -s 6 2>/dev/null || true
        fi

        log_info "  - ShadowTLS + SS2022 config generated"
    else
        log_info "  - ShadowTLS skipped (missing keys)"
    fi
fi

# -----------------------------------------------------------------------------
# Generate TrustTunnel client config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_TRUSTTUNNEL:-true}" == "true" ]]; then
    # TrustTunnel uses username/password authentication
    # Generate full TOML config for CLI client

    cat > "$OUTPUT_DIR/trusttunnel.toml" <<EOF
# TrustTunnel Client Configuration for $USER_ID
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
has_ipv6 = ${SERVER_IPV6:+true}${SERVER_IPV6:-false}
username = "${USER_ID}"
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

    # Generate human-readable text file with instructions
    cat > "$OUTPUT_DIR/trusttunnel.txt" <<EOF
TrustTunnel Configuration for $USER_ID
======================================

IP Address: ${SERVER_IP}:4443
Domain: ${DOMAIN}
Username: ${USER_ID}
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

    # Generate JSON config for programmatic use
    cat > "$OUTPUT_DIR/trusttunnel.json" <<EOF
{
  "ip_address": "${SERVER_IP}:4443",
  "domain": "${DOMAIN}",
  "username": "${USER_ID}",
  "password": "${USER_PASSWORD}",
  "dns_servers": ["tls://1.1.1.1", "tls://8.8.8.8"]
}
EOF

    log_info "  - TrustTunnel config generated"
fi

# -----------------------------------------------------------------------------
# Generate WireGuard config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_WIREGUARD:-true}" == "true" ]]; then
    # Count existing peers to determine next IP (peer 1 = 10.66.66.2, peer 2 = 10.66.66.3, etc.)
    PEER_COUNT=$(grep -c '^\[Peer\]' "$WG_CONFIG_DIR/wg0.conf" 2>/dev/null) || true
    PEER_COUNT=${PEER_COUNT:-0}
    PEER_NUM=$((PEER_COUNT + 1))
    wireguard_add_peer "$USER_ID" "$PEER_NUM"
    wireguard_generate_client_config "$USER_ID" "$OUTPUT_DIR"
    qrencode -o "$OUTPUT_DIR/wireguard-qr.png" -s 6 -r "$OUTPUT_DIR/wireguard.conf" 2>/dev/null || true
    qrencode -o "$OUTPUT_DIR/wireguard-wstunnel-qr.png" -s 6 -r "$OUTPUT_DIR/wireguard-wstunnel.conf" 2>/dev/null || true
    # IPv6 QR code if available
    if [[ -n "${SERVER_IPV6:-}" ]] && [[ -f "$OUTPUT_DIR/wireguard-ipv6.conf" ]]; then
        qrencode -o "$OUTPUT_DIR/wireguard-ipv6-qr.png" -s 6 -r "$OUTPUT_DIR/wireguard-ipv6.conf" 2>/dev/null || true
    fi
    log_info "  - WireGuard config generated (direct + wstunnel${SERVER_IPV6:+ + ipv6})"
fi

# -----------------------------------------------------------------------------
# Generate AmneziaWG config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_AMNEZIAWG:-true}" == "true" ]]; then
    # Count existing peers to determine next IP (peer 1 = 10.67.67.2, etc.)
    AWG_PEER_COUNT=$(grep -c '^\[Peer\]' "$AWG_CONFIG_DIR/awg0.conf" 2>/dev/null) || true
    AWG_PEER_COUNT=${AWG_PEER_COUNT:-0}
    AWG_PEER_NUM=$((AWG_PEER_COUNT + 1))
    amneziawg_add_peer "$USER_ID" "$AWG_PEER_NUM"
    amneziawg_generate_client_config "$USER_ID" "$OUTPUT_DIR"
    qrencode -o "$OUTPUT_DIR/amneziawg-qr.png" -s 6 -r "$OUTPUT_DIR/amneziawg.conf" 2>/dev/null || true
    # IPv6 QR code if available
    if [[ -n "${SERVER_IPV6:-}" ]] && [[ -f "$OUTPUT_DIR/amneziawg-ipv6.conf" ]]; then
        qrencode -o "$OUTPUT_DIR/amneziawg-ipv6-qr.png" -s 6 -r "$OUTPUT_DIR/amneziawg-ipv6.conf" 2>/dev/null || true
    fi
    log_info "  - AmneziaWG config generated (obfuscated WireGuard${SERVER_IPV6:+ + ipv6})"
fi

# -----------------------------------------------------------------------------
# Generate dnstt instructions (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_DNSTT:-true}" == "true" ]]; then
    dnstt_generate_client_instructions "$USER_ID" "$OUTPUT_DIR"
    log_info "  - dnstt instructions generated"
fi

# -----------------------------------------------------------------------------
# Generate README.html from template
# -----------------------------------------------------------------------------
TEMPLATE_FILE="/docs/client-guide-template.html"
OUTPUT_HTML="$OUTPUT_DIR/README.html"

if [[ -f "$TEMPLATE_FILE" ]]; then
    # Read config values
    CONFIG_REALITY=$(cat "$OUTPUT_DIR/reality.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_HYSTERIA2=$(cat "$OUTPUT_DIR/hysteria2.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_TROJAN=$(cat "$OUTPUT_DIR/trojan.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_CDN=$(cat "$OUTPUT_DIR/cdn-vless-ws.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_WIREGUARD=$(cat "$OUTPUT_DIR/wireguard.conf" 2>/dev/null || echo "")
    CONFIG_WIREGUARD_WSTUNNEL=$(cat "$OUTPUT_DIR/wireguard-wstunnel.conf" 2>/dev/null || echo "")
    CONFIG_AMNEZIAWG=$(cat "$OUTPUT_DIR/amneziawg.conf" 2>/dev/null || echo "")
    CONFIG_TUIC=$(cat "$OUTPUT_DIR/tuic.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_VMESS=$(cat "$OUTPUT_DIR/vmess-ws.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_VMESS_CDN=$(cat "$OUTPUT_DIR/vmess-cdn.txt" 2>/dev/null | tr -d '\n' || echo "")
    CONFIG_SHADOWTLS=$(cat "$OUTPUT_DIR/shadowtls.txt" 2>/dev/null || echo "")

    # Get dnstt info
    DNSTT_DOMAIN="${DNSTT_SUBDOMAIN:-t}.${DOMAIN}"
    DNSTT_PUBKEY=$(cat "$STATE_DIR/keys/dnstt-server.pub.hex" 2>/dev/null || echo "")

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
    QR_CDN_B64=$(qr_to_base64 "$OUTPUT_DIR/cdn-vless-ws-qr.png")
    QR_WIREGUARD_B64=$(qr_to_base64 "$OUTPUT_DIR/wireguard-qr.png")
    QR_WIREGUARD_WSTUNNEL_B64=$(qr_to_base64 "$OUTPUT_DIR/wireguard-wstunnel-qr.png")
    QR_AMNEZIAWG_B64=$(qr_to_base64 "$OUTPUT_DIR/amneziawg-qr.png")
    QR_TUIC_B64=$(qr_to_base64 "$OUTPUT_DIR/tuic-qr.png")
    QR_VMESS_B64=$(qr_to_base64 "$OUTPUT_DIR/vmess-ws-qr.png")
    QR_SHADOWTLS_B64=$(qr_to_base64 "$OUTPUT_DIR/shadowtls-qr.png")

    GENERATED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Copy template and replace placeholders
    cp "$TEMPLATE_FILE" "$OUTPUT_HTML"

    # Simple replacements
    sed -i "s|{{USERNAME}}|$USER_ID|g" "$OUTPUT_HTML"
    sed -i "s|{{SERVER_IP}}|$SERVER_IP|g" "$OUTPUT_HTML"
    sed -i "s|{{DOMAIN}}|$DOMAIN|g" "$OUTPUT_HTML"
    sed -i "s|{{GENERATED_DATE}}|$GENERATED_DATE|g" "$OUTPUT_HTML"
    sed -i "s|{{DNSTT_DOMAIN}}|$DNSTT_DOMAIN|g" "$OUTPUT_HTML"
    sed -i "s|{{DNSTT_PUBKEY}}|$DNSTT_PUBKEY|g" "$OUTPUT_HTML"

    # TrustTunnel password (same as user password) - escape special chars
    if [[ -n "${USER_PASSWORD:-}" ]]; then
        escaped_pw=$(printf '%s' "$USER_PASSWORD" | sed -e 's/[&\\/]/\\&/g')
        sed -i "s|{{TRUSTTUNNEL_PASSWORD}}|${escaped_pw}|g" "$OUTPUT_HTML"
    else
        sed -i "s|{{TRUSTTUNNEL_PASSWORD}}|See trusttunnel.txt|g" "$OUTPUT_HTML"
    fi

    # Demo user notice (only for bootstrap demouser)
    if [[ "${IS_DEMO_USER:-false}" == "true" ]]; then
        # Build list of disabled services
        DISABLED_SERVICES=""
        [[ "${ENABLE_WIREGUARD:-true}" != "true" ]] && DISABLED_SERVICES+="WireGuard, "
        [[ "${ENABLE_DNSTT:-true}" != "true" ]] && DISABLED_SERVICES+="DNS Tunnel, "
        [[ "${ENABLE_TROJAN:-true}" != "true" ]] && DISABLED_SERVICES+="Trojan, "
        [[ "${ENABLE_HYSTERIA2:-true}" != "true" ]] && DISABLED_SERVICES+="Hysteria2, "
        [[ "${ENABLE_REALITY:-true}" != "true" ]] && DISABLED_SERVICES+="Reality, "
        DISABLED_SERVICES="${DISABLED_SERVICES%, }"  # Remove trailing comma

        # English notice
        DEMO_NOTICE_EN='<div class="warning" style="background: rgba(210, 153, 34, 0.1); border-color: var(--accent-orange); color: var(--accent-orange); margin-top: 12px;"><strong>Demo User Notice:</strong> This is a demo account created during initial setup. Some config files may be missing if services were not enabled'"${DISABLED_SERVICES:+ ($DISABLED_SERVICES)}"'. See <a href="https://github.com/moav-project/moav/tree/main/docs" style="color: var(--accent-orange);">documentation</a> for setup.</div>'

        # Farsi notice
        DEMO_NOTICE_FA='<div class="warning" style="background: rgba(210, 153, 34, 0.1); border-color: var(--accent-orange); color: var(--accent-orange); margin-top: 12px;"><strong>توجه:</strong> این یک حساب کاربری آزمایشی است. برخی فایل‌های پیکربندی ممکن است وجود نداشته باشند. برای راهنمایی به <a href="https://github.com/moav-project/moav/tree/main/docs" style="color: var(--accent-orange);">مستندات</a> مراجعه کنید.</div>'

        sed -i "s|{{DEMO_NOTICE_EN}}|$DEMO_NOTICE_EN|g" "$OUTPUT_HTML"
        sed -i "s|{{DEMO_NOTICE_FA}}|$DEMO_NOTICE_FA|g" "$OUTPUT_HTML"
    else
        # Remove placeholders for non-demo users
        sed -i "s|{{DEMO_NOTICE_EN}}||g" "$OUTPUT_HTML"
        sed -i "s|{{DEMO_NOTICE_FA}}||g" "$OUTPUT_HTML"
    fi

    # Clean up any .bak files
    rm -f "$OUTPUT_HTML.bak"

    # QR codes (base64) - safe for sed as base64 has no special chars
    sed -i "s|{{QR_REALITY}}|$QR_REALITY_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_HYSTERIA2}}|$QR_HYSTERIA2_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_TROJAN}}|$QR_TROJAN_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_CDN}}|$QR_CDN_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_WIREGUARD}}|$QR_WIREGUARD_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_WIREGUARD_WSTUNNEL}}|$QR_WIREGUARD_WSTUNNEL_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_AMNEZIAWG}}|$QR_AMNEZIAWG_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_TUIC}}|$QR_TUIC_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_VMESS}}|$QR_VMESS_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_SHADOWTLS}}|$QR_SHADOWTLS_B64|g" "$OUTPUT_HTML"

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
        replace_placeholder "{{CDN_DOMAIN}}" "${CDN_DOMAIN:-}"
    else
        replace_placeholder "{{CONFIG_CDN}}" "CDN not configured"
        replace_placeholder "{{CDN_DOMAIN}}" "Not configured"
    fi

    # WireGuard config is multiline - use Python replacement
    if [[ -n "$CONFIG_WIREGUARD" ]]; then
        replace_placeholder "{{CONFIG_WIREGUARD}}" "$CONFIG_WIREGUARD"
    else
        replace_placeholder "{{CONFIG_WIREGUARD}}" "No WireGuard config available"
    fi

    # WireGuard-wstunnel config is multiline
    if [[ -n "$CONFIG_WIREGUARD_WSTUNNEL" ]]; then
        replace_placeholder "{{CONFIG_WIREGUARD_WSTUNNEL}}" "$CONFIG_WIREGUARD_WSTUNNEL"
    else
        replace_placeholder "{{CONFIG_WIREGUARD_WSTUNNEL}}" "No WireGuard-wstunnel config available"
    fi

    # AmneziaWG config is multiline
    if [[ -n "$CONFIG_AMNEZIAWG" ]]; then
        replace_placeholder "{{CONFIG_AMNEZIAWG}}" "$CONFIG_AMNEZIAWG"
    else
        replace_placeholder "{{CONFIG_AMNEZIAWG}}" "No AmneziaWG config available"
    fi

    # TUIC config
    if [[ -n "$CONFIG_TUIC" ]]; then
        replace_placeholder "{{CONFIG_TUIC}}" "$CONFIG_TUIC"
    else
        replace_placeholder "{{CONFIG_TUIC}}" "No TUIC config available"
    fi

    # VMess+WS config
    if [[ -n "$CONFIG_VMESS" ]]; then
        replace_placeholder "{{CONFIG_VMESS}}" "$CONFIG_VMESS"
    else
        replace_placeholder "{{CONFIG_VMESS}}" "No VMess config available"
    fi

    # VMess CDN config
    if [[ -n "$CONFIG_VMESS_CDN" ]]; then
        replace_placeholder "{{CONFIG_VMESS_CDN}}" "$CONFIG_VMESS_CDN"
    else
        replace_placeholder "{{CONFIG_VMESS_CDN}}" "No VMess CDN config available"
    fi

    # ShadowTLS config (multiline)
    if [[ -n "$CONFIG_SHADOWTLS" ]]; then
        replace_placeholder "{{CONFIG_SHADOWTLS}}" "$CONFIG_SHADOWTLS"
    else
        replace_placeholder "{{CONFIG_SHADOWTLS}}" "No ShadowTLS config available"
    fi

    log_info "  - README.html generated"
else
    log_info "  - README.html skipped (template not found)"
fi

log_info "Bundle generated at $OUTPUT_DIR"
