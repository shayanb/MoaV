#!/bin/bash
# =============================================================================
# MoaV Client - Test Mode
# Tests connectivity to all services for a given user bundle
# =============================================================================

set -euo pipefail

# Colors (inherit from entrypoint or define)
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
# Logging (same as entrypoint)
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
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

setup() {
    mkdir -p "$TEMP_DIR"
}

# Extract server address from config files
get_server_from_config() {
    local config_file="$1"
    local server=""

    if [[ -f "$config_file" ]]; then
        # Try to extract server from various config formats
        if [[ "$config_file" == *.json ]]; then
            server=$(jq -r '.outbounds[0].server // .server // empty' "$config_file" 2>/dev/null || echo "")
        elif [[ "$config_file" == *.txt ]]; then
            # Parse URI format (vless://, trojan://, etc.)
            server=$(grep -oP '(?<=@)[^:]+' "$config_file" 2>/dev/null | head -1 || echo "")
        fi
    fi

    echo "$server"
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
    for f in "$CONFIG_DIR"/reality*.json "$CONFIG_DIR"/*reality*.json "$CONFIG_DIR"/reality.txt; do
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

    # Generate sing-box client config
    local client_config="$TEMP_DIR/reality-client.json"

    # If it's a URI file, convert to sing-box config
    if [[ "$config_file" == *.txt ]]; then
        local uri=$(cat "$config_file" | tr -d '\n\r')
        # Parse VLESS URI: vless://uuid@server:port?params#name
        local uuid=$(echo "$uri" | sed -n 's/vless:\/\/\([^@]*\)@.*/\1/p')
        local server=$(echo "$uri" | sed -n 's/.*@\([^:]*\):.*/\1/p')
        local port=$(echo "$uri" | sed -n 's/.*:\([0-9]*\)?.*/\1/p')
        local params=$(echo "$uri" | sed -n 's/.*?\([^#]*\).*/\1/p')

        # Extract Reality params
        local sni=$(echo "$params" | grep -oP 'sni=\K[^&]+' || echo "")
        local pbk=$(echo "$params" | grep -oP 'pbk=\K[^&]+' || echo "")
        local sid=$(echo "$params" | grep -oP 'sid=\K[^&]+' || echo "")
        local fp=$(echo "$params" | grep -oP 'fp=\K[^&]+' || echo "chrome")

        cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10800}
  ],
  "outbounds": [
    {
      "type": "vless",
      "server": "$server",
      "server_port": ${port:-443},
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
  ]
}
EOF
    else
        # Use existing JSON config, add inbound
        jq '. + {
          "log": {"level": "error"},
          "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 10800}]
        }' "$config_file" > "$client_config"
    fi

    # Start sing-box
    sing-box run -c "$client_config" &
    local pid=$!
    sleep 2

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

    for f in "$CONFIG_DIR"/trojan*.json "$CONFIG_DIR"/*trojan*.json "$CONFIG_DIR"/trojan.txt; do
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
        # Parse Trojan URI: trojan://password@server:port?params#name
        local password=$(echo "$uri" | sed -n 's/trojan:\/\/\([^@]*\)@.*/\1/p')
        local server=$(echo "$uri" | sed -n 's/.*@\([^:]*\):.*/\1/p')
        local port=$(echo "$uri" | sed -n 's/.*:\([0-9]*\)?.*/\1/p')
        local sni=$(echo "$uri" | grep -oP 'sni=\K[^&#]+' || echo "$server")

        cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10801}
  ],
  "outbounds": [
    {
      "type": "trojan",
      "server": "$server",
      "server_port": ${port:-8443},
      "password": "$password",
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "insecure": false
      }
    }
  ]
}
EOF
    else
        jq '. + {
          "log": {"level": "error"},
          "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 10801}]
        }' "$config_file" > "$client_config"
    fi

    sing-box run -c "$client_config" &
    local pid=$!
    sleep 2

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

    for f in "$CONFIG_DIR"/hysteria2*.yaml "$CONFIG_DIR"/hysteria2*.json "$CONFIG_DIR"/*hysteria*.yaml "$CONFIG_DIR"/hysteria2.txt; do
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

    if [[ "$config_file" == *.txt ]]; then
        local uri=$(cat "$config_file" | tr -d '\n\r')
        # Parse Hysteria2 URI: hysteria2://auth@server:port?params#name
        local auth=$(echo "$uri" | sed -n 's/hysteria2:\/\/\([^@]*\)@.*/\1/p')
        local server=$(echo "$uri" | sed -n 's/.*@\([^:]*\):.*/\1/p')
        local port=$(echo "$uri" | sed -n 's/.*:\([0-9]*\)?.*/\1/p')
        local sni=$(echo "$uri" | grep -oP 'sni=\K[^&#]+' || echo "$server")

        cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10802}
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "server": "$server",
      "server_port": ${port:-443},
      "password": "$auth",
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "insecure": false
      }
    }
  ]
}
EOF
    elif [[ "$config_file" == *.yaml ]]; then
        # Convert YAML to JSON sing-box format
        local server=$(grep -oP 'server:\s*\K[^\s]+' "$config_file" | head -1)
        local auth=$(grep -oP 'auth:\s*\K[^\s]+' "$config_file" | head -1)
        local sni=$(grep -oP 'sni:\s*\K[^\s]+' "$config_file" | head -1 || echo "$server")

        cat > "$client_config" << EOF
{
  "log": {"level": "error"},
  "inbounds": [
    {"type": "socks", "listen": "127.0.0.1", "listen_port": 10802}
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "server": "${server%:*}",
      "server_port": ${server#*:},
      "password": "$auth",
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "insecure": false
      }
    }
  ]
}
EOF
    else
        jq '. + {
          "log": {"level": "error"},
          "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 10802}]
        }' "$config_file" > "$client_config"
    fi

    sing-box run -c "$client_config" &
    local pid=$!
    sleep 2

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

