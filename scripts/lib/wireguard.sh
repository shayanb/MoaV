#!/bin/bash
# WireGuard configuration functions

WG_CONFIG_DIR="/configs/wireguard"
WG_PORT=51820
WG_NETWORK="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1"

generate_wireguard_config() {
    ensure_dir "$WG_CONFIG_DIR"
    ensure_dir "$STATE_DIR/keys"

    # Generate server keys if not exist
    if [[ ! -f "$STATE_DIR/keys/wg-server.key" ]]; then
        log_info "Generating new WireGuard server keys..."
        wg genkey > "$STATE_DIR/keys/wg-server.key"
    fi

    # Always derive public key from private key to ensure consistency
    local server_private_key
    local server_public_key
    server_private_key=$(cat "$STATE_DIR/keys/wg-server.key")
    server_public_key=$(echo "$server_private_key" | wg pubkey)

    # Save public key to state (authoritative source)
    echo "$server_public_key" > "$STATE_DIR/keys/wg-server.pub"

    log_info "WireGuard server private key: $STATE_DIR/keys/wg-server.key"
    log_info "WireGuard server public key: $server_public_key"

    # Create server config
    cat > "$WG_CONFIG_DIR/wg0.conf" <<EOF
[Interface]
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $server_private_key
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth+ -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth+ -j MASQUERADE

# Peers are added dynamically
EOF

    # Save server public key for client configs (copy from state)
    cp "$STATE_DIR/keys/wg-server.pub" "$WG_CONFIG_DIR/server.pub"

    log_info "WireGuard server configuration created"
    log_info "Server public key saved to: $WG_CONFIG_DIR/server.pub"
}

# Add a WireGuard peer
wireguard_add_peer() {
    local user_id="$1"
    local peer_num="$2"

    # Generate client keys
    local client_private_key
    local client_public_key
    client_private_key=$(wg genkey)
    client_public_key=$(echo "$client_private_key" | wg pubkey)

    # Calculate client IP
    local client_ip="10.66.66.$((peer_num + 1))"

    # Save client credentials
    cat > "$STATE_DIR/users/$user_id/wireguard.env" <<EOF
WG_PRIVATE_KEY=$client_private_key
WG_PUBLIC_KEY=$client_public_key
WG_CLIENT_IP=$client_ip
EOF

    # Add peer to server config
    cat >> "$WG_CONFIG_DIR/wg0.conf" <<EOF

[Peer]
# $user_id
PublicKey = $client_public_key
AllowedIPs = $client_ip/32
EOF

    log_info "Added WireGuard peer for $user_id"
}

# Generate WireGuard client config
wireguard_generate_client_config() {
    local user_id="$1"
    local output_dir="$2"

    source "$STATE_DIR/users/$user_id/wireguard.env"
    local server_public_key
    server_public_key=$(cat "$WG_CONFIG_DIR/server.pub")

    # Direct WireGuard config
    cat > "$output_dir/wireguard.conf" <<EOF
[Interface]
PrivateKey = $WG_PRIVATE_KEY
Address = $WG_CLIENT_IP/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${SERVER_IP}:${PORT_WIREGUARD:-51820}
PersistentKeepalive = 25
EOF

    # WireGuard-wstunnel config (for censored networks)
    # Points to localhost - user must run wstunnel client first
    cat > "$output_dir/wireguard-wstunnel.conf" <<EOF
[Interface]
PrivateKey = $WG_PRIVATE_KEY
Address = $WG_CLIENT_IP/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 127.0.0.1:51820
PersistentKeepalive = 25
EOF

    log_info "Generated WireGuard client config for $user_id"
}
