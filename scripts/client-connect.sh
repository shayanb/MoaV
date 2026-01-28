#!/bin/bash
# =============================================================================
# MoaV Client - Connect Mode
# Connects to MoaV server and exposes local SOCKS5/HTTP proxy
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration (from environment, set by entrypoint)
CONFIG_DIR="${CONFIG_DIR:-/config}"
PROTOCOL="${PROTOCOL:-auto}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
HTTP_PORT="${HTTP_PORT:-8080}"
TEST_URL="${TEST_URL:-https://www.google.com/generate_204}"
TEST_TIMEOUT="${TEST_TIMEOUT:-10}"

# Protocol priority for auto mode
PROTOCOL_PRIORITY=(reality hysteria2 trojan wireguard psiphon tor dnstt)

# State
CURRENT_PID=""
CURRENT_PROTOCOL=""

# =============================================================================
# Logging
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $1" || true; }

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    log_info "Shutting down..."
    [[ -n "$CURRENT_PID" ]] && kill "$CURRENT_PID" 2>/dev/null || true
    rm -rf /tmp/moav-client-*
    exit 0
}
trap cleanup SIGTERM SIGINT

# =============================================================================
# Protocol Connection Functions
# =============================================================================

# Portable URL parameter extraction (no grep -P)
extract_param() {
    local uri="$1"
    local param="$2"
    echo "$uri" | sed -n "s/.*[?&]${param}=\([^&#]*\).*/\1/p" | head -1
}

# Extract value before @ in URI
extract_auth() {
    local uri="$1"
    local protocol="$2"
    echo "$uri" | sed -n "s|${protocol}://\([^@]*\)@.*|\1|p" | head -1
}

# Extract host from URI (between @ and :port or ?)
extract_host() {
    local uri="$1"
    echo "$uri" | sed -n 's|.*@\([^:]*\):.*|\1|p' | head -1
}

# Extract port from URI
extract_port() {
    local uri="$1"
    echo "$uri" | sed -n 's|.*:\([0-9]*\)[?#].*|\1|p' | head -1
}

