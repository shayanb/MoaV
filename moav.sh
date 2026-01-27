#!/bin/bash
# =============================================================================
# MoaV Management Script
# Interactive CLI for managing the MoaV circumvention stack
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║                                                    ║"
    echo "║  ███╗   ███╗ ██████╗  █████╗ ██╗   ██╗             ║"
    echo "║  ████╗ ████║██╔═══██╗██╔══██╗██║   ██║             ║"
    echo "║  ██╔████╔██║██║   ██║███████║██║   ██║             ║"
    echo "║  ██║╚██╔╝██║██║   ██║██╔══██║╚██╗ ██╔╝             ║"
    echo "║  ██║ ╚═╝ ██║╚██████╔╝██║  ██║ ╚████╔╝              ║"
    echo "║  ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝  ╚═══╝               ║"
    echo "║                                                    ║"
    echo "║           Mother of all VPNs                       ║"
    echo "║                                                    ║"
    echo "║  Multi-protocol Circumvention Stack                ║"
    echo "║                                                    ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  $1${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

prompt() {
    echo -e "${CYAN}?${NC} $1"
}

confirm() {
    local message="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        prompt "$message [Y/n]: "
    else
        prompt "$message [y/N]: "
    fi

    read -r response
    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

press_enter() {
    echo ""
    echo -e "${DIM}Press Enter to continue...${NC}"
    read -r
}

run_command() {
    local cmd="$1"
    local description="${2:-Running command}"

    echo ""
    echo -e "${DIM}Command:${NC}"
    echo -e "${WHITE}  $cmd${NC}"
    echo ""

    if confirm "Execute this command?"; then
        echo ""
        eval "$cmd"
        return $?
    else
        warn "Command cancelled"
        return 1
    fi
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    local missing=0

    print_section "Checking Prerequisites"

    # Check Docker
    if command -v docker &> /dev/null; then
        success "Docker is installed"
    else
        error "Docker is not installed"
        echo "  Install from: https://docs.docker.com/get-docker/"
        missing=1
    fi

    # Check Docker Compose
    if docker compose version &> /dev/null; then
        success "Docker Compose is installed"
    else
        error "Docker Compose is not installed"
        echo "  Install from: https://docs.docker.com/compose/install/"
        missing=1
    fi

    # Check .env file
    if [[ -f ".env" ]]; then
        success ".env file exists"
    else
        warn ".env file not found"
        if [[ -f ".env.example" ]]; then
            if confirm "Copy .env.example to .env?"; then
                cp .env.example .env
                success "Created .env from .env.example"
                warn "Please edit .env with your settings before continuing"
                echo ""
                echo -e "${YELLOW}Required settings:${NC}"
                echo "  - DOMAIN: Your domain name"
                echo "  - ACME_EMAIL: Email for Let's Encrypt"
                echo "  - ADMIN_PASSWORD: Password for admin dashboard"
                echo ""
                if confirm "Open .env in editor now?" "y"; then
                    ${EDITOR:-nano} .env
                fi
            else
                missing=1
            fi
        else
            error ".env.example not found"
            missing=1
        fi
    fi

    # Check if Docker is running
    if docker info &> /dev/null; then
        success "Docker daemon is running"
    else
        error "Docker daemon is not running"
        echo "  Start Docker and try again"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        echo ""
        error "Prerequisites check failed. Please fix the issues above."
        exit 1
    fi

    success "All prerequisites met!"
}

check_bootstrap() {
    # Check if bootstrap has been run by looking for state directory contents
    if docker volume ls | grep -q "moav_moav_state"; then
        # Volume exists, check if it has been initialized
        local has_keys=$(docker run --rm -v moav_moav_state:/state alpine sh -c "ls /state/keys 2>/dev/null | wc -l" 2>/dev/null || echo "0")
        if [[ "$has_keys" -gt 0 ]]; then
            return 0  # Bootstrap has been run
        fi
    fi
    return 1  # Bootstrap needed
}

run_bootstrap() {
    print_section "First-Time Setup (Bootstrap)"

    info "Bootstrap will:"
    echo "  • Generate encryption keys"
    echo "  • Obtain TLS certificate from Let's Encrypt"
    echo "  • Create initial users"
    echo "  • Generate client configuration bundles"
    echo ""

    warn "Make sure your domain DNS is configured correctly!"
    echo "  Your domain should point to this server's IP address."
    echo ""

    if confirm "Run bootstrap now?" "y"; then
        echo ""
        info "Building bootstrap container..."
        docker compose --profile setup build bootstrap

        echo ""
        info "Running bootstrap..."
        docker compose --profile setup run --rm bootstrap

        echo ""
        success "Bootstrap completed!"
        echo ""
        info "User bundles have been created in: outputs/bundles/"
        echo "  Each bundle contains configuration files and QR codes"
        echo "  for connecting to your server."
    else
        warn "Bootstrap skipped. You'll need to run it before starting services."
        return 1
    fi
}

# =============================================================================
# Service Management
# =============================================================================

get_running_services() {
    docker compose ps --services --filter "status=running" 2>/dev/null || echo ""
}

show_status() {
    print_section "Service Status"

    docker compose --profile all ps

    echo ""
    info "To view logs: docker compose logs -t -f [service]"
    info "To stop all:  docker compose --profile all down"
}

select_profiles() {
    local selected_profiles=()

    print_section "Select Services to Start"

    echo "Available service profiles:"
    echo ""
    echo -e "  ${WHITE}1)${NC} proxy      - sing-box (Reality, Trojan, Hysteria2) + decoy website"
    echo -e "  ${WHITE}2)${NC} wireguard  - WireGuard VPN via wstunnel"
    echo -e "  ${WHITE}3)${NC} dnstt      - DNS tunnel (last resort)"
    echo -e "  ${WHITE}4)${NC} admin      - Stats dashboard (port 9443)"
    echo -e "  ${WHITE}5)${NC} conduit    - Psiphon bandwidth donation"
    echo -e "  ${WHITE}6)${NC} snowflake  - Tor Snowflake bandwidth donation"
    echo ""
    echo -e "  ${WHITE}a)${NC} ALL        - Start all services"
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Enter choices (e.g., 1 2 4 or 'a' for all): "
    read -r choices </dev/tty

    if [[ "$choices" == "0" || -z "$choices" ]]; then
        return 1
    fi

    if [[ "$choices" == "a" || "$choices" == "A" ]]; then
        selected_profiles=("all")
    else
        for choice in $choices; do
            case $choice in
                1) selected_profiles+=("proxy") ;;
                2) selected_profiles+=("wireguard") ;;
                3) selected_profiles+=("dnstt") ;;
                4) selected_profiles+=("admin") ;;
                5) selected_profiles+=("conduit") ;;
                6) selected_profiles+=("snowflake") ;;
            esac
        done
    fi

    if [[ ${#selected_profiles[@]} -eq 0 ]]; then
        warn "No profiles selected"
        return 1
    fi

    # Build profile string and store in global variable
    SELECTED_PROFILE_STRING=""
    for p in "${selected_profiles[@]}"; do
        SELECTED_PROFILE_STRING+="--profile $p "
    done

    return 0
}

start_services() {
    print_section "Start Services"

    echo "How would you like to start services?"
    echo ""
    echo -e "  ${WHITE}1)${NC} Start ALL services"
    echo -e "  ${WHITE}2)${NC} Select specific services"
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice

    local profiles=""

    case $choice in
        1)
            profiles="--profile all"
            ;;
        2)
            SELECTED_PROFILE_STRING=""
            select_profiles || return 1
            profiles="$SELECTED_PROFILE_STRING"
            ;;
        0|*)
            return 1
            ;;
    esac

    if [[ -z "$profiles" ]]; then
        warn "No profiles selected"
        return 1
    fi

    echo ""
    info "Building containers (if needed)..."

    local cmd="docker compose $profiles up -d"

    if run_command "$cmd" "Starting services"; then
        echo ""
        success "Services started!"
        echo ""
        show_log_help
    fi
}

