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

# Generate v2rayN/NekoBox compatible link
REALITY_LINK="vless://${USER_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_TARGET_HOST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#MoaV-Reality-${USER_ID}"
echo "$REALITY_LINK" > "$OUTPUT_DIR/reality.txt"

# Generate QR code
qrencode -o "$OUTPUT_DIR/reality-qr.png" -s 6 "$REALITY_LINK" 2>/dev/null || true

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

# Generate Trojan URI
TROJAN_LINK="trojan://${USER_PASSWORD}@${SERVER_IP}:8443?security=tls&sni=${DOMAIN}&type=tcp#MoaV-Trojan-${USER_ID}"
echo "$TROJAN_LINK" > "$OUTPUT_DIR/trojan.txt"
qrencode -o "$OUTPUT_DIR/trojan-qr.png" -s 6 "$TROJAN_LINK" 2>/dev/null || true

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

# Hysteria2 URI
HY2_LINK="hysteria2://${USER_PASSWORD}@${SERVER_IP}:443?sni=${DOMAIN}#MoaV-Hysteria2-${USER_ID}"
echo "$HY2_LINK" > "$OUTPUT_DIR/hysteria2.txt"
qrencode -o "$OUTPUT_DIR/hysteria2-qr.png" -s 6 "$HY2_LINK" 2>/dev/null || true

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
    log_info "  - WireGuard config generated (direct + wstunnel)"
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
cat > "$OUTPUT_DIR/README.md" <<EOF
# MoaV Connection Guide for ${USER_ID}

This bundle contains your personal credentials for connecting to the MoaV server.
**Do not share these files with anyone.**

Server: \`${SERVER_IP}\` / \`${DOMAIN}\`

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
| Nothing works | Try DNS tunnel as last resort |

---

## Security Notes

- These credentials are unique to you
- If compromised, contact the admin to revoke and get new ones
- Don't share screenshots of QR codes
- Delete this file after importing configs to your devices

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log_info "Bundle generated at $OUTPUT_DIR"
