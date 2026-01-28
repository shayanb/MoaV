#!/bin/bash
# =============================================================================
# MoaV Client - Test Mode
# Tests connectivity to all services for a given user bundle
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test configuration
TEST_URL="${TEST_URL:-https://www.google.com/generate_204}"
TEST_TIMEOUT="${TEST_TIMEOUT:-10}"
TEMP_DIR="/tmp/moav-test-$$"

# Results storage
declare -A RESULTS
declare -A DETAILS

# =============================================================================
# Logging
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_debug() { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $1" >&2 || true; }

# =============================================================================
# Utility Functions
# =============================================================================

cleanup() {
    log_debug "Cleaning up..."
    jobs -p | xargs -r kill 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

setup() {
    mkdir -p "$TEMP_DIR"
}

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

# =============================================================================
# Test Functions
# =============================================================================

# Test Reality (VLESS) protocol
test_reality() {
    log_info "Testing Reality (VLESS)..."

    local config_file=""
    local result="skip"
    local detail=""

    # Find Reality config
    for f in "$CONFIG_DIR"/reality*.txt "$CONFIG_DIR"/reality*.json; do
        [[ -f "$f" ]] && config_file="$f" && break
    done

    if [[ -z "$config_file" ]]; then
        detail="No Reality config found in bundle"
        log_warn "$detail"
        RESULTS[reality]="skip"
        DETAILS[reality]="$detail"
        return
    fi

    log_debug "Using config: $config_file"

    local client_config="$TEMP_DIR/reality-client.json"

    if [[ "$config_file" == *.txt ]]; then
        local uri=$(cat "$config_file" | tr -d '\n\r')

        # Parse VLESS URI using portable methods
        local uuid=$(extract_auth "$uri" "vless")
        local server=$(extract_host "$uri")
        local port=$(extract_port "$uri")
        local sni=$(extract_param "$uri" "sni")
        local pbk=$(extract_param "$uri" "pbk")
        local sid=$(extract_param "$uri" "sid")
        local fp=$(extract_param "$uri" "fp")

        [[ -z "$fp" ]] && fp="chrome"
        [[ -z "$port" ]] && port="443"

        log_debug "Parsed: server=$server port=$port uuid=$uuid sni=$sni"

        # Generate sing-box 1.12+ compatible config
        cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10800}
  ],
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
  "route": {
    "final": "proxy"
  }
}
EOF
    else
        # JSON config - wrap with inbounds
        jq '. + {
          "log": {"level": "error"},
          "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 10800}],
          "route": {"final": "proxy"}
        }' "$config_file" > "$client_config" 2>/dev/null || {
            detail="Failed to parse JSON config"
            log_error "$detail"
            RESULTS[reality]="fail"
            DETAILS[reality]="$detail"
            return
        }
    fi

    log_debug "Generated config: $(cat "$client_config")"

    # Start sing-box
    sing-box run -c "$client_config" &
    local pid=$!
    sleep 3

    if ! kill -0 $pid 2>/dev/null; then
        detail="sing-box failed to start"
        log_error "$detail"
        RESULTS[reality]="fail"
        DETAILS[reality]="$detail"
        return
    fi

    # Test connection
    if curl -sf --socks5 127.0.0.1:10800 --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        log_success "Reality connection successful"
        RESULTS[reality]="pass"
        DETAILS[reality]="Connected via VLESS/Reality"
    else
        detail="Connection test failed (timeout or rejected)"
        log_error "$detail"
        RESULTS[reality]="fail"
        DETAILS[reality]="$detail"
    fi

    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