stop_services() {
    print_section "Stop Services"

    echo "What would you like to stop?"
    echo ""
    echo -e "  ${WHITE}1)${NC} Stop ALL services"
    echo -e "  ${WHITE}2)${NC} Stop specific service"
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice

    case $choice in
        1)
            run_command "docker compose --profile all down" "Stopping all services"
            ;;
        2)
            echo ""
            prompt "Enter service name (e.g., sing-box, conduit): "
            read -r service
            if [[ -n "$service" ]]; then
                run_command "docker compose stop $service" "Stopping $service"
            fi
            ;;
        0|*)
            return 1
            ;;
    esac
}

restart_services() {
    print_section "Restart Services"

    echo "What would you like to restart?"
    echo ""
    echo -e "  ${WHITE}1)${NC} Restart ALL services"
    echo -e "  ${WHITE}2)${NC} Restart specific service"
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice

    case $choice in
        1)
            run_command "docker compose --profile all restart" "Restarting all services"
            ;;
        2)
            echo ""
            prompt "Enter service name (e.g., sing-box, conduit): "
            read -r service
            if [[ -n "$service" ]]; then
                run_command "docker compose restart $service" "Restarting $service"
            fi
            ;;
        0|*)
            return 1
            ;;
    esac
}

view_logs() {
    print_section "View Logs"

    echo "Which logs would you like to view?"
    echo ""
    echo -e "  ${WHITE}1)${NC} All services (follow)"
    echo -e "  ${WHITE}2)${NC} Specific service"
    echo -e "  ${WHITE}3)${NC} Last 100 lines (all services)"
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice

    case $choice in
        1)
            echo ""
            info "Showing logs for all services. Press Ctrl+C to exit."
            echo ""
            docker compose --profile all logs -t -f
            ;;
        2)
            echo ""
            prompt "Enter service name (e.g., sing-box, conduit, snowflake): "
            read -r service
            if [[ -n "$service" ]]; then
                echo ""
                info "Showing logs for $service. Press Ctrl+C to exit."
                echo ""
                docker compose logs -t -f "$service"
            fi
            ;;
        3)
            docker compose --profile all logs -t --tail=100
            ;;
        0|*)
            return 1
            ;;
    esac
}

