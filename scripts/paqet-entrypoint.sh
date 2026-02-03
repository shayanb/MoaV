#!/bin/bash
# =============================================================================
# Paqet Server Entrypoint
# Auto-detects network configuration and starts paqet server
# =============================================================================

set -euo pipefail

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[paqet]${NC} $1"; }
log_success() { echo -e "${GREEN}[paqet]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[paqet]${NC} $1"; }
log_error() { echo -e "${RED}[paqet]${NC} $1"; }

# =============================================================================
# VPS Compatibility Check
# =============================================================================
check_vps_compatibility() {
    log_info "Checking VPS compatibility..."

    # Check for OpenVZ (doesn't support raw sockets)
    if [[ -f /proc/user_beancounters ]]; then
        log_error "OpenVZ detected - raw sockets not supported!"
        log_error "Paqet requires KVM, Xen, or bare metal servers."
        exit 1
    fi

    # Check for LXC/container environment
    if [[ -f /proc/1/environ ]] && grep -q "container=" /proc/1/environ 2>/dev/null; then
        log_warn "Container environment detected - raw sockets may not work"
    fi

    # Test raw socket capability
    if ! capsh --print 2>/dev/null | grep -q "cap_net_raw"; then
        # Try alternative check
        if [[ ! -w /dev/net/tun ]] && [[ "$(id -u)" != "0" ]]; then
            log_warn "May not have raw socket capabilities"
        fi
    fi

    log_success "VPS compatibility check passed"
}

# =============================================================================
# Network Auto-Detection
# =============================================================================
detect_interface() {
    # Find the default route interface
    local iface=$(ip route | grep default | awk '{print $5}' | head -1)

    if [[ -z "$iface" ]]; then
        # Fallback: find first non-lo interface with an IP
        iface=$(ip -o -4 addr show | grep -v ' lo ' | awk '{print $2}' | head -1)
    fi

    echo "$iface"
}

detect_server_ip() {
    local iface="$1"
    ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1
}

detect_gateway_ip() {
    ip route | grep default | awk '{print $3}' | head -1
}

detect_gateway_mac() {
    local gateway_ip="$1"

    # Ping gateway to ensure ARP entry exists
    ping -c 1 -W 1 "$gateway_ip" >/dev/null 2>&1 || true

    # Get MAC from ARP table
    local mac=$(ip neigh show "$gateway_ip" 2>/dev/null | awk '{print $5}' | head -1)

    # Fallback to arp command
    if [[ -z "$mac" ]] || [[ "$mac" == "FAILED" ]]; then
        mac=$(arp -n "$gateway_ip" 2>/dev/null | tail -1 | awk '{print $3}')
    fi

    echo "$mac"
}

# =============================================================================
# iptables Setup
# =============================================================================
setup_iptables() {
    local port="$1"

    log_info "Setting up iptables rules for port $port..."

    # Check if rules already exist
    if iptables -t raw -C PREROUTING -p tcp --dport "$port" -j NOTRACK 2>/dev/null; then
        log_info "iptables rules already configured"
        return 0
    fi

    # Bypass connection tracking (essential for paqet)
    iptables -t raw -A PREROUTING -p tcp --dport "$port" -j NOTRACK || log_warn "Failed to add PREROUTING NOTRACK rule"
    iptables -t raw -A OUTPUT -p tcp --sport "$port" -j NOTRACK || log_warn "Failed to add OUTPUT NOTRACK rule"

    # Prevent kernel from sending RST packets
    iptables -t mangle -A OUTPUT -p tcp --sport "$port" --tcp-flags RST RST -j DROP || log_warn "Failed to add RST DROP rule"

    # Allow traffic on the port
    iptables -t filter -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    iptables -t filter -A OUTPUT -p tcp --sport "$port" -j ACCEPT 2>/dev/null || true

    log_success "iptables rules configured"
}

# =============================================================================
# Configuration Generation
# =============================================================================
generate_config() {
    local config_file="$1"
    local interface="$2"
    local server_ip="$3"
    local gateway_mac="$4"
    local port="$5"
    local key="$6"

    log_info "Generating paqet server configuration..."

    cat > "$config_file" <<EOF
# Paqet Server Configuration (auto-generated)
role: "server"

log:
  level: "${PAQET_LOG_LEVEL:-info}"

listen:
  addr: ":${port}"

network:
  interface: "${interface}"
  ipv4:
    addr: "${server_ip}:${port}"
    router_mac: "${gateway_mac}"

transport:
  protocol: "kcp"
  conn: 1
  kcp:
    mode: "${PAQET_KCP_MODE:-fast}"
    block: "${PAQET_ENCRYPTION:-aes}"
    key: "${key}"
EOF

    log_success "Configuration generated: $config_file"
}

# =============================================================================
# Main
# =============================================================================
main() {
    log_info "Starting Paqet server..."

    # Configuration
    PORT="${PAQET_PORT:-9999}"
    CONFIG_FILE="/etc/paqet/server.yaml"
    KEY_FILE="/state/keys/paqet.key"

    # Check VPS compatibility
    check_vps_compatibility

    # Load or generate key
    if [[ -f "$KEY_FILE" ]]; then
        PAQET_KEY=$(cat "$KEY_FILE")
        log_info "Loaded encryption key from $KEY_FILE"
    else
        log_error "No encryption key found at $KEY_FILE"
        log_error "Run bootstrap first: docker compose --profile setup run --rm bootstrap"
        exit 1
    fi

    # Auto-detect network configuration
    log_info "Auto-detecting network configuration..."

    INTERFACE=$(detect_interface)
    if [[ -z "$INTERFACE" ]]; then
        log_error "Could not detect network interface"
        exit 1
    fi
    log_info "  Interface: $INTERFACE"

    SERVER_IP=$(detect_server_ip "$INTERFACE")
    if [[ -z "$SERVER_IP" ]]; then
        log_error "Could not detect server IP"
        exit 1
    fi
    log_info "  Server IP: $SERVER_IP"

    GATEWAY_IP=$(detect_gateway_ip)
    if [[ -z "$GATEWAY_IP" ]]; then
        log_error "Could not detect gateway IP"
        exit 1
    fi
    log_info "  Gateway IP: $GATEWAY_IP"

    GATEWAY_MAC=$(detect_gateway_mac "$GATEWAY_IP")
    if [[ -z "$GATEWAY_MAC" ]] || [[ "$GATEWAY_MAC" == "(incomplete)" ]]; then
        log_error "Could not detect gateway MAC address"
        log_error "Try setting PAQET_GATEWAY_MAC environment variable"
        exit 1
    fi
    log_info "  Gateway MAC: $GATEWAY_MAC"

    # Setup iptables
    setup_iptables "$PORT"

    # Generate configuration
    mkdir -p "$(dirname "$CONFIG_FILE")"
    generate_config "$CONFIG_FILE" "$INTERFACE" "$SERVER_IP" "$GATEWAY_MAC" "$PORT" "$PAQET_KEY"

    # Display config for debugging
    if [[ "${PAQET_DEBUG:-false}" == "true" ]]; then
        log_info "Configuration:"
        cat "$CONFIG_FILE"
    fi

    log_success "Starting paqet server on port $PORT..."
    exec paqet run -c "$CONFIG_FILE"
}

main "$@"