# Generate sing-box client config for proxy protocols
generate_singbox_config() {
    local protocol="$1"
    local output_file="$2"
    local config_file=""

    # Find config file
    case "$protocol" in
        reality)
            for f in "$CONFIG_DIR"/reality*.json "$CONFIG_DIR"/reality*.txt; do
                [[ -f "$f" ]] && config_file="$f" && break
            done
            ;;
        trojan)
            for f in "$CONFIG_DIR"/trojan*.json "$CONFIG_DIR"/trojan*.txt; do
                [[ -f "$f" ]] && config_file="$f" && break
            done
            ;;
        hysteria2)
            for f in "$CONFIG_DIR"/hysteria2*.yaml "$CONFIG_DIR"/hysteria2*.json "$CONFIG_DIR"/hysteria2*.txt; do
                [[ -f "$f" ]] && config_file="$f" && break
            done
            ;;
        wireguard)
            for f in "$CONFIG_DIR"/wireguard*.conf "$CONFIG_DIR"/wg*.conf; do
                [[ -f "$f" ]] && config_file="$f" && break
            done
            ;;
    esac

    if [[ -z "$config_file" ]]; then
        return 1
    fi

    log_debug "Generating config from: $config_file"

    # Base config with inbounds
    local inbounds='[
        {"type": "socks", "tag": "socks-in", "listen": "0.0.0.0", "listen_port": '"$SOCKS_PORT"'},
        {"type": "http", "tag": "http-in", "listen": "0.0.0.0", "listen_port": '"$HTTP_PORT"'}
    ]'

    # Parse and generate outbound based on protocol and file type
    case "$protocol" in
        reality)
            if [[ "$config_file" == *.txt ]]; then
                local uri=$(cat "$config_file" | tr -d '\n\r')
                local uuid=$(extract_auth "$uri" "vless")
                local server=$(extract_host "$uri")
                local port=$(extract_port "$uri")
                local sni=$(extract_param "$uri" "sni")
                local pbk=$(extract_param "$uri" "pbk")
                local sid=$(extract_param "$uri" "sid")
                local fp=$(extract_param "$uri" "fp")

                [[ -z "$fp" ]] && fp="chrome"
                [[ -z "$port" ]] && port="443"

                cat > "$output_file" << EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": $inbounds,
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "$server",
      "server_port": $port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "utls": {"enabled": true, "fingerprint": "$fp"},
        "reality": {
          "enabled": true,
          "public_key": "$pbk",
          "short_id": "$sid"
        }
      }
    }
  ],
  "route": {"final": "proxy"}
}
EOF
            else
                jq --argjson inbounds "$inbounds" '. + {"inbounds": $inbounds, "log": {"level": "info", "timestamp": true}, "route": {"final": "proxy"}}' "$config_file" > "$output_file"
            fi
            ;;

        trojan)
            if [[ "$config_file" == *.txt ]]; then
                local uri=$(cat "$config_file" | tr -d '\n\r')
                local password=$(extract_auth "$uri" "trojan")
                local server=$(extract_host "$uri")
                local port=$(extract_port "$uri")
                local sni=$(extract_param "$uri" "sni")

                [[ -z "$sni" ]] && sni="$server"
                [[ -z "$port" ]] && port="8443"

                cat > "$output_file" << EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": $inbounds,
  "outbounds": [
    {
      "type": "trojan",
      "tag": "proxy",
      "server": "$server",
      "server_port": $port,
      "password": "$password",
      "tls": {
        "enabled": true,
        "server_name": "$sni"
      }
    }
  ],
  "route": {"final": "proxy"}
}
EOF
            else
                jq --argjson inbounds "$inbounds" '. + {"inbounds": $inbounds, "log": {"level": "info", "timestamp": true}, "route": {"final": "proxy"}}' "$config_file" > "$output_file"
            fi
            ;;

        hysteria2)
            local server="" auth="" sni=""

            if [[ "$config_file" == *.txt ]]; then
                local uri=$(cat "$config_file" | tr -d '\n\r')
                auth=$(extract_auth "$uri" "hysteria2")
                server=$(echo "$uri" | sed -n 's|.*@\([^?#]*\).*|\1|p' | head -1)
                sni=$(extract_param "$uri" "sni")
            elif [[ "$config_file" == *.yaml ]] || [[ "$config_file" == *.yml ]]; then
                server=$(grep -E "^server:" "$config_file" | sed 's/server:[[:space:]]*//' | tr -d '"' | head -1)
                auth=$(grep -E "^auth:" "$config_file" | sed 's/auth:[[:space:]]*//' | tr -d '"' | head -1)
                sni=$(grep -E "^[[:space:]]*sni:" "$config_file" | sed 's/.*sni:[[:space:]]*//' | tr -d '"' | head -1)
            fi

            local host="${server%:*}"
            local port="${server##*:}"
            [[ "$port" == "$host" ]] && port=443
            [[ -z "$sni" ]] && sni="$host"

            cat > "$output_file" << EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": $inbounds,
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "$host",
      "server_port": $port,
      "password": "$auth",
      "tls": {
        "enabled": true,
        "server_name": "$sni"
      }
    }
  ],
  "route": {"final": "proxy"}
}
EOF
            ;;

        wireguard)
            # Extract WireGuard config values (case-insensitive, allow whitespace)
            local private_key=$(grep -i "PrivateKey" "$config_file" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d ' \t\r')
            local endpoint=$(grep -i "Endpoint" "$config_file" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d ' \t\r')
            local peer_public_key=$(grep -i "PublicKey" "$config_file" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d ' \t\r')
            local address=$(grep -i "Address" "$config_file" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d ' \t\r' | cut -d',' -f1)

            local server="${endpoint%:*}"
            local port="${endpoint#*:}"

            cat > "$output_file" << EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": $inbounds,
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "proxy",
      "server": "$server",
      "server_port": $port,
      "local_address": ["$address"],
      "private_key": "$private_key",
      "peer_public_key": "$peer_public_key",
      "mtu": 1280
    }
  ],
  "route": {"final": "proxy"}
}
EOF
            ;;
    esac

    return 0
}

# Connect using sing-box (Reality, Trojan, Hysteria2)
connect_singbox() {
    local protocol="$1"
    local config_file="/tmp/moav-client-$protocol.json"

    if ! generate_singbox_config "$protocol" "$config_file"; then
        log_error "Failed to generate config for $protocol"
        return 1
    fi

    log_info "Starting sing-box with $protocol..."
    sing-box run -c "$config_file" &
    CURRENT_PID=$!
    CURRENT_PROTOCOL="$protocol"

    sleep 2

    if ! kill -0 $CURRENT_PID 2>/dev/null; then
        log_error "sing-box failed to start"
        return 1
    fi

    # Test connection
    sleep 1
    if curl -sf --socks5 127.0.0.1:$SOCKS_PORT --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        return 0
    else
        log_warn "Connection test failed for $protocol"
        kill $CURRENT_PID 2>/dev/null || true
        CURRENT_PID=""
        return 1
    fi
}

