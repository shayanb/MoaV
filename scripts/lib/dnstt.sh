#!/bin/bash
# dnstt DNS tunnel configuration functions

DNSTT_CONFIG_DIR="/configs/dnstt"

generate_dnstt_config() {
    log_info "Setting up dnstt configuration..."

    ensure_dir "$DNSTT_CONFIG_DIR"
    ensure_dir "$STATE_DIR/keys"

    # Generate keypair if not exists or is empty/invalid
    local need_keygen=false
    local key_file="$STATE_DIR/keys/dnstt-server.key.hex"

    if [[ ! -f "$key_file" ]]; then
        log_info "dnstt key file does not exist, will generate..."
        need_keygen=true
    elif [[ ! -s "$key_file" ]]; then
        log_info "dnstt key file is empty, regenerating..."
        need_keygen=true
    else
        local key_size=$(wc -c < "$key_file" | tr -d ' ')
        if [[ $key_size -lt 60 ]]; then
            log_info "dnstt key file too small ($key_size bytes), regenerating..."
            need_keygen=true
        else
            log_info "dnstt key file exists and looks valid ($key_size bytes)"
        fi
    fi

    if [[ "$need_keygen" == "true" ]]; then
        log_info "Generating dnstt x25519 keypair..."

        # Generate x25519 keypair using openssl
        if ! openssl genpkey -algorithm x25519 -out "$STATE_DIR/keys/dnstt-temp.pem" 2>&1; then
            log_error "Failed to generate x25519 key with openssl"
            return 1
        fi

        if [[ ! -f "$STATE_DIR/keys/dnstt-temp.pem" ]]; then
            log_error "x25519 key file was not created"
            return 1
        fi

        # Extract raw private key (last 32 bytes of DER) as hex
        openssl pkey -in "$STATE_DIR/keys/dnstt-temp.pem" -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 64 > "$STATE_DIR/keys/dnstt-server.key.hex"

        # Extract raw public key (last 32 bytes of DER pubkey) as hex
        openssl pkey -in "$STATE_DIR/keys/dnstt-temp.pem" -pubout -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 64 > "$STATE_DIR/keys/dnstt-server.pub.hex"

        rm -f "$STATE_DIR/keys/dnstt-temp.pem"

        # Verify keys were created
        if [[ ! -s "$STATE_DIR/keys/dnstt-server.key.hex" ]]; then
            log_error "Failed to generate dnstt private key - file is empty"
            ls -la "$STATE_DIR/keys/" || true
            return 1
        fi
        if [[ ! -s "$STATE_DIR/keys/dnstt-server.pub.hex" ]]; then
            log_error "Failed to generate dnstt public key - file is empty"
            return 1
        fi

        log_info "dnstt keypair generated successfully"
        log_info "Private key at: $STATE_DIR/keys/dnstt-server.key.hex"
        log_info "Public key at: $STATE_DIR/keys/dnstt-server.pub.hex"
    fi

    local dnstt_pubkey
    dnstt_pubkey=$(cat "$STATE_DIR/keys/dnstt-server.pub.hex")

    # Write server config
    cat > "$DNSTT_CONFIG_DIR/server.conf" <<EOF
# dnstt server configuration
DNSTT_DOMAIN=${DNSTT_SUBDOMAIN:-t}.${DOMAIN}
DNSTT_PRIVKEY_FILE=/state/keys/dnstt-server.key.hex
DNSTT_UPSTREAM=127.0.0.1:8080
EOF

    # Write public key for clients
    echo "$dnstt_pubkey" > "$DNSTT_CONFIG_DIR/server.pub"

    # Copy to outputs for easy distribution
    ensure_dir "/outputs/dnstt"
    cp "$DNSTT_CONFIG_DIR/server.pub" "/outputs/dnstt/server.pub"

    log_info "dnstt configuration created"
    log_info "Public key (hex): $dnstt_pubkey"
}

# Generate dnstt client instructions for a user
dnstt_generate_client_instructions() {
    local user_id="$1"
    local output_dir="$2"

    local dnstt_pubkey
    dnstt_pubkey=$(cat "$STATE_DIR/keys/dnstt-server.pub.hex" 2>/dev/null || echo "KEY_NOT_GENERATED")
    local dnstt_domain="${DNSTT_SUBDOMAIN:-t}.${DOMAIN}"

    cat > "$output_dir/dnstt-instructions.txt" <<EOF
# dnstt DNS Tunnel Instructions
# =============================
# Use this as a LAST RESORT when other methods are blocked.
# DNS tunneling is SLOW but often works when everything else fails.

# Server Public Key (hex):
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