show_log_help() {
    echo -e "${CYAN}Log Commands:${NC}"
    echo "  • View all logs:      docker compose logs -t -f"
    echo "  • View service logs:  docker compose logs -t -f sing-box"
    echo "  • Last 100 lines:     docker compose logs -t --tail=100"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  • Check status:       docker compose ps"
    echo "  • Stop all:           docker compose --profile all down"
    echo "  • Restart service:    docker compose restart sing-box"
}

# =============================================================================
# User Management
# =============================================================================

user_management() {
    print_section "User Management"

    echo "User management options:"
    echo ""
    echo -e "  ${WHITE}1)${NC} List all users"
    echo -e "  ${WHITE}2)${NC} Add new user"
    echo -e "  ${WHITE}3)${NC} Revoke user"
    echo -e "  ${WHITE}0)${NC} Back to main menu"
    echo ""

    prompt "Choice: "
    read -r choice

    case $choice in
        1)
            list_users
            ;;
        2)
            add_user
            ;;
        3)
            revoke_user
            ;;
        0|*)
            return 0
            ;;
    esac
}

list_users() {
    print_section "User List"

    if [[ -x "./scripts/user-list.sh" ]]; then
        ./scripts/user-list.sh
    else
        # Fallback: list from outputs/bundles
        if [[ -d "outputs/bundles" ]]; then
            echo "Users with bundles:"
            ls -1 outputs/bundles/ 2>/dev/null || echo "  No users found"
        else
            warn "No users found. Run bootstrap first."
        fi
    fi
}

add_user() {
    print_section "Add New User"

    prompt "Enter username for new user: "
    read -r username

    if [[ -z "$username" ]]; then
        warn "Username cannot be empty"
        return 1
    fi

    # Validate username (alphanumeric and underscore only)
    if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        error "Username can only contain letters, numbers, and underscores"
        return 1
    fi

    echo ""
    echo "This will add '$username' to:"
    echo "  • sing-box (Reality, Trojan, Hysteria2)"
    echo "  • WireGuard"
    echo ""

    if [[ -x "./scripts/user-add.sh" ]]; then
        run_command "./scripts/user-add.sh $username" "Adding user $username"

        if [[ $? -eq 0 ]]; then
            echo ""
            success "User '$username' created!"
            echo ""
            info "Bundle location: outputs/bundles/$username/"
            echo "  Share this bundle securely with the user."
        fi
    else
        error "User add script not found: ./scripts/user-add.sh"
        return 1
    fi
}