# Test Trojan protocol
test_trojan() {
    log_info "Testing Trojan..."

    local config_file=""
    local detail=""

    for f in "$CONFIG_DIR"/trojan*.txt "$CONFIG_DIR"/trojan*.json; do
        [[ -f "$f" ]] && config_file="$f" && break
    done

    if [[ -z "$config_file" ]]; then
        detail="No Trojan config found in bundle"
        log_warn "$detail"
        RESULTS[trojan]="skip"
        DETAILS[trojan]="$detail"
        return
    fi

    log_debug "Using config: $config_file"

    local client_config="$TEMP_DIR/trojan-client.json"

    if [[ "$config_file" == *.txt ]]; then
        local uri=$(cat "$config_file" | tr -d '\n\r')

        local password=$(extract_auth "$uri" "trojan")
        local server=$(extract_host "$uri")
        local port=$(extract_port "$uri")
        local sni=$(extract_param "$uri" "sni")

        [[ -z "$sni" ]] && sni="$server"
        [[ -z "$port" ]] && port="8443"

        cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10801}
  ],
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
  "route": {
    "final": "proxy"
  }
}
EOF
    else
        jq '. + {
          "log": {"level": "error"},
          "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 10801}],
          "route": {"final": "proxy"}
        }' "$config_file" > "$client_config" 2>/dev/null || {
            detail="Failed to parse JSON config"
            log_error "$detail"
            RESULTS[trojan]="fail"
            DETAILS[trojan]="$detail"
            return
        }
    fi

    sing-box run -c "$client_config" &
    local pid=$!
    sleep 3

    if ! kill -0 $pid 2>/dev/null; then
        detail="sing-box failed to start"
        log_error "$detail"
        RESULTS[trojan]="fail"
        DETAILS[trojan]="$detail"
        return
    fi

    if curl -sf --socks5 127.0.0.1:10801 --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        log_success "Trojan connection successful"
        RESULTS[trojan]="pass"
        DETAILS[trojan]="Connected via Trojan"
    else
        detail="Connection test failed"
        log_error "$detail"
        RESULTS[trojan]="fail"
        DETAILS[trojan]="$detail"
    fi

    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

# Test Hysteria2 protocol
test_hysteria2() {
    log_info "Testing Hysteria2..."

    local config_file=""
    local detail=""

    for f in "$CONFIG_DIR"/hysteria2*.yaml "$CONFIG_DIR"/hysteria2*.yml "$CONFIG_DIR"/hysteria2*.txt; do
        [[ -f "$f" ]] && config_file="$f" && break
    done

    if [[ -z "$config_file" ]]; then
        detail="No Hysteria2 config found in bundle"
        log_warn "$detail"
        RESULTS[hysteria2]="skip"
        DETAILS[hysteria2]="$detail"
        return
    fi

    log_debug "Using config: $config_file"

    local client_config="$TEMP_DIR/hysteria2-client.json"
    local server="" auth="" sni="" host="" port=""

    if [[ "$config_file" == *.txt ]]; then
        local uri=$(cat "$config_file" | tr -d '\n\r')
        auth=$(extract_auth "$uri" "hysteria2")
        # For hysteria2, server might include port
        server=$(echo "$uri" | sed -n 's|.*@\([^?#]*\).*|\1|p' | head -1)
        sni=$(extract_param "$uri" "sni")
    elif [[ "$config_file" == *.yaml ]] || [[ "$config_file" == *.yml ]]; then
        server=$(grep -E "^server:" "$config_file" | sed 's/server:[[:space:]]*//' | tr -d '"' | head -1)
        auth=$(grep -E "^auth:" "$config_file" | sed 's/auth:[[:space:]]*//' | tr -d '"' | head -1)
        sni=$(grep -E "^[[:space:]]*sni:" "$config_file" | sed 's/.*sni:[[:space:]]*//' | tr -d '"' | head -1)
    fi

    # Parse host:port
    if echo "$server" | grep -q ':'; then
        host="${server%:*}"
        port="${server##*:}"
    else
        host="$server"
        port="443"
    fi

    [[ -z "$sni" ]] && sni="$host"

    log_debug "Parsed: host=$host port=$port auth=$auth sni=$sni"

    if [[ -z "$host" ]] || [[ -z "$auth" ]]; then
        detail="Could not parse Hysteria2 config"
        log_error "$detail"
        RESULTS[hysteria2]="fail"
        DETAILS[hysteria2]="$detail"
        return
    fi

    cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10802}
  ],
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
  "route": {
    "final": "proxy"
  }
}
EOF

    log_debug "Generated config: $(cat "$client_config")"

    sing-box run -c "$client_config" &
    local pid=$!
    sleep 3

    if ! kill -0 $pid 2>/dev/null; then
        detail="sing-box failed to start"
        log_error "$detail"
        RESULTS[hysteria2]="fail"
        DETAILS[hysteria2]="$detail"
        return
    fi

    if curl -sf --socks5 127.0.0.1:10802 --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        log_success "Hysteria2 connection successful"
        RESULTS[hysteria2]="pass"
        DETAILS[hysteria2]="Connected via Hysteria2"
    else
        detail="Connection test failed"
        log_error "$detail"
        RESULTS[hysteria2]="fail"
        DETAILS[hysteria2]="$detail"
    fi

    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

