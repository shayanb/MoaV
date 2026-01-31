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

# Load Reality keys
source "$STATE_DIR/keys/reality.env"

# Create output directory
OUTPUT_DIR="/outputs/bundles/$USER_ID"
ensure_dir "$OUTPUT_DIR"

# Parse Reality target
REALITY_TARGET_HOST=$(echo "${REALITY_TARGET:-www.microsoft.com:443}" | cut -d: -f1)
REALITY_TARGET_PORT=$(echo "${REALITY_TARGET:-www.microsoft.com:443}" | cut -d: -f2)

log_info "Generating bundle for $USER_ID..."

# -----------------------------------------------------------------------------
# Generate Reality (VLESS) client config (sing-box 1.12+ format)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Generate Trojan client config (sing-box 1.12+ format)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Generate Hysteria2 client config
# -----------------------------------------------------------------------------
cat > "$OUTPUT_DIR/hysteria2.yaml" <<EOF
server: ${SERVER_IP}:443
auth: ${USER_PASSWORD}

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

# Hysteria2 URI (IPv4)
HY2_LINK="hysteria2://${USER_PASSWORD}@${SERVER_IP}:443?sni=${DOMAIN}#MoaV-Hysteria2-${USER_ID}"
echo "$HY2_LINK" > "$OUTPUT_DIR/hysteria2.txt"
qrencode -o "$OUTPUT_DIR/hysteria2-qr.png" -s 6 "$HY2_LINK" 2>/dev/null || true

# Generate IPv6 link if available
if [[ -n "${SERVER_IPV6:-}" ]]; then
    HY2_LINK_V6="hysteria2://${USER_PASSWORD}@[${SERVER_IPV6}]:443?sni=${DOMAIN}#MoaV-Hysteria2-${USER_ID}-IPv6"
    echo "$HY2_LINK_V6" > "$OUTPUT_DIR/hysteria2-ipv6.txt"
    qrencode -o "$OUTPUT_DIR/hysteria2-ipv6-qr.png" -s 6 "$HY2_LINK_V6" 2>/dev/null || true
fi

log_info "  - Hysteria2 config generated"

# -----------------------------------------------------------------------------
# Generate WireGuard config (if enabled)
# -----------------------------------------------------------------------------
if [[ "${ENABLE_WIREGUARD:-true}" == "true" ]]; then
    # Get peer number from user ID
    PEER_NUM=$(echo "$USER_ID" | tr -dc '0-9')
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
# Generate README for user
# -----------------------------------------------------------------------------

# Check for demo user mode
DEMO_NOTE=""
if [[ "${IS_DEMO_USER:-false}" == "true" ]]; then
    # Build list of disabled services
    DISABLED_SERVICES=""
    [[ "${ENABLE_WIREGUARD:-true}" != "true" ]] && DISABLED_SERVICES+="WireGuard, "
    [[ "${ENABLE_DNSTT:-true}" != "true" ]] && DISABLED_SERVICES+="DNS Tunnel, "
    [[ "${ENABLE_TROJAN:-true}" != "true" ]] && DISABLED_SERVICES+="Trojan, "
    [[ "${ENABLE_HYSTERIA2:-true}" != "true" ]] && DISABLED_SERVICES+="Hysteria2, "
    [[ "${ENABLE_REALITY:-true}" != "true" ]] && DISABLED_SERVICES+="Reality, "
    DISABLED_SERVICES="${DISABLED_SERVICES%, }"  # Remove trailing comma

    DEMO_NOTE="
