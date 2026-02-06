#!/bin/bash
set -euo pipefail

# =============================================================================
# Generate user bundle with all client configurations
# Usage: generate-user.sh <user_id>
# =============================================================================

source /app/lib/common.sh
source /app/lib/wireguard.sh
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

Endpoint: ${DOMAIN}:4443
Server IP: ${SERVER_IP}
Username: ${USER_ID}
Password: ${USER_PASSWORD}

CLI Client:
-----------
1. Download from: https://github.com/TrustTunnel/TrustTunnelClient/releases
2. Run: trusttunnel_client trusttunnel.toml

Mobile/Desktop App:
-------------------
1. Download TrustTunnel from app store or https://trusttunnel.org/
2. Add new VPN with the endpoint, username, and password above
3. Connect

Note: TrustTunnel supports HTTP/2 and HTTP/3 (QUIC) transports,
which look like regular HTTPS traffic to network observers.
EOF

    # Generate JSON config for programmatic use
    cat > "$OUTPUT_DIR/trusttunnel.json" <<EOF
{
  "endpoint": "${DOMAIN}:4443",
  "server_ip": "${SERVER_IP}",
  "username": "${USER_ID}",
  "password": "${USER_PASSWORD}"
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
    CONFIG_WIREGUARD=$(cat "$OUTPUT_DIR/wireguard.conf" 2>/dev/null || echo "")
    CONFIG_WIREGUARD_WSTUNNEL=$(cat "$OUTPUT_DIR/wireguard-wstunnel.conf" 2>/dev/null || echo "")

    # Get dnstt info
    DNSTT_DOMAIN="${DNSTT_SUBDOMAIN:-t}.${DOMAIN}"
    DNSTT_PUBKEY=$(cat "$STATE_DIR/keys/dnstt-server.pub" 2>/dev/null || echo "")

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

    # TrustTunnel password (same as user password)
    if [[ -n "${USER_PASSWORD:-}" ]]; then
        sed -i "s|{{TRUSTTUNNEL_PASSWORD}}|$USER_PASSWORD|g" "$OUTPUT_HTML"
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

    # QR codes (base64)
    sed -i "s|{{QR_REALITY}}|$QR_REALITY_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_HYSTERIA2}}|$QR_HYSTERIA2_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_TROJAN}}|$QR_TROJAN_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_WIREGUARD}}|$QR_WIREGUARD_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_WIREGUARD_WSTUNNEL}}|$QR_WIREGUARD_WSTUNNEL_B64|g" "$OUTPUT_HTML"

    # Config values (need special handling for special characters)
    # Write value to temp file to avoid shell escaping issues
    replace_placeholder() {
        local placeholder="$1"
        local value="$2"
        local placeholder_len=${#placeholder}
        local temp_value_file=$(mktemp)
        printf '%s' "$value" > "$temp_value_file"
        awk -v placeholder="$placeholder" -v plen="$placeholder_len" -v valfile="$temp_value_file" '
        BEGIN {
            val = ""
            while ((getline line < valfile) > 0) {
                if (val != "") val = val "\n"
                val = val line
            }
            close(valfile)
        }
        {
            while ((i = index($0, placeholder)) > 0) {
                $0 = substr($0, 1, i-1) val substr($0, i+plen)
            }
            print
        }' "$OUTPUT_HTML" > "$OUTPUT_HTML.new" && mv "$OUTPUT_HTML.new" "$OUTPUT_HTML"
        rm -f "$temp_value_file"
    }

    if [[ -n "$CONFIG_REALITY" ]]; then
        replace_placeholder "{{CONFIG_REALITY}}" "$CONFIG_REALITY"
    else
        sed -i "s|{{CONFIG_REALITY}}|No Reality config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_HYSTERIA2" ]]; then
        replace_placeholder "{{CONFIG_HYSTERIA2}}" "$CONFIG_HYSTERIA2"
    else
        sed -i "s|{{CONFIG_HYSTERIA2}}|No Hysteria2 config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_TROJAN" ]]; then
        replace_placeholder "{{CONFIG_TROJAN}}" "$CONFIG_TROJAN"
    else
        sed -i "s|{{CONFIG_TROJAN}}|No Trojan config available|g" "$OUTPUT_HTML"
    fi

    # WireGuard config is multiline - use same safe replacement
    if [[ -n "$CONFIG_WIREGUARD" ]]; then
        replace_placeholder "{{CONFIG_WIREGUARD}}" "$CONFIG_WIREGUARD"
    else
        sed -i "s|{{CONFIG_WIREGUARD}}|No WireGuard config available|g" "$OUTPUT_HTML"
    fi

    # WireGuard-wstunnel config is multiline
    if [[ -n "$CONFIG_WIREGUARD_WSTUNNEL" ]]; then
        replace_placeholder "{{CONFIG_WIREGUARD_WSTUNNEL}}" "$CONFIG_WIREGUARD_WSTUNNEL"
    else
        sed -i "s|{{CONFIG_WIREGUARD_WSTUNNEL}}|No WireGuard-wstunnel config available|g" "$OUTPUT_HTML"
    fi

    log_info "  - README.html generated"
else
    log_info "  - README.html skipped (template not found)"
fi

log_info "Bundle generated at $OUTPUT_DIR"