# Connect using WireGuard via sing-box
connect_wireguard() {
    local config_file="/tmp/moav-client-wireguard.json"

    if ! generate_singbox_config "wireguard" "$config_file"; then
        log_error "Failed to generate config for wireguard"
        return 1
    fi

    log_info "Starting sing-box with WireGuard..."
    sing-box run -c "$config_file" &
    CURRENT_PID=$!
    CURRENT_PROTOCOL="wireguard"

    sleep 3

    if ! kill -0 $CURRENT_PID 2>/dev/null; then
        log_error "sing-box failed to start WireGuard tunnel"
        return 1
    fi

    # Test connection
    if curl -sf --socks5 127.0.0.1:$SOCKS_PORT --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        return 0
    else
        log_warn "Connection test failed for wireguard"
        kill $CURRENT_PID 2>/dev/null || true
        CURRENT_PID=""
        return 1
    fi
}

# Connect using dnstt
connect_dnstt() {
    local config_file=""

    for f in "$CONFIG_DIR"/dnstt*.txt "$CONFIG_DIR"/*dnstt*; do
        [[ -f "$f" ]] && config_file="$f" && break
    done

    if [[ -z "$config_file" ]]; then
        log_error "No dnstt config found"
        return 1
    fi

    # Extract domain - look for t.domain.com pattern (portable)
    local domain=$(grep -oE 't\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$config_file" | head -1)

    # Extract pubkey from config file (portable)
    local pubkey=$(grep -i "pubkey" "$config_file" | sed 's/.*[=:][[:space:]]*//' | grep -oE '[A-Za-z0-9+/=]{40,}' | head -1)

    # Check for server.pub in bundle
    [[ -z "$pubkey" ]] && [[ -f "$CONFIG_DIR/server.pub" ]] && pubkey=$(cat "$CONFIG_DIR/server.pub" | tr -d '\n\r')

    # Check for server.pub in default dnstt outputs location (mounted at /dnstt)
    [[ -z "$pubkey" ]] && [[ -f "/dnstt/server.pub" ]] && pubkey=$(cat "/dnstt/server.pub" | tr -d '\n\r')

    if [[ -z "$domain" ]] || [[ -z "$pubkey" ]]; then
        log_error "Could not extract dnstt domain or pubkey"
        return 1
    fi

    log_info "Starting dnstt client for $domain..."

    dnstt-client -doh https://1.1.1.1/dns-query -pubkey "$pubkey" "$domain" 127.0.0.1:$SOCKS_PORT &
    CURRENT_PID=$!
    CURRENT_PROTOCOL="dnstt"

    sleep 3

    if ! kill -0 $CURRENT_PID 2>/dev/null; then
        log_error "dnstt-client failed to start"
        return 1
    fi

    log_success "dnstt tunnel established"
    return 0
}

# Connect using Psiphon (standalone, doesn't need MoaV server)
connect_psiphon() {
    if ! command -v psiphon-client >/dev/null 2>&1; then
        log_error "psiphon-client not available"
        return 1
    fi

    log_info "Starting Psiphon client..."
    log_info "Note: Psiphon connects to its own network, not your MoaV server"

    # Create minimal Psiphon config
    local psiphon_config="/tmp/moav-psiphon-config.json"
    cat > "$psiphon_config" << EOF
{
    "LocalSocksProxyPort": $SOCKS_PORT,
    "LocalHttpProxyPort": $HTTP_PORT,
    "PropagationChannelId": "FFFFFFFFFFFFFFFF",
    "SponsorId": "FFFFFFFFFFFFFFFF"
}
EOF

    psiphon-client -config "$psiphon_config" &
    CURRENT_PID=$!
    CURRENT_PROTOCOL="psiphon"

    sleep 5

    if ! kill -0 $CURRENT_PID 2>/dev/null; then
        log_error "Psiphon client failed to start"
        return 1
    fi

    # Test connection
    if curl -sf --socks5 127.0.0.1:$SOCKS_PORT --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        return 0
    else
        log_warn "Psiphon connection not ready yet, continuing..."
        return 0  # Psiphon may take time to establish
    fi
}