revoke_user() {
    print_section "Revoke User"

    echo "Current users:"
    list_users
    echo ""

    prompt "Enter username to revoke: "
    read -r username

    if [[ -z "$username" ]]; then
        warn "Username cannot be empty"
        return 1
    fi

    echo ""
    warn "This will revoke '$username' from ALL services!"
    echo ""

    if [[ -x "./scripts/user-revoke.sh" ]]; then
        if confirm "Are you sure you want to revoke '$username'?"; then
            run_command "./scripts/user-revoke.sh $username" "Revoking user $username"

            if [[ $? -eq 0 ]]; then
                echo ""
                success "User '$username' revoked!"
            fi
        fi
    else
        error "User revoke script not found: ./scripts/user-revoke.sh"
        return 1
    fi
}

# =============================================================================
# Build Management
# =============================================================================

build_services() {
    print_section "Build Services"

    echo "Build options:"
    echo ""
    echo -e "  ${WHITE}1)${NC} Build all services"
    echo -e "  ${WHITE}2)${NC} Build all (no cache)"
    echo -e "  ${WHITE}3)${NC} Build specific service"
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice

    case $choice in
        1)
            run_command "docker compose --profile all build" "Building all services"
            ;;
        2)
            run_command "docker compose --profile all build --no-cache" "Building all services (no cache)"
            ;;
        3)
            echo ""
            prompt "Enter service name (e.g., sing-box, conduit): "
            read -r service
            if [[ -n "$service" ]]; then
                run_command "docker compose build $service" "Building $service"
            fi
            ;;
        0|*)
            return 1
            ;;
    esac
}

# =============================================================================
# Main Menu
# =============================================================================

main_menu() {
    while true; do
        print_header

        # Show quick status
        local running=$(get_running_services)
        if [[ -n "$running" ]]; then
            echo -e "  ${GREEN}●${NC} Services running: $(echo $running | wc -w)"
        else
            echo -e "  ${DIM}○ No services running${NC}"
        fi
        echo ""

        echo "  What would you like to do?"
        echo ""
        echo -e "  ${WHITE}1)${NC} Start services"
        echo -e "  ${WHITE}2)${NC} Stop services"
        echo -e "  ${WHITE}3)${NC} Restart services"
        echo -e "  ${WHITE}4)${NC} View status"
        echo -e "  ${WHITE}5)${NC} View logs"
        echo ""
        echo -e "  ${WHITE}6)${NC} User management"
        echo -e "  ${WHITE}7)${NC} Build/rebuild services"
        echo ""
        echo -e "  ${WHITE}0)${NC} Exit"
        echo ""

        prompt "Choice: "
        read -r choice

        case $choice in
            1) start_services; press_enter ;;
            2) stop_services; press_enter ;;
            3) restart_services; press_enter ;;
            4) show_status; press_enter ;;
            5) view_logs ;;
            6) user_management; press_enter ;;
            7) build_services; press_enter ;;
            0|q|Q)
                echo ""
                info "Goodbye!"
                exit 0
                ;;
            *)
                warn "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Command Line Interface
# =============================================================================

show_usage() {
    echo "Usage: ./moav.sh [command] [options]"
    echo ""
    echo "Commands:"
    echo "  (no command)     Interactive menu"
    echo "  help             Show this help message"
    echo "  check            Run prerequisites check"
    echo "  bootstrap        Run first-time setup"
    echo "  start [PROFILE]  Start services (default: all)"
    echo "  stop             Stop all services"
    echo "  restart          Restart all services"
    echo "  status           Show service status"
    echo "  logs [SERVICE]   View logs (default: all, follow mode)"
    echo "  users            List all users"
    echo "  user add NAME    Add a new user"
    echo "  user revoke NAME Revoke a user"
    echo "  build            Build all services"
    echo ""
    echo "Profiles: proxy, wireguard, dnstt, admin, conduit, snowflake, all"
    echo ""
    echo "Examples:"
    echo "  ./moav.sh                    # Interactive menu"
    echo "  ./moav.sh start              # Start all services"
    echo "  ./moav.sh start proxy admin  # Start proxy and admin"
    echo "  ./moav.sh logs sing-box      # View sing-box logs"
    echo "  ./moav.sh user add john      # Add user 'john'"
}

