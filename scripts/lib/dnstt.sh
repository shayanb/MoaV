#!/bin/bash
# dnstt DNS tunnel configuration functions

DNSTT_CONFIG_DIR="/configs/dnstt"

generate_dnstt_config() {
    ensure_dir "$DNSTT_CONFIG_DIR"

    # Generate keypair if not exists
    if [[ ! -f "$STATE_DIR/keys/dnstt-server.key" ]]; then
        log_info "Generating dnstt keypair..."

        # dnstt uses a specific key format - generate with openssl
        openssl genpkey -algorithm x25519 -out "$STATE_DIR/keys/dnstt-server.key"
        openssl pkey -in "$STATE_DIR/keys/dnstt-server.key" -pubout -out "$STATE_DIR/keys/dnstt-server.pub"

        # Also generate in the format dnstt expects (raw base64)
        openssl pkey -in "$STATE_DIR/keys/dnstt-server.key" -outform DER | tail -c 32 | base64 > "$STATE_DIR/keys/dnstt-server.key.b64"
        openssl pkey -in "$STATE_DIR/keys/dnstt-server.key" -pubout -outform DER | tail -c 32 | base64 > "$STATE_DIR/keys/dnstt-server.pub.b64"
    fi

    local dnstt_pubkey
    dnstt_pubkey=$(cat "$STATE_DIR/keys/dnstt-server.pub.b64")

    # Write server config
    cat > "$DNSTT_CONFIG_DIR/server.conf" <<EOF
# dnstt server configuration
DNSTT_DOMAIN=${DNSTT_SUBDOMAIN:-t}.${DOMAIN}
DNSTT_PRIVKEY_FILE=/state/keys/dnstt-server.key.b64
DNSTT_UPSTREAM=127.0.0.1:8080
EOF

    # Write public key for clients
    echo "$dnstt_pubkey" > "$DNSTT_CONFIG_DIR/server.pub"

    # Copy to outputs for easy distribution
    ensure_dir "/outputs/dnstt"
    cp "$DNSTT_CONFIG_DIR/server.pub" "/outputs/dnstt/server.pub"

    log_info "dnstt configuration created"
    log_info "Public key: $dnstt_pubkey"
}

# Generate dnstt client instructions for a user
dnstt_generate_client_instructions() {
    local user_id="$1"
    local output_dir="$2"

    local dnstt_pubkey
    dnstt_pubkey=$(cat "$STATE_DIR/keys/dnstt-server.pub.b64")
    local dnstt_domain="${DNSTT_SUBDOMAIN:-t}.${DOMAIN}"

    cat > "$output_dir/dnstt-instructions.txt" <<EOF
# dnstt DNS Tunnel Instructions
# =============================
# Use this as a LAST RESORT when other methods are blocked.
# DNS tunneling is SLOW but often works when everything else fails.

# Server Public Key:
$dnstt_pubkey

# Tunnel Domain:
$dnstt_domain

# -------------------------
# Option 1: Using DoH (DNS over HTTPS) - RECOMMENDED
# -------------------------

# Download dnstt-client from: https://www.bamsoftware.com/software/dnstt/

# Run (creates a local SOCKS5 proxy on port 1080):
dnstt-client -doh https://1.1.1.1/dns-query -pubkey $dnstt_pubkey $dnstt_domain 127.0.0.1:1080

# Then configure your apps to use SOCKS5 proxy: 127.0.0.1:1080

# -------------------------
# Option 2: Using Plain UDP DNS
# -------------------------

# If DoH is blocked, try plain UDP (use a public resolver):
dnstt-client -udp 8.8.8.8:53 -pubkey $dnstt_pubkey $dnstt_domain 127.0.0.1:1080

# -------------------------
# Alternative Resolvers (if one is blocked, try another):
# -------------------------
# - Cloudflare DoH: https://1.1.1.1/dns-query
# - Google DoH: https://dns.google/dns-query
# - Cloudflare UDP: 1.1.1.1:53
# - Google UDP: 8.8.8.8:53
# - Quad9 DoH: https://dns.quad9.net/dns-query

# -------------------------
# Notes:
# -------------------------
# - DNS tunneling is slow (expect 10-50 KB/s)
# - Works best for text-based apps (chat, email)
# - Not suitable for video streaming or large downloads
# - Keep the dnstt-client running while you need the connection
EOF

    log_info "Generated dnstt instructions for $user_id"
}