# Test WireGuard via sing-box
test_wireguard() {
    log_info "Testing WireGuard..."

    local config_file=""
    local detail=""

    for f in "$CONFIG_DIR"/wireguard*.conf "$CONFIG_DIR"/wg*.conf; do
        [[ -f "$f" ]] && config_file="$f" && break
    done

    if [[ -z "$config_file" ]]; then
        detail="No WireGuard config found in bundle"
        log_warn "$detail"
        RESULTS[wireguard]="skip"
        DETAILS[wireguard]="$detail"
        return
    fi

    log_debug "Using config: $config_file"

    # Validate config structure
    if ! grep -q "\[Interface\]" "$config_file" || ! grep -q "\[Peer\]" "$config_file"; then
        detail="Invalid WireGuard config format"
        log_error "$detail"
        RESULTS[wireguard]="fail"
        DETAILS[wireguard]="$detail"
        return
    fi

    # Extract values using portable grep/sed
    local private_key=$(grep -E "^PrivateKey" "$config_file" | sed 's/.*=[[:space:]]*//' | tr -d ' ')
    local endpoint=$(grep -E "^Endpoint" "$config_file" | sed 's/.*=[[:space:]]*//' | tr -d ' ')
    local peer_public_key=$(grep -E "^PublicKey" "$config_file" | sed 's/.*=[[:space:]]*//' | tr -d ' ')
    local address=$(grep -E "^Address" "$config_file" | sed 's/.*=[[:space:]]*//' | tr -d ' ' | cut -d',' -f1)
    local dns=$(grep -E "^DNS" "$config_file" | sed 's/.*=[[:space:]]*//' | tr -d ' ' | cut -d',' -f1)
    local allowed_ips=$(grep -E "^AllowedIPs" "$config_file" | sed 's/.*=[[:space:]]*//' | tr -d ' ')

    if [[ -z "$private_key" ]] || [[ -z "$endpoint" ]] || [[ -z "$peer_public_key" ]]; then
        detail="Missing required fields in WireGuard config"
        log_error "$detail"
        RESULTS[wireguard]="fail"
        DETAILS[wireguard]="$detail"
        return
    fi

    # Parse endpoint
    local server="${endpoint%:*}"
    local port="${endpoint#*:}"

    # Extract local address without CIDR
    local local_address="${address%/*}"

    log_debug "Parsed: server=$server port=$port peer_pubkey=${peer_public_key:0:20}..."

    # Generate sing-box config for WireGuard
    local client_config="$TEMP_DIR/wireguard-client.json"

    cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10804}
  ],
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
  "route": {
    "final": "proxy"
  }
}
EOF

    log_debug "Generated config: $(cat "$client_config")"

    # Start sing-box
    sing-box run -c "$client_config" &
    local pid=$!
    sleep 3

    if ! kill -0 $pid 2>/dev/null; then
        detail="sing-box failed to start WireGuard tunnel"
        log_error "$detail"
        RESULTS[wireguard]="fail"
        DETAILS[wireguard]="$detail"
        return
    fi

    # Test connection
    if curl -sf --socks5 127.0.0.1:10804 --max-time "$TEST_TIMEOUT" "$TEST_URL" >/dev/null 2>&1; then
        log_success "WireGuard connection successful"
        RESULTS[wireguard]="pass"
        DETAILS[wireguard]="Connected via WireGuard"
    else
        detail="Connection test failed (tunnel established but no traffic)"
        log_error "$detail"
        RESULTS[wireguard]="fail"
        DETAILS[wireguard]="$detail"
    fi

    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