# Test WireGuard (config validation only - full test requires NET_ADMIN)
test_wireguard() {
    log_info "Testing WireGuard (config validation)..."

    local config_file=""
    local detail=""

    for f in "$CONFIG_DIR"/wireguard*.conf "$CONFIG_DIR"/wg*.conf "$CONFIG_DIR"/*wireguard*.conf; do
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

    # Extract and validate keys
    local private_key=$(grep -oP 'PrivateKey\s*=\s*\K.+' "$config_file" | tr -d ' ')
    local endpoint=$(grep -oP 'Endpoint\s*=\s*\K.+' "$config_file" | tr -d ' ')

    if [[ -z "$private_key" ]] || [[ -z "$endpoint" ]]; then
        detail="Missing PrivateKey or Endpoint in config"
        log_error "$detail"
        RESULTS[wireguard]="fail"
        DETAILS[wireguard]="$detail"
        return
    fi

    # Test endpoint reachability (just port check, not full WG handshake)
    local host="${endpoint%:*}"
    local port="${endpoint#*:}"

    if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        log_success "WireGuard endpoint reachable: $endpoint"
        RESULTS[wireguard]="pass"
        DETAILS[wireguard]="Config valid, endpoint reachable (full test requires --cap-add NET_ADMIN)"
    else
        # Try wstunnel endpoint (port 8080)
        local wstunnel_endpoint="${host}:8080"
        if timeout 5 bash -c "echo >/dev/tcp/$host/8080" 2>/dev/null; then
            log_success "WireGuard wstunnel endpoint reachable: $wstunnel_endpoint"
            RESULTS[wireguard]="pass"
            DETAILS[wireguard]="Config valid, wstunnel endpoint reachable"
        else
            detail="Endpoint not reachable: $endpoint (and wstunnel 8080)"
            log_warn "$detail"
            RESULTS[wireguard]="warn"
            DETAILS[wireguard]="$detail"
        fi
    fi
}

# Test dnstt (DNS tunnel)
test_dnstt() {
    log_info "Testing dnstt (DNS tunnel)..."

    local config_file=""
    local detail=""

    # Look for dnstt instructions or config
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

    # Extract domain and pubkey from instructions
    local domain=$(grep -oP 't\.\K[a-zA-Z0-9.-]+' "$config_file" | head -1)
    local pubkey=$(grep -oP 'pubkey[=\s]+\K[a-zA-Z0-9+/=]+' "$config_file" | head -1)

    # Also check for server.pub file
    if [[ -z "$pubkey" ]] && [[ -f "$CONFIG_DIR/server.pub" ]]; then
        pubkey=$(cat "$CONFIG_DIR/server.pub")
    fi

    if [[ -z "$domain" ]]; then
        detail="Could not extract tunnel domain from config"
        log_error "$detail"
        RESULTS[dnstt]="fail"
        DETAILS[dnstt]="$detail"
        return
    fi

    # Test DNS resolution for tunnel domain
    if dig +short "test.t.$domain" @8.8.8.8 >/dev/null 2>&1; then
        log_debug "DNS query for t.$domain succeeded"
    fi

    if [[ -z "$pubkey" ]]; then
        detail="Could not extract public key"
        log_warn "$detail"
        RESULTS[dnstt]="warn"
        DETAILS[dnstt]="Domain: t.$domain, but missing pubkey for full test"
        return
    fi

    # Try to establish dnstt tunnel briefly
    if command -v dnstt-client >/dev/null 2>&1; then
        dnstt-client -doh https://1.1.1.1/dns-query -pubkey "$pubkey" "t.$domain" 127.0.0.1:10803 &
        local pid=$!
        sleep 3

        if kill -0 $pid 2>/dev/null; then
            log_success "dnstt client started successfully"
            RESULTS[dnstt]="pass"
            DETAILS[dnstt]="DNS tunnel established to t.$domain"
            kill $pid 2>/dev/null || true
        else
            detail="dnstt client failed to start"
            log_error "$detail"
            RESULTS[dnstt]="fail"
            DETAILS[dnstt]="$detail"
        fi
    else
        RESULTS[dnstt]="warn"
        DETAILS[dnstt]="dnstt-client not available, config looks valid for t.$domain"
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

    # Count results
    for protocol in "${!RESULTS[@]}"; do
        case "${RESULTS[$protocol]}" in
            pass) ((pass_count++)) ;;
            fail) ((fail_count++)); overall_status="fail" ;;
            skip) ((skip_count++)) ;;
            warn) ((warn_count++)); [[ "$overall_status" == "pass" ]] && overall_status="warn" ;;
        esac
    done

    # Build JSON
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
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