> ⚠️ **Demo User Notice**
>
> This is a demo user account created during initial setup. Some configuration
> files may be missing if their corresponding services were not enabled:
> ${DISABLED_SERVICES:-All services are enabled.}
>
> To enable additional services, update your \`.env\` file and run:
> \`\`\`bash
> moav bootstrap   # Regenerate configs
> moav start       # Start additional services
> \`\`\`
>
> For full documentation, see: https://github.com/moav-project/moav/tree/main/docs

---
"
fi

cat > "$OUTPUT_DIR/README.md" <<EOF
# MoaV Connection Guide for ${USER_ID}

This bundle contains your personal credentials for connecting to the MoaV server.
**Do not share these files with anyone.**
${DEMO_NOTE}
Server: \`${SERVER_IP}\` / \`${DOMAIN}\`$(if [[ -n "${SERVER_IPV6:-}" ]]; then echo "
IPv6: \`${SERVER_IPV6}\`"; fi)

---

## Quick Start (Recommended Order)

Try these methods in order. If one doesn't work, try the next.

### 1. Reality (VLESS) - Primary, Most Reliable

**Why:** Impersonates legitimate TLS traffic to ${REALITY_TARGET_HOST}. Very hard to detect.

| Platform | App | How to Import |
|----------|-----|---------------|
| iOS | Shadowrocket (\$2.99) | Scan \`reality-qr.png\` or import \`reality.txt\` |
| iOS | Streisand (free) | Scan QR or paste link |
| Android | v2rayNG (free) | Scan QR or import link |
| Android | NekoBox (free) | Import \`reality-singbox.json\` |
| macOS | V2rayU | Import link from \`reality.txt\` |

**Your Reality Link:**
\`\`\`
$(cat "$OUTPUT_DIR/reality.txt")
\`\`\`

---

### 2. Hysteria2 - Fast Alternative

**Why:** Uses QUIC protocol (like Google). Fast and often works when TCP is throttled.

| Platform | App | How to Import |
|----------|-----|---------------|
| iOS | Shadowrocket | Scan \`hysteria2-qr.png\` |
| Android | v2rayNG | Scan QR or import link |
| Any | Hysteria2 CLI | Use \`hysteria2.yaml\` |

**Your Hysteria2 Link:**
\`\`\`
$(cat "$OUTPUT_DIR/hysteria2.txt")
\`\`\`

---

### 3. Trojan - Backup (Port 8443)

**Why:** Looks like normal HTTPS. Uses your dedicated domain on port 8443.

**Your Trojan Link:**
\`\`\`
$(cat "$OUTPUT_DIR/trojan.txt")
\`\`\`

---

### 4. WireGuard - Full VPN Mode

**Why:** Full system VPN with all traffic routed through the tunnel.

**Direct Connection (if WireGuard is not blocked):**
1. Install WireGuard app (iOS/Android/Mac/Windows)
2. Import \`wireguard.conf\` or scan \`wireguard-qr.png\`
3. Connect

**Via WebSocket (for censored networks like Iran/China/Russia):**
If direct WireGuard is blocked, use wstunnel to wrap traffic in WebSocket:
1. Download wstunnel from https://github.com/erebe/wstunnel/releases
2. Run: \`wstunnel client -L udp://127.0.0.1:51820:127.0.0.1:51820 wss://${SERVER_IP}:8080\`
3. Import \`wireguard-wstunnel.conf\` (points to localhost)
4. Connect WireGuard while wstunnel is running

---

### 5. DNS Tunnel - Last Resort

**Why:** Works when ONLY DNS traffic is allowed. Very slow but reliable.

See \`dnstt-instructions.txt\` for setup steps.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't connect | Try a different protocol (Reality → Hysteria2 → Trojan) |
| Very slow | Your ISP may be throttling. Try Hysteria2 (uses UDP) |
| Disconnects often | Enable "Persistent Connection" in your app settings |
| IPv4 blocked | Try the \`-ipv6\` config files if available |
| Nothing works | Try DNS tunnel as last resort |

---

## Security Notes

- These credentials are unique to you
- If compromised, contact the admin to revoke and get new ones
- Don't share screenshots of QR codes
- Delete this file after importing configs to your devices

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

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

    # QR codes (base64)
    sed -i "s|{{QR_REALITY}}|$QR_REALITY_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_HYSTERIA2}}|$QR_HYSTERIA2_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_TROJAN}}|$QR_TROJAN_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_WIREGUARD}}|$QR_WIREGUARD_B64|g" "$OUTPUT_HTML"
    sed -i "s|{{QR_WIREGUARD_WSTUNNEL}}|$QR_WIREGUARD_WSTUNNEL_B64|g" "$OUTPUT_HTML"

    # Config values (need special handling for special characters)
    escape_for_awk() {
        echo "$1" | sed 's/&/\\\\\\&/g'
    }

    if [[ -n "$CONFIG_REALITY" ]]; then
        ESCAPED=$(escape_for_awk "$CONFIG_REALITY")
        awk -v replacement="$ESCAPED" '{gsub(/\{\{CONFIG_REALITY\}\}/, replacement)}1' "$OUTPUT_HTML" > "$OUTPUT_HTML.new" && mv "$OUTPUT_HTML.new" "$OUTPUT_HTML"
    else
        sed -i "s|{{CONFIG_REALITY}}|No Reality config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_HYSTERIA2" ]]; then
        ESCAPED=$(escape_for_awk "$CONFIG_HYSTERIA2")
        awk -v replacement="$ESCAPED" '{gsub(/\{\{CONFIG_HYSTERIA2\}\}/, replacement)}1' "$OUTPUT_HTML" > "$OUTPUT_HTML.new" && mv "$OUTPUT_HTML.new" "$OUTPUT_HTML"
    else
        sed -i "s|{{CONFIG_HYSTERIA2}}|No Hysteria2 config available|g" "$OUTPUT_HTML"
    fi

    if [[ -n "$CONFIG_TROJAN" ]]; then
        ESCAPED=$(escape_for_awk "$CONFIG_TROJAN")
        awk -v replacement="$ESCAPED" '{gsub(/\{\{CONFIG_TROJAN\}\}/, replacement)}1' "$OUTPUT_HTML" > "$OUTPUT_HTML.new" && mv "$OUTPUT_HTML.new" "$OUTPUT_HTML"
    else
        sed -i "s|{{CONFIG_TROJAN}}|No Trojan config available|g" "$OUTPUT_HTML"
    fi

    # WireGuard config is multiline
    if [[ -n "$CONFIG_WIREGUARD" ]]; then
        ESCAPED=$(echo "$CONFIG_WIREGUARD" | sed 's/&/\\\\\\&/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
        awk -v replacement="$ESCAPED" 'BEGIN{gsub(/\\n/,"\n",replacement)} {gsub(/\{\{CONFIG_WIREGUARD\}\}/, replacement)}1' "$OUTPUT_HTML" > "$OUTPUT_HTML.new" && mv "$OUTPUT_HTML.new" "$OUTPUT_HTML"
    else
        sed -i "s|{{CONFIG_WIREGUARD}}|No WireGuard config available|g" "$OUTPUT_HTML"
    fi

    # WireGuard-wstunnel config is multiline
    if [[ -n "$CONFIG_WIREGUARD_WSTUNNEL" ]]; then
        ESCAPED=$(echo "$CONFIG_WIREGUARD_WSTUNNEL" | sed 's/&/\\\\\\&/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
        awk -v replacement="$ESCAPED" 'BEGIN{gsub(/\\n/,"\n",replacement)} {gsub(/\{\{CONFIG_WIREGUARD_WSTUNNEL\}\}/, replacement)}1' "$OUTPUT_HTML" > "$OUTPUT_HTML.new" && mv "$OUTPUT_HTML.new" "$OUTPUT_HTML"
    else
        sed -i "s|{{CONFIG_WIREGUARD_WSTUNNEL}}|No WireGuard-wstunnel config available|g" "$OUTPUT_HTML"
    fi

    log_info "  - README.html generated"
else
    log_info "  - README.html skipped (template not found)"
fi

log_info "Bundle generated at $OUTPUT_DIR"