# Test dnstt (DNS tunnel)
test_dnstt() {
    log_info "Testing dnstt (DNS tunnel)..."

    local config_file=""
    local detail=""

    for f in "$CONFIG_DIR"/dnstt*.txt "$CONFIG_DIR"/*dnstt*; do
        [[ -f "$f" ]] && config_file="$f" && break
    done

    if [[ -z "$config_file" ]]; then
        detail="No dnstt config found in bundle"
        log_warn "$detail"
        RESULTS[dnstt]="skip"
        DETAILS[dnstt]="$detail"
        return
    fi

    log_debug "Using config: $config_file"

    # Extract domain - look for t.domain.com pattern
    local domain=$(grep -oE 't\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$config_file" | head -1)

    # Extract pubkey - look for base64-like string after "pubkey"
    local pubkey=$(grep -i "pubkey" "$config_file" | sed 's/.*[=:][[:space:]]*//' | grep -oE '[A-Za-z0-9+/=]{40,}' | head -1)

    # Check for server.pub file in bundle
    if [[ -z "$pubkey" ]] && [[ -f "$CONFIG_DIR/server.pub" ]]; then
        pubkey=$(cat "$CONFIG_DIR/server.pub" | tr -d '\n\r')
        log_debug "Found pubkey in bundle: server.pub"
    fi

    # Check for server.pub in default dnstt outputs location (mounted at /dnstt)
    if [[ -z "$pubkey" ]] && [[ -f "/dnstt/server.pub" ]]; then
        pubkey=$(cat "/dnstt/server.pub" | tr -d '\n\r')
        log_debug "Found pubkey in /dnstt/server.pub"
    fi

    if [[ -z "$domain" ]]; then
        detail="Could not extract tunnel domain from config"
        log_error "$detail"
        RESULTS[dnstt]="fail"
        DETAILS[dnstt]="$detail"
        return
    fi

    log_debug "Parsed: domain=$domain pubkey=${pubkey:0:20}..."

    if [[ -z "$pubkey" ]]; then
        detail="Could not extract public key (check outputs/dnstt/server.pub)"
        log_warn "$detail"
        RESULTS[dnstt]="warn"
        DETAILS[dnstt]="Domain: $domain, but missing pubkey for full test"
        return
    fi

    # Try to establish dnstt tunnel briefly
    if command -v dnstt-client >/dev/null 2>&1; then
        log_debug "Starting dnstt-client..."
        dnstt-client -doh https://1.1.1.1/dns-query -pubkey "$pubkey" "$domain" 127.0.0.1:10803 &
        local pid=$!
        sleep 5

        if kill -0 $pid 2>/dev/null; then
            log_success "dnstt client started successfully"
            RESULTS[dnstt]="pass"
            DETAILS[dnstt]="DNS tunnel established to $domain"
            kill $pid 2>/dev/null || true
        else
            detail="dnstt client failed to start"
            log_error "$detail"
            RESULTS[dnstt]="fail"
            DETAILS[dnstt]="$detail"
        fi
    else
        RESULTS[dnstt]="warn"
        DETAILS[dnstt]="dnstt-client not available, config looks valid for $domain"
    fi
}

# =============================================================================
# Output Functions
# =============================================================================

output_json() {
    local overall_status="pass"
    local pass_count=0
    local fail_count=0
    local skip_count=0
    local warn_count=0

    for protocol in "${!RESULTS[@]}"; do
        case "${RESULTS[$protocol]}" in
            pass) ((pass_count++)) ;;
            fail) ((fail_count++)); overall_status="fail" ;;
            skip) ((skip_count++)) ;;
            warn) ((warn_count++)); [[ "$overall_status" == "pass" ]] && overall_status="warn" ;;
        esac
    done

    cat << EOF
{
  "timestamp": "$(date -Iseconds 2>/dev/null || date)",
  "config_dir": "$CONFIG_DIR",
  "overall_status": "$overall_status",
  "summary": {
    "pass": $pass_count,
    "fail": $fail_count,
    "warn": $warn_count,
    "skip": $skip_count
  },
  "tests": {
EOF

    local first=true
    for protocol in reality trojan hysteria2 wireguard dnstt; do
        if [[ -n "${RESULTS[$protocol]:-}" ]]; then
            [[ "$first" != "true" ]] && echo ","
            first=false
            cat << EOF
    "$protocol": {
      "status": "${RESULTS[$protocol]}",
      "detail": "${DETAILS[$protocol]:-}"
    }
EOF
        fi
    done

    cat << EOF

  }
}
EOF
}

output_human() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  MoaV Connection Test Results"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Config: $CONFIG_DIR"
    echo "  Time:   $(date)"
    echo ""
    echo "───────────────────────────────────────────────────────────────"

    for protocol in reality trojan hysteria2 wireguard dnstt; do
        if [[ -n "${RESULTS[$protocol]:-}" ]]; then
            local status="${RESULTS[$protocol]}"
            local detail="${DETAILS[$protocol]:-}"
            local icon=""
            local color=""

            case "$status" in
                pass) icon="✓"; color="$GREEN" ;;
                fail) icon="✗"; color="$RED" ;;
                warn) icon="⚠"; color="$YELLOW" ;;
                skip) icon="○"; color="$CYAN" ;;
            esac

            printf "  ${color}${icon}${NC} %-12s %s\n" "$protocol" "$detail"
        fi
    done

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    log_info "Starting connectivity tests..."
    log_info "Config directory: $CONFIG_DIR"
    echo ""

    # Run all tests
    test_reality
    test_trojan
    test_hysteria2
    test_wireguard
    test_dnstt

    # Output results
    if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
        output_json
    else
        output_human
    fi
}

main