cmd_check() {
    print_header
    check_prerequisites
}

cmd_bootstrap() {
    print_header
    check_prerequisites
    echo ""
    run_bootstrap
}

cmd_start() {
    local profiles=""
    if [[ $# -eq 0 ]]; then
        profiles="--profile all"
    else
        for p in "$@"; do
            profiles+="--profile $p "
        done
    fi

    info "Starting services..."
    docker compose $profiles up -d
    success "Services started!"
    echo ""
    docker compose $profiles ps
}

cmd_stop() {
    info "Stopping all services..."
    docker compose --profile all down
    success "Services stopped!"
}

cmd_restart() {
    info "Restarting all services..."
    docker compose --profile all restart
    success "Services restarted!"
}

cmd_status() {
    docker compose --profile all ps
}

cmd_logs() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        docker compose logs -t -f "$service"
    else
        docker compose --profile all logs -t -f
    fi
}

cmd_users() {
    list_users
}

cmd_user() {
    local action="${1:-}"
    local username="${2:-}"

    case "$action" in
        add)
            if [[ -z "$username" ]]; then
                error "Usage: ./moav.sh user add USERNAME"
                exit 1
            fi
            if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
                error "Username can only contain letters, numbers, and underscores"
                exit 1
            fi
            if [[ -x "./scripts/user-add.sh" ]]; then
                ./scripts/user-add.sh "$username"
            else
                error "User add script not found"
                exit 1
            fi
            ;;
        revoke)
            if [[ -z "$username" ]]; then
                error "Usage: ./moav.sh user revoke USERNAME"
                exit 1
            fi
            if [[ -x "./scripts/user-revoke.sh" ]]; then
                ./scripts/user-revoke.sh "$username"
            else
                error "User revoke script not found"
                exit 1
            fi
            ;;
        *)
            error "Usage: ./moav.sh user [add|revoke] USERNAME"
            exit 1
            ;;
    esac
}

cmd_build() {
    info "Building all services..."
    docker compose --profile all build
    success "Build complete!"
}

# =============================================================================
# Entry Point
# =============================================================================

# Track if prerequisites have been checked this session
PREREQS_CHECKED=false

main_interactive() {
    print_header

    # Check prerequisites only once per session
    if [[ "$PREREQS_CHECKED" != "true" ]]; then
        check_prerequisites
        PREREQS_CHECKED=true
        echo ""
    fi

    # Check if bootstrap needed
    if ! check_bootstrap; then
        warn "Bootstrap has not been run yet!"
        echo ""
        info "Bootstrap is required for first-time setup."
        echo "  It generates keys, obtains TLS certificates, and creates users."
        echo ""

        if confirm "Run bootstrap now?" "y"; then
            run_bootstrap || exit 1
            press_enter
        else
            warn "You can run bootstrap later from the main menu"
            warn "or manually with: docker compose --profile setup run --rm bootstrap"
            press_enter
        fi
    fi

    # Show main menu
    main_menu
}

main() {
    local cmd="${1:-}"

    case "$cmd" in
        "")
            main_interactive
            ;;
        help|--help|-h)
            show_usage
            ;;
        check)
            cmd_check
            ;;
        bootstrap)
            cmd_bootstrap
            ;;
        start)
            shift
            cmd_start "$@"
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        status)
            cmd_status
            ;;
        logs)
            shift
            cmd_logs "$@"
            ;;
        users)
            cmd_users
            ;;
        user)
            shift
            cmd_user "$@"
            ;;
        build)
            cmd_build
            ;;
        *)
            error "Unknown command: $cmd"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
