#!/bin/bash
# =============================================================================
# MoaV Client Entrypoint
# Handles both test mode and client (connect) mode
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
CONFIG_DIR="${CONFIG_DIR:-/config}"
MODE=""
PROTOCOL="auto"
SOCKS_PORT="${SOCKS_PORT:-1080}"
HTTP_PORT="${HTTP_PORT:-8080}"
SERVER_HOST=""
JSON_OUTPUT=false
VERBOSE=false

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
MoaV Client - Multi-protocol circumvention client

USAGE:
    moav-client [OPTIONS] <MODE>

MODES:
    --test              Test connectivity to all services for a user
    --connect           Connect and expose local proxy

OPTIONS:
    -c, --config DIR    Path to user bundle directory (default: /config)
    -p, --protocol P    Protocol to use (default: auto)
                        Options: auto, reality, trojan, hysteria2, wireguard,
                                 psiphon, tor, dnstt
    -s, --server HOST   Override server address (default: from config)
    --socks-port PORT   SOCKS5 proxy port (default: 1080)
    --http-port PORT    HTTP proxy port (default: 8080)
    --json              Output results in JSON format (test mode)
    -v, --verbose       Verbose output
    -h, --help          Show this help

PROTOCOL PRIORITY (auto mode):
    1. Reality (VLESS)  - Primary, most stealth
    2. Hysteria2        - Fast UDP-based
    3. Trojan           - Reliable TCP backup
    4. WireGuard        - Via wstunnel (WebSocket)
    5. Psiphon          - Standalone network fallback
    6. Tor/Snowflake    - Ultimate fallback
    7. dnstt            - Last resort (slow but hard to block)

EXAMPLES:
    # Test all services for user 'joe'
    moav-client --test -c /path/to/bundles/joe

    # Connect using auto-detected best protocol
    moav-client --connect -c /path/to/bundles/joe

    # Connect using specific protocol
    moav-client --connect -c /path/to/bundles/joe -p reality

    # Test with JSON output
    moav-client --test -c /path/to/bundles/joe --json

EOF
}

# =============================================================================
# Logging
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

# =============================================================================
# Parse Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --test)
                MODE="test"
                shift
                ;;
            --connect)
                MODE="connect"
                shift
                ;;
            -c|--config)
                CONFIG_DIR="$2"
                shift 2
                ;;
            -p|--protocol)
                PROTOCOL="$2"
                shift 2
                ;;
            -s|--server)
                SERVER_HOST="$2"
                shift 2
                ;;
            --socks-port)
                SOCKS_PORT="$2"
                shift 2
                ;;
            --http-port)
                HTTP_PORT="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate mode
    if [[ -z "$MODE" ]]; then
        log_error "Mode required: --test or --connect"
        show_help
        exit 1
    fi

    # Validate config directory
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "Config directory not found: $CONFIG_DIR"
        exit 1
    fi

    # Export for sub-scripts
    export CONFIG_DIR PROTOCOL SOCKS_PORT HTTP_PORT SERVER_HOST JSON_OUTPUT VERBOSE
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    log_info "MoaV Client starting..."
    log_info "Config directory: $CONFIG_DIR"
    log_info "Mode: $MODE"
    log_info "Protocol: $PROTOCOL"

    case "$MODE" in
        test)
            exec /app/client-test.sh
            ;;
        connect)
            exec /app/client-connect.sh
            ;;
        *)
            log_error "Invalid mode: $MODE"
            exit 1
            ;;
    esac
}

main "$@"