# Connect using Tor with Snowflake
connect_tor() {
    log_info "Starting Tor with Snowflake bridge..."
    log_info "Note: Tor connects to its own network, not your MoaV server"

    # Create torrc with Snowflake
    local torrc="/tmp/moav-torrc"
    cat > "$torrc" << EOF
SocksPort 0.0.0.0:$SOCKS_PORT
DataDirectory /tmp/tor-data
UseBridges 1
ClientTransportPlugin snowflake exec /usr/local/bin/snowflake-client -url https://snowflake-broker.torproject.net.global.prod.fastly.net/ -front cdn.sstatic.net -ice stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478,stun:stun.altar.com.pl:3478,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,stun:stun.sonetel.net:3478,stun:stun.stunprotocol.org:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478
Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net.global.prod.fastly.net/ front=cdn.sstatic.net ice=stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478,stun:stun.altar.com.pl:3478,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,stun:stun.sonetel.net:3478,stun:stun.stunprotocol.org:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478 utls-imitate=hellorandomizedalpn
EOF

    mkdir -p /tmp/tor-data
    chmod 700 /tmp/tor-data

    tor -f "$torrc" &
    CURRENT_PID=$!
    CURRENT_PROTOCOL="tor"

    log_info "Waiting for Tor to bootstrap (this may take a while)..."
    sleep 10

    if ! kill -0 $CURRENT_PID 2>/dev/null; then
        log_error "Tor failed to start"
        return 1
    fi

    # Wait for bootstrap
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if curl -sf --socks5 127.0.0.1:$SOCKS_PORT --max-time 5 "$TEST_URL" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        ((attempts++))
    done

    log_warn "Tor may still be bootstrapping..."
    return 0
}

# =============================================================================
# Auto Mode - Try protocols in order
# =============================================================================

connect_auto() {
    log_info "Auto mode: trying protocols in priority order..."

    for protocol in "${PROTOCOL_PRIORITY[@]}"; do
        log_info "Trying $protocol..."

        case "$protocol" in
            reality|trojan|hysteria2)
                if connect_singbox "$protocol"; then
                    log_success "Connected via $protocol"
                    return 0
                fi
                ;;
            wireguard)
                if connect_wireguard; then
                    log_success "Connected via WireGuard"
                    return 0
                fi
                ;;
            psiphon)
                if connect_psiphon; then
                    log_success "Connected via Psiphon"
                    return 0
                fi
                ;;
            tor)
                if connect_tor; then
                    log_success "Connected via Tor/Snowflake"
                    return 0
                fi
                ;;
            dnstt)
                if connect_dnstt; then
                    log_success "Connected via dnstt"
                    return 0
                fi
                ;;
        esac

        log_warn "$protocol failed, trying next..."
    done

    log_error "All protocols failed!"
    return 1
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  MoaV Client - Connect Mode"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Config:     $CONFIG_DIR"
    echo "  Protocol:   $PROTOCOL"
    echo "  SOCKS5:     0.0.0.0:$SOCKS_PORT"
    echo "  HTTP:       0.0.0.0:$HTTP_PORT"
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo ""

    local connected=false

    case "$PROTOCOL" in
        auto)
            connect_auto && connected=true
            ;;
        reality|trojan|hysteria2)
            connect_singbox "$PROTOCOL" && connected=true
            ;;
        wireguard)
            connect_wireguard && connected=true
            ;;
        psiphon)
            connect_psiphon && connected=true
            ;;
        tor)
            connect_tor && connected=true
            ;;
        dnstt)
            connect_dnstt && connected=true
            ;;
        *)
            log_error "Unknown protocol: $PROTOCOL"
            exit 1
            ;;
    esac

    if [[ "$connected" != "true" ]]; then
        log_error "Failed to establish connection"
        exit 1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "  ${GREEN}Connected!${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Protocol:   $CURRENT_PROTOCOL"
    echo "  SOCKS5:     localhost:$SOCKS_PORT"
    echo "  HTTP:       localhost:$HTTP_PORT"
    echo ""
    echo "  Configure your browser/apps to use one of these proxies."
    echo "  Press Ctrl+C to disconnect."
    echo ""
    echo "───────────────────────────────────────────────────────────────"

    # Keep running
    wait $CURRENT_PID
}

main
