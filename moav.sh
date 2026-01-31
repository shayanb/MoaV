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

# Get script directory (resolve symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    # If relative symlink, resolve relative to symlink directory
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
cd "$SCRIPT_DIR"

# Version
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "dev")

# Component versions (read from .env or use defaults)
get_component_version() {
    local var_name="$1"
    local default="$2"
    local env_file="$SCRIPT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        local val
        val=$(grep "^${var_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        [[ -n "$val" ]] && echo "$val" && return
    fi
    echo "$default"
}

# State file for persistent checks
PREREQS_FILE="$SCRIPT_DIR/.moav_prereqs_ok"

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
    printf "║  %-49s ║\n" "v${VERSION}"
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

    # Read single character from /dev/tty to work when stdin is piped
    local response
    if read -n 1 -r response < /dev/tty 2>/dev/null; then
        echo ""  # newline after single-char input
        response=${response:-$default}
    else
        echo ""
        response="$default"
    fi

    if [[ "$default" == "y" ]]; then
        # Default yes: return true unless explicitly 'n' or 'N'
        [[ ! "$response" =~ ^[Nn]$ ]]
    else
        # Default no: return true only if 'y' or 'Y'
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

press_enter() {
    echo ""
    echo -e "${DIM}Press Enter to continue...${NC}"
    read -r < /dev/tty 2>/dev/null || true
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

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]] || [[ -f /etc/fedora-release ]]; then
        echo "rhel"
    elif [[ -f /etc/alpine-release ]]; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

install_docker() {
    local os_type=$(detect_os)

    case "$os_type" in
        debian|rhel)
            info "Installing Docker using official install script..."
            echo ""
            curl -fsSL https://get.docker.com | sh

            # Add current user to docker group
            sudo usermod -aG docker "$(whoami)" 2>/dev/null || true

            # Start and enable Docker
            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
            sudo systemctl enable docker 2>/dev/null || true

            success "Docker installed"
            echo ""
            warn "You may need to log out and back in for docker group permissions."
            warn "Or run: newgrp docker"
            return 0
            ;;
        macos)
            error "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
            echo "After installing, run this script again."
            return 1
            ;;
        alpine)
            info "Installing Docker via apk..."
            sudo apk add docker docker-compose
            sudo rc-update add docker boot
            sudo service docker start
            success "Docker installed"
            return 0
            ;;
        *)
            error "Cannot auto-install Docker on this OS."
            echo "Please install from: https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac
}

install_qrencode() {
    local os_type=$(detect_os)
    local pkg_manager=""

    # Detect package manager
    case "$os_type" in
        macos)
            if command -v brew &>/dev/null; then
                pkg_manager="brew"
            fi
            ;;
        debian)
            pkg_manager="apt"
            ;;
        rhel)
            if command -v dnf &>/dev/null; then
                pkg_manager="dnf"
            elif command -v yum &>/dev/null; then
                pkg_manager="yum"
            fi
            ;;
        alpine)
            pkg_manager="apk"
            ;;
    esac

    case "$pkg_manager" in
        brew)
            info "Installing qrencode via Homebrew..."
            brew install qrencode
            ;;
        apt)
            info "Installing qrencode via apt..."
            sudo apt update && sudo apt install -y qrencode
            ;;
        dnf)
            info "Installing qrencode via dnf..."
            sudo dnf install -y qrencode
            ;;
        yum)
            info "Installing qrencode via yum..."
            sudo yum install -y qrencode
            ;;
        apk)
            info "Installing qrencode via apk..."
            sudo apk add libqrencode-tools
            ;;
        *)
            error "Could not detect package manager"
            echo "  Please install qrencode manually:"
            echo "    Linux (Debian/Ubuntu): sudo apt install qrencode"
            echo "    Linux (RHEL/Fedora):   sudo dnf install qrencode"
            echo "    macOS:                 brew install qrencode"
            return 1
            ;;
    esac

    if command -v qrencode &>/dev/null; then
        success "qrencode installed successfully"
    else
        error "qrencode installation failed"
        return 1
    fi
}

check_prerequisites() {
    local missing=0

    print_section "Checking Prerequisites"

    # Check Docker
    if command -v docker &> /dev/null; then
        success "Docker is installed"
    else
        warn "Docker is not installed"
        if confirm "Install Docker now?"; then
            if install_docker; then
                success "Docker installed"
            else
                missing=1
            fi
        else
            error "Docker is required"
            echo "  Install from: https://docs.docker.com/get-docker/"
            missing=1
        fi
    fi

    # Check Docker Compose (only if Docker is installed)
    if command -v docker &> /dev/null; then
        if docker compose version &> /dev/null; then
            success "Docker Compose is installed"
        else
            warn "Docker Compose is not installed"
            echo "  Docker Compose plugin is usually included with Docker."
            echo "  If you installed Docker manually, install Compose from:"
            echo "  https://docs.docker.com/compose/install/"
            missing=1
        fi
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
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            success "Docker daemon is running"
        else
            warn "Docker daemon is not running"
            if confirm "Start Docker now?"; then
                info "Starting Docker..."
                sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
                sleep 2
                if docker info &> /dev/null; then
                    success "Docker daemon started"
                else
                    error "Failed to start Docker daemon"
                    echo "  You may need to:"
                    echo "    1. Log out and back in (for group permissions)"
                    echo "    2. Run: sudo systemctl start docker"
                    missing=1
                fi
            else
                error "Docker daemon is required"
                echo "  Start with: sudo systemctl start docker"
                missing=1
            fi
        fi
    fi

    # Check optional dependencies
    if command -v qrencode &> /dev/null; then
        success "qrencode is installed (for QR codes)"
    else
        warn "qrencode not installed (needed for QR codes in user packages)"
        if confirm "Install qrencode now?"; then
            install_qrencode
        else
            echo "  You can install later with:"
            echo "    Linux (Debian/Ubuntu): sudo apt install qrencode"
            echo "    Linux (RHEL/Fedora):   sudo dnf install qrencode"
            echo "    macOS:                 brew install qrencode"
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        echo ""
        error "Prerequisites check failed. Please fix the issues above."
        rm -f "$PREREQS_FILE" 2>/dev/null
        exit 1
    fi

    success "All prerequisites met!"
    # Mark prerequisites as checked
    touch "$PREREQS_FILE"

    # Offer to install globally if not already installed
    if ! is_installed; then
        echo ""
        if confirm "Install 'moav' command globally? (run from anywhere)"; then
            do_install
        fi
    fi
}

prereqs_already_checked() {
    [[ -f "$PREREQS_FILE" ]]
}

# =============================================================================
# Installation
# =============================================================================

INSTALL_PATH="/usr/local/bin/moav"

is_installed() {
    [[ -L "$INSTALL_PATH" ]] && [[ "$(readlink "$INSTALL_PATH")" == "$SCRIPT_DIR/moav.sh" ]]
}

do_install() {
    local script_path="$SCRIPT_DIR/moav.sh"

    echo ""
    info "Installing moav to $INSTALL_PATH"

    # Check if already installed correctly
    if is_installed; then
        success "Already installed at $INSTALL_PATH"
        return 0
    fi

    # Check if something else exists at install path
    if [[ -e "$INSTALL_PATH" ]]; then
        warn "File already exists at $INSTALL_PATH"
        if [[ -L "$INSTALL_PATH" ]]; then
            local current_target
            current_target=$(readlink "$INSTALL_PATH")
            echo "  Current symlink points to: $current_target"
        fi
        if ! confirm "Replace it?"; then
            warn "Installation cancelled"
            return 1
        fi
    fi

    # Need sudo for /usr/local/bin
    if [[ -w "$(dirname "$INSTALL_PATH")" ]]; then
        ln -sf "$script_path" "$INSTALL_PATH"
    else
        info "Requires sudo to create symlink in /usr/local/bin"
        sudo ln -sf "$script_path" "$INSTALL_PATH"
    fi

    if is_installed; then
        success "Installed! You can now run 'moav' from anywhere"
        echo ""
        echo "  Examples:"
        echo "    moav              # Interactive menu"
        echo "    moav start        # Start all services"
        echo "    moav logs conduit # View conduit logs"
    else
        error "Installation failed"
        return 1
    fi
}

do_uninstall() {
    if [[ ! -e "$INSTALL_PATH" ]]; then
        warn "Not installed (no file at $INSTALL_PATH)"
        return 0
    fi

    if [[ -L "$INSTALL_PATH" ]]; then
        info "Removing symlink at $INSTALL_PATH"
        if [[ -w "$(dirname "$INSTALL_PATH")" ]]; then
            rm -f "$INSTALL_PATH"
        else
            sudo rm -f "$INSTALL_PATH"
        fi
        success "Uninstalled"
    else
        error "$INSTALL_PATH is not a symlink, not removing"
        return 1
    fi
}

cmd_update() {
    echo ""
    info "Updating MoaV..."
    echo ""

    # Get the installation directory
    local install_dir="$SCRIPT_DIR"

    # Check if it's a git repository
    if [[ ! -d "$install_dir/.git" ]]; then
        error "Not a git repository: $install_dir"
        echo "  Cannot update - MoaV was not installed via git clone"
        return 1
    fi

    echo -e "  Install directory: ${CYAN}$install_dir${NC}"
    echo ""

    # Show current version/commit
    local current_commit
    current_commit=$(git -C "$install_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo -e "  Current commit: ${YELLOW}$current_commit${NC}"

    # Pull latest changes
    info "Running git pull..."
    if git -C "$install_dir" pull; then
        echo ""
        local new_commit
        new_commit=$(git -C "$install_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        if [[ "$current_commit" == "$new_commit" ]]; then
            success "Already up to date"
        else
            success "Updated: $current_commit → $new_commit"
            echo ""
            echo -e "${YELLOW}Note:${NC} If containers have changed, run: ${WHITE}moav build${NC}"
        fi
    else
        error "Failed to update. Check your network connection or git status."
        return 1
    fi
}

check_bootstrap() {
    # Check if bootstrap has been run by looking for local outputs
    # This is faster than checking docker volumes
    if [[ -d "outputs/bundles" ]] && [[ -n "$(ls -A outputs/bundles 2>/dev/null)" ]]; then
        return 0  # Bootstrap has been run
    fi

    # Fallback: check docker volume (with timeout)
    if docker volume ls 2>/dev/null | grep -q "moav_moav_state"; then
        # Quick check - just see if volume exists and has data
        # Use timeout to prevent hanging
        local has_keys
        has_keys=$(timeout 3 docker run --rm -v moav_moav_state:/state alpine sh -c "ls /state/keys 2>/dev/null | head -1" 2>/dev/null || echo "")
        if [[ -n "$has_keys" ]]; then
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

    # Service selection
    echo ""
    print_section "Service Selection"
    echo "Select which services to build and set as default for 'moav start'."
    echo ""

    if select_profiles "save"; then
        echo ""
        info "Building selected services..."
        docker compose $SELECTED_PROFILE_STRING build

        echo ""
        if confirm "Start services now?" "y"; then
            info "Starting services..."
            docker compose $SELECTED_PROFILE_STRING up -d
            echo ""
            success "Services started!"
            docker compose $SELECTED_PROFILE_STRING ps
        else
            echo ""
            info "You can start services later with: moav start"
        fi
    else
        echo ""
        info "You can select and start services later with: moav start"
    fi
}

# =============================================================================
# Service Management
# =============================================================================

get_running_services() {
    docker compose ps --services --filter "status=running" 2>/dev/null || echo ""
}

show_versions() {
    local singbox_ver wstunnel_ver conduit_ver
    singbox_ver=$(get_component_version "SINGBOX_VERSION" "1.12.17")
    wstunnel_ver=$(get_component_version "WSTUNNEL_VERSION" "10.5.1")
    conduit_ver=$(get_component_version "CONDUIT_VERSION" "1.2.0")

    echo ""
    echo -e "${CYAN}MoaV${NC} v${VERSION}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${WHITE}Component Versions:${NC}"
    echo ""
    echo -e "  ${CYAN}┌──────────────┬──────────┬──────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC} ${WHITE}Component${NC}    ${CYAN}│${NC} ${WHITE}Version${NC}  ${CYAN}│${NC} ${WHITE}Source${NC}                           ${CYAN}│${NC}"
    echo -e "  ${CYAN}├──────────────┼──────────┼──────────────────────────────────┤${NC}"
    printf "  ${CYAN}│${NC} %-12s ${CYAN}│${NC} ${GREEN}%-8s${NC} ${CYAN}│${NC} %-32s ${CYAN}│${NC}\n" "sing-box" "$singbox_ver" "github.com/SagerNet/sing-box"
    printf "  ${CYAN}│${NC} %-12s ${CYAN}│${NC} ${GREEN}%-8s${NC} ${CYAN}│${NC} %-32s ${CYAN}│${NC}\n" "wstunnel" "$wstunnel_ver" "github.com/erebe/wstunnel"
    printf "  ${CYAN}│${NC} %-12s ${CYAN}│${NC} ${GREEN}%-8s${NC} ${CYAN}│${NC} %-32s ${CYAN}│${NC}\n" "conduit" "$conduit_ver" "github.com/Psiphon-Inc/conduit"
    printf "  ${CYAN}│${NC} %-12s ${CYAN}│${NC} ${DIM}%-8s${NC} ${CYAN}│${NC} %-32s ${CYAN}│${NC}\n" "snowflake" "latest" "torproject.org (built from src)"
    printf "  ${CYAN}│${NC} %-12s ${CYAN}│${NC} ${DIM}%-8s${NC} ${CYAN}│${NC} %-32s ${CYAN}│${NC}\n" "dnstt" "latest" "bamsoftware.com (built from src)"
    printf "  ${CYAN}│${NC} %-12s ${CYAN}│${NC} ${DIM}%-8s${NC} ${CYAN}│${NC} %-32s ${CYAN}│${NC}\n" "wireguard" "alpine" "wireguard-tools package"
    echo -e "  ${CYAN}└──────────────┴──────────┴──────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${DIM}Versions can be changed in .env and rebuilt with: moav build${NC}"
    echo ""
}

show_status() {
    # Get service status from docker compose
    local raw_status json_lines
    raw_status=$(docker compose --profile all ps --format json 2>/dev/null)

    if [[ -z "$raw_status" ]] || [[ "$raw_status" == "[]" ]]; then
        print_section "Service Status"
        echo ""
        warn "No services are running"
        echo ""
        return
    fi

    # Handle both JSON array format and NDJSON (one object per line)
    # If it starts with '[', it's a JSON array - split into lines
    if [[ "$raw_status" == "["* ]]; then
        # Convert JSON array to one object per line (split on },{ )
        json_lines=$(echo "$raw_status" | sed 's/^\[//;s/\]$//;s/},{/}\n{/g')
    else
        json_lines="$raw_status"
    fi

    print_section "Service Status"
    echo ""
    echo -e "  ${CYAN}┌────────────┬───────────┬─────────────────────┬──────────────┬───────────┐${NC}"
    echo -e "  ${CYAN}│${NC} ${WHITE}Service${NC}    ${CYAN}│${NC} ${WHITE}Status${NC}    ${CYAN}│${NC} ${WHITE}Created${NC}             ${CYAN}│${NC} ${WHITE}Uptime${NC}       ${CYAN}│${NC} ${WHITE}Ports${NC}     ${CYAN}│${NC}"
    echo -e "  ${CYAN}├────────────┼───────────┼─────────────────────┼──────────────┼───────────┤${NC}"

    # Parse JSON and display each service (using here-string to avoid subshell)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local name state ports health status_str created_at uptime created
        name=$(echo "$line" | grep -o '"Name":"[^"]*"' | head -1 | cut -d'"' -f4)
        state=$(echo "$line" | grep -o '"State":"[^"]*"' | head -1 | cut -d'"' -f4)
        health=$(echo "$line" | grep -o '"Health":"[^"]*"' | head -1 | cut -d'"' -f4)
        status_str=$(echo "$line" | grep -o '"Status":"[^"]*"' | head -1 | cut -d'"' -f4)
        # CreatedAt is a datetime string like "2026-01-28 19:56:32 +0000 UTC"
        created_at=$(echo "$line" | grep -o '"CreatedAt":"[^"]*"' | head -1 | cut -d'"' -f4)
        # Extract ports - use || true to prevent exit on empty Publishers array
        ports=$(echo "$line" | grep -o '"Publishers":\[[^]]*\]' | grep -o '"PublishedPort":[0-9]*' | cut -d':' -f2 | sort -u | grep -v '^0$' | tr '\n' ',' | sed 's/,$//' || true)

        [[ -z "$name" ]] && continue
        name="${name#moav-}"

        # Format created datetime (extract just date and time, remove timezone)
        created="-"
        if [[ -n "$created_at" ]]; then
            # Extract "YYYY-MM-DD HH:MM:SS" from "2026-01-28 19:56:32 +0000 UTC"
            created=$(echo "$created_at" | cut -d' ' -f1,2)
        fi

        # Parse uptime from Status field (e.g., "Up 29 hours", "Up 28 minutes")
        uptime="-"
        if [[ "$state" == "running" ]] && [[ "$status_str" =~ ^Up[[:space:]]+(.*) ]]; then
            uptime="${BASH_REMATCH[1]}"
            # Clean up health status suffix if present (e.g., "28 minutes (healthy)")
            uptime="${uptime%% (*}"
            # Shorten common long phrases to fit column
            uptime="${uptime/About an /~1 }"
            uptime="${uptime/About a /~1 }"
            uptime="${uptime/Less than a /< 1 }"
        fi

        local status_display status_color
        if [[ "$state" == "running" ]]; then
            if [[ "$health" == "healthy" ]] || [[ -z "$health" ]]; then
                status_color="${GREEN}"
                status_display="● running"
            elif [[ "$health" == "unhealthy" ]]; then
                status_color="${RED}"
                status_display="○ unhealthy"
            else
                status_color="${YELLOW}"
                status_display="◐ starting"
            fi
        elif [[ "$state" == "exited" ]]; then
            status_color="${RED}"
            status_display="○ stopped"
            uptime="-"
        else
            status_color="${YELLOW}"
            status_display="◐ ${state}"
        fi

        [[ -z "$ports" ]] && ports="-"

        printf "  ${CYAN}│${NC} %-10s ${CYAN}│${NC} ${status_color}%-9s${NC} ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-9s ${CYAN}│${NC}\n" \
            "$name" "$status_display" "$created" "$uptime" "$ports"
    done <<< "$json_lines"

    echo -e "  ${CYAN}└────────────┴───────────┴─────────────────────┴──────────────┴───────────┘${NC}"
    echo ""
}

# Display service selection menu and populate SELECTED_PROFILES array
# Usage: select_profiles [save_to_env]
#   save_to_env: if "save", updates DEFAULT_PROFILES in .env
select_profiles() {
    local save_to_env="${1:-}"
    SELECTED_PROFILES=()

    print_section "Select Services"

    echo ""
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  ${WHITE}#${NC}   ${WHITE}Profile${NC}      ${WHITE}Description${NC}                                   ${CYAN}│${NC}"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}1${NC}   proxy        Reality, Trojan, Hysteria2 + decoy site       ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}2${NC}   wireguard    WireGuard VPN via WebSocket tunnel            ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${YELLOW}3${NC}   dnstt        DNS tunnel ${YELLOW}(last resort, slow)${NC}                ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}4${NC}   admin        Stats dashboard (port 9443)                   ${CYAN}│${NC}"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${CYAN}│${NC}  ${BLUE}5${NC}   conduit      Psiphon bandwidth donation$       ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${BLUE}6${NC}   snowflake    Tor Snowflake donation           ${CYAN}│${NC}"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${CYAN}│${NC}  ${WHITE}a${NC}   ALL          Start all services                            ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${RED}0${NC}   Cancel       Exit without selecting                        ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    prompt "Enter choices (e.g., 1 2 4 or 'a' for all): "
    read -r choices < /dev/tty 2>/dev/null || choices=""

    if [[ "$choices" == "0" || -z "$choices" ]]; then
        return 1
    fi

    if [[ "$choices" == "a" || "$choices" == "A" ]]; then
        SELECTED_PROFILES=("all")
    else
        for choice in $choices; do
            case $choice in
                1) SELECTED_PROFILES+=("proxy") ;;
                2) SELECTED_PROFILES+=("wireguard") ;;
                3) SELECTED_PROFILES+=("dnstt") ;;
                4) SELECTED_PROFILES+=("admin") ;;
                5) SELECTED_PROFILES+=("conduit") ;;
                6) SELECTED_PROFILES+=("snowflake") ;;
            esac
        done
    fi

    if [[ ${#SELECTED_PROFILES[@]} -eq 0 ]]; then
        warn "No profiles selected"
        return 1
    fi

    # Build profile string for docker compose
    SELECTED_PROFILE_STRING=""
    for p in "${SELECTED_PROFILES[@]}"; do
        SELECTED_PROFILE_STRING+="--profile $p "
    done

    # Save to .env if requested
    if [[ "$save_to_env" == "save" ]]; then
        save_default_profiles
    fi

    return 0
}

# Save selected profiles to .env
save_default_profiles() {
    local profiles_str="${SELECTED_PROFILES[*]}"
    local env_file="$SCRIPT_DIR/.env"

    if [[ ! -f "$env_file" ]]; then
        warn "No .env file found, cannot save defaults"
        return 1
    fi

    # Update or add DEFAULT_PROFILES in .env
    if grep -q "^DEFAULT_PROFILES=" "$env_file" 2>/dev/null; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^DEFAULT_PROFILES=.*/DEFAULT_PROFILES=$profiles_str/" "$env_file"
        else
            sed -i "s/^DEFAULT_PROFILES=.*/DEFAULT_PROFILES=$profiles_str/" "$env_file"
        fi
    else
        # Add new line
        echo "" >> "$env_file"
        echo "# Default profiles for 'moav start'" >> "$env_file"
        echo "DEFAULT_PROFILES=$profiles_str" >> "$env_file"
    fi

    success "Saved default profiles: $profiles_str"
}

# Get default profiles from .env
get_default_profiles() {
    local env_file="$SCRIPT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        grep "^DEFAULT_PROFILES=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'"
    fi
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
    read -r choice < /dev/tty 2>/dev/null || choice=""

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

    # Get running services
    local running_services
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | sort)

    if [[ -z "$running_services" ]]; then
        warn "No services are currently running"
        return 0
    fi

    echo "Running services:"
    echo ""

    # Show status table
    docker compose ps --filter "status=running" 2>/dev/null | head -20
    echo ""

    echo "Options:"
    echo ""
    echo -e "  ${WHITE}a)${NC} Stop ALL services"

    # Build numbered list of services
    local i=1
    local services_array=()
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        services_array+=("$svc")
        echo -e "  ${WHITE}$i)${NC} Stop $svc"
        ((i++))
    done <<< "$running_services"

    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice < /dev/tty 2>/dev/null || choice=""

    case $choice in
        a|A)
            echo ""
            info "Stopping all services..."
            docker compose --profile all down
            success "All services stopped!"
            ;;
        0|"")
            return 0
            ;;
        [1-9]*)
            local idx=$((choice - 1))
            if [[ $idx -ge 0 && $idx -lt ${#services_array[@]} ]]; then
                local service="${services_array[$idx]}"
                echo ""
                info "Stopping $service..."
                docker compose stop "$service"
                success "$service stopped!"
            else
                warn "Invalid choice"
            fi
            ;;
        *)
            warn "Invalid choice"
            ;;
    esac
}

restart_services() {
    print_section "Restart Services"

    # Get running services
    local running_services
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | sort)

    if [[ -z "$running_services" ]]; then
        warn "No services are currently running"
        return 0
    fi

    echo "Running services:"
    echo ""
    docker compose ps --filter "status=running" 2>/dev/null | head -20
    echo ""

    echo "Options:"
    echo ""
    echo -e "  ${WHITE}a)${NC} Restart ALL services"

    local i=1
    local services_array=()
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        services_array+=("$svc")
        echo -e "  ${WHITE}$i)${NC} Restart $svc"
        ((i++))
    done <<< "$running_services"

    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice < /dev/tty 2>/dev/null || choice=""

    case $choice in
        a|A)
            echo ""
            info "Restarting all services..."
            docker compose --profile all restart
            success "All services restarted!"
            ;;
        0|"")
            return 0
            ;;
        [1-9]*)
            local idx=$((choice - 1))
            if [[ $idx -ge 0 && $idx -lt ${#services_array[@]} ]]; then
                local service="${services_array[$idx]}"
                echo ""
                info "Restarting $service..."
                docker compose restart "$service"
                success "$service restarted!"
            else
                warn "Invalid choice"
            fi
            ;;
        *)
            warn "Invalid choice"
            ;;
    esac
}

view_logs() {
    print_section "View Logs"

    # Get all services (running or not)
    local all_services
    all_services=$(docker compose ps --services -a 2>/dev/null | sort)

    echo "Options:"
    echo ""
    echo -e "  ${WHITE}a)${NC} All services (follow)"
    echo -e "  ${WHITE}t)${NC} Last 100 lines (all services)"

    if [[ -n "$all_services" ]]; then
        echo ""
        local i=1
        local services_array=()
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            services_array+=("$svc")
            echo -e "  ${WHITE}$i)${NC} $svc"
            ((i++))
        done <<< "$all_services"
    fi

    echo ""
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice < /dev/tty 2>/dev/null || choice=""

    case $choice in
        a|A)
            echo ""
            info "Showing logs for all services. Press Ctrl+C to exit."
            echo ""
            docker compose --profile all logs -t -f
            ;;
        t|T)
            docker compose --profile all logs -t --tail=100
            ;;
        0|"")
            return 0
            ;;
        [1-9]*)
            local idx=$((choice - 1))
            if [[ $idx -ge 0 && $idx -lt ${#services_array[@]} ]]; then
                local service="${services_array[$idx]}"
                echo ""
                info "Showing logs for $service. Press Ctrl+C to exit."
                echo ""
                docker compose logs -t -f "$service"
            else
                warn "Invalid choice"
            fi
            ;;
        *)
            warn "Invalid choice"
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
    read -r choice < /dev/tty 2>/dev/null || choice=""

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

migration_menu() {
    print_section "Export/Import (Migration)"

    echo "Migration options:"
    echo ""
    echo -e "  ${WHITE}1)${NC} Export configuration backup"
    echo -e "  ${WHITE}2)${NC} Import configuration backup"
    echo -e "  ${WHITE}3)${NC} Migrate to new IP address"
    echo -e "  ${WHITE}0)${NC} Back to main menu"
    echo ""

    prompt "Choice: "
    read -r choice < /dev/tty 2>/dev/null || choice=""

    case $choice in
        1)
            echo ""
            local default_file="moav-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
            prompt "Output file [$default_file]: "
            read -r output_file < /dev/tty 2>/dev/null || output_file=""
            [[ -z "$output_file" ]] && output_file="$default_file"
            cmd_export "$output_file"
            ;;
        2)
            echo ""
            prompt "Backup file to import: "
            read -r input_file < /dev/tty 2>/dev/null || input_file=""
            if [[ -n "$input_file" ]]; then
                cmd_import "$input_file"
            else
                warn "No file specified"
            fi
            ;;
        3)
            echo ""
            local current_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
            local detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
            [[ -n "$current_ip" ]] && echo "Current IP in .env: $current_ip"
            [[ -n "$detected_ip" ]] && echo "Detected server IP: $detected_ip"
            echo ""
            prompt "New IP address: "
            read -r new_ip < /dev/tty 2>/dev/null || new_ip=""
            if [[ -n "$new_ip" ]]; then
                cmd_migrate_ip "$new_ip"
            else
                warn "No IP specified"
            fi
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
    read -r username < /dev/tty 2>/dev/null || username=""

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
    read -r username < /dev/tty 2>/dev/null || username=""

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

    # Get all available services from compose
    local all_services
    all_services=$(docker compose --profile all config --services 2>/dev/null | sort)

    echo "Build options:"
    echo ""
    echo -e "  ${WHITE}a)${NC} Build all services"
    echo -e "  ${WHITE}n)${NC} Build all (no cache)"

    if [[ -n "$all_services" ]]; then
        echo ""
        echo "Build specific service:"
        local i=1
        local services_array=()
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            services_array+=("$svc")
            echo -e "  ${WHITE}$i)${NC} $svc"
            ((i++))
        done <<< "$all_services"
    fi

    echo ""
    echo -e "  ${WHITE}0)${NC} Cancel"
    echo ""

    prompt "Choice: "
    read -r choice < /dev/tty 2>/dev/null || choice=""

    case $choice in
        a|A)
            echo ""
            info "Building all services..."
            docker compose --profile all build
            success "Build complete!"
            ;;
        n|N)
            echo ""
            info "Building all services (no cache)..."
            docker compose --profile all build --no-cache
            success "Build complete!"
            ;;
        0|"")
            return 0
            ;;
        [1-9]*)
            local idx=$((choice - 1))
            if [[ $idx -ge 0 && $idx -lt ${#services_array[@]} ]]; then
                local service="${services_array[$idx]}"
                echo ""
                info "Building $service..."
                docker compose build "$service"
                success "$service built!"
            else
                warn "Invalid choice"
            fi
            ;;
        *)
            warn "Invalid choice"
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
        echo -e "  ${WHITE}8)${NC} Export/Import (migration)"
        echo ""
        echo -e "  ${WHITE}0)${NC} Exit"
        echo ""

        prompt "Choice: "
        read -r choice < /dev/tty 2>/dev/null || choice=""

        case $choice in
            1) start_services; press_enter ;;
            2) stop_services; press_enter ;;
            3) restart_services; press_enter ;;
            4) show_status; press_enter ;;
            5) view_logs; press_enter ;;
            6) user_management; press_enter ;;
            7) build_services; press_enter ;;
            8) migration_menu; press_enter ;;
            0|q|Q)
                echo ""
                info "🕊️ Goodbye! ✌️"
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
    echo "MoaV v${VERSION} - Multi-protocol Circumvention Stack"
    echo ""
    echo "Usage: moav [command] [options]"
    echo ""
    echo "Commands:"
    echo "  (no command)          Interactive menu"
    echo "  help, --help, -h      Show this help message"
    echo "  version, --version    Show version information"
    echo "  install               Install 'moav' command globally"
    echo "  uninstall             Remove global 'moav' command"
    echo "  update                Update MoaV (git pull)"
    echo "  check                 Run prerequisites check"
    echo "  bootstrap             Run first-time setup (includes service selection)"
    echo "  profiles              Change default services for 'moav start'"
    echo "  start [PROFILE...]    Start services (uses DEFAULT_PROFILES from .env)"
    echo "  stop [SERVICE...]     Stop services (default: all)"
    echo "  restart [SERVICE...]  Restart services (default: all)"
    echo "  status                Show service status"
    echo "  logs [SERVICE...] [-n] View logs (default: all, follow mode, -n for no-follow)"
    echo "  users                 List all users"
    echo "  user list             List all users"
    echo "  user add NAME [-p]    Add a new user (--package creates zip with HTML guide)"
    echo "  user revoke NAME      Revoke a user"
    echo "  user package NAME     Create distributable zip for existing user"
    echo "  build [SERVICE...]    Build services (default: all)"
    echo "  test USERNAME         Test connectivity for a user"
    echo "  client                Client mode (test/connect)"
    echo ""
    echo "Migration:"
    echo "  export [FILE]         Export full config backup (keys, users, .env)"
    echo "  import FILE           Import config backup from file"
    echo "  migrate-ip NEW_IP     Update SERVER_IP and regenerate all configs"
    echo ""
    echo "Profiles: proxy, wireguard, dnstt, admin, conduit, snowflake, client, all"
    echo "Services: sing-box, decoy, wstunnel, wireguard, dnstt, admin, psiphon-conduit, snowflake"
    echo "Aliases:  conduit→psiphon-conduit, singbox→sing-box, wg→wireguard, dns→dnstt"
    echo ""
    echo "Examples:"
    echo "  moav                           # Interactive menu"
    echo "  moav install                   # Install globally (run from anywhere)"
    echo "  moav update                    # Update MoaV (git pull)"
    echo "  moav start                     # Start all services"
    echo "  moav start proxy admin         # Start proxy and admin profiles"
    echo "  moav stop conduit              # Stop specific service"
    echo "  moav logs sing-box             # Follow sing-box logs (Ctrl+C to exit)"
    echo "  moav logs -n                   # Show last 100 lines without following"
    echo "  moav build conduit             # Build specific service"
    echo "  moav profiles                  # Change default services"
    echo "  moav user add john             # Add user 'john'"
    echo "  moav user add john --package   # Add user and create zip bundle"
    echo "  moav test joe                  # Test connectivity for user joe"
    echo "  moav client connect joe        # Connect as user joe (exposes proxy)"
    echo ""
    echo "Migration:"
    echo "  moav export                    # Backup to moav-backup-TIMESTAMP.tar.gz"
    echo "  moav import backup.tar.gz     # Restore from backup"
    echo "  moav migrate-ip 1.2.3.4       # Update configs to new server IP"
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

cmd_profiles() {
    print_header

    print_section "Default Profiles"

    local current
    current=$(get_default_profiles)

    echo ""
    if [[ -n "$current" ]]; then
        echo -e "  Current defaults: ${GREEN}${current}${NC}"
        echo ""
        echo -e "  These profiles will start when you run ${CYAN}moav start${NC} without arguments."
    else
        echo -e "  ${YELLOW}No default profiles set${NC}"
        echo ""
        echo -e "  Running ${CYAN}moav start${NC} will start ${WHITE}all${NC} services."
    fi
    echo ""

    if confirm "Change default profiles?" "y"; then
        echo ""
        if select_profiles "save"; then
            echo ""
            if confirm "Build selected services now?" "n"; then
                info "Building..."
                docker compose $SELECTED_PROFILE_STRING build
                success "Build complete!"
            fi
        fi
    fi
}

cmd_start() {
    local profiles=""

    if [[ $# -eq 0 ]]; then
        # No arguments - check for DEFAULT_PROFILES in .env
        local defaults
        defaults=$(get_default_profiles)
        if [[ -n "$defaults" ]]; then
            info "Using default profiles from .env: $defaults"
            for p in $defaults; do
                profiles+="--profile $p "
            done
        else
            # No defaults set - use all
            profiles="--profile all"
        fi
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

# Resolve service name aliases to actual docker-compose service names
resolve_service() {
    local svc="$1"
    case "$svc" in
        conduit|psiphon)    echo "psiphon-conduit" ;;
        singbox|sing)       echo "sing-box" ;;
        wg)                 echo "wireguard" ;;
        ws|tunnel)          echo "wstunnel" ;;
        dns)                echo "dnstt" ;;
        snow|tor)           echo "snowflake" ;;
        *)                  echo "$svc" ;;
    esac
}

# Resolve multiple service arguments
resolve_services() {
    local resolved=()
    for svc in "$@"; do
        resolved+=("$(resolve_service "$svc")")
    done
    echo "${resolved[@]}"
}

cmd_stop() {
    if [[ $# -eq 0 ]] || [[ "$1" == "all" ]]; then
        info "Stopping all services..."
        docker compose --profile all down
        success "All services stopped!"
    else
        local services
        services=$(resolve_services "$@")
        info "Stopping: $services"
        docker compose stop $services
        success "Services stopped!"
    fi
}

cmd_restart() {
    if [[ $# -eq 0 ]] || [[ "$1" == "all" ]]; then
        info "Restarting all services..."
        docker compose --profile all restart
        success "All services restarted!"
    else
        local services
        services=$(resolve_services "$@")
        info "Restarting: $services"
        docker compose restart $services
        success "Services restarted!"
    fi
}

cmd_status() {
    # Simple header without clearing terminal
    local singbox_ver wstunnel_ver conduit_ver
    singbox_ver=$(get_component_version "SINGBOX_VERSION" "1.12.17")
    wstunnel_ver=$(get_component_version "WSTUNNEL_VERSION" "10.5.1")
    conduit_ver=$(get_component_version "CONDUIT_VERSION" "1.2.0")

    echo ""
    echo -e "${CYAN}MoaV${NC} v${VERSION}  ${DIM}│${NC}  ${DIM}sing-box ${singbox_ver}  wstunnel ${wstunnel_ver}  conduit ${conduit_ver}${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    show_status

    # Show default profiles
    local defaults
    defaults=$(get_default_profiles)
    if [[ -n "$defaults" ]]; then
        info "Default profiles: ${WHITE}$defaults${NC}"
    fi
    echo ""
    echo -e "  ${CYAN}Commands:${NC} moav logs [service] | moav stop | moav restart | moav version"
}

cmd_logs() {
    local follow=true
    local tail_lines=100
    local services_to_log=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-follow|-n)
                follow=false
                shift
                ;;
            --tail=*)
                tail_lines="${1#*=}"
                shift
                ;;
            --tail)
                tail_lines="$2"
                shift 2
                ;;
            all)
                shift
                ;;
            *)
                if [[ -z "$services_to_log" ]]; then
                    services_to_log=$(resolve_services "$1")
                else
                    services_to_log="$services_to_log $(resolve_services "$1")"
                fi
                shift
                ;;
        esac
    done

    # Build docker compose command
    local cmd="docker compose"
    if [[ -z "$services_to_log" ]]; then
        cmd="$cmd --profile all"
    fi
    cmd="$cmd logs -t --tail $tail_lines"

    if [[ "$follow" == "true" ]]; then
        echo -e "${CYAN}Following logs (Ctrl+C to exit)...${NC}"
        echo ""
        $cmd -f $services_to_log
    else
        $cmd $services_to_log
    fi
}

cmd_users() {
    list_users
}

cmd_user() {
    local action="${1:-}"
    local username="${2:-}"
    shift 2 2>/dev/null || shift $# # Shift past action and username to get extra args

    case "$action" in
        list|ls)
            list_users
            ;;
        add)
            if [[ -z "$username" ]]; then
                error "Usage: moav user add USERNAME [--package]"
                exit 1
            fi
            if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
                error "Username can only contain letters, numbers, and underscores"
                exit 1
            fi
            if [[ -x "./scripts/user-add.sh" ]]; then
                ./scripts/user-add.sh "$username" "$@"
            else
                error "User add script not found"
                exit 1
            fi
            ;;
        revoke|rm|remove|delete)
            if [[ -z "$username" ]]; then
                error "Usage: moav user revoke USERNAME"
                exit 1
            fi
            if [[ -x "./scripts/user-revoke.sh" ]]; then
                ./scripts/user-revoke.sh "$username"
            else
                error "User revoke script not found"
                exit 1
            fi
            ;;
        package|pkg)
            if [[ -z "$username" ]]; then
                error "Usage: moav user package USERNAME"
                exit 1
            fi
            if [[ -x "./scripts/user-package.sh" ]]; then
                ./scripts/user-package.sh "$username"
            else
                error "User package script not found"
                exit 1
            fi
            ;;
        *)
            error "Usage: moav user [list|add|revoke|package] [USERNAME]"
            exit 1
            ;;
    esac
}

cmd_build() {
    if [[ $# -eq 0 ]] || [[ "$1" == "all" ]]; then
        info "Building all services..."
        docker compose --profile all build
        success "All services built!"
    else
        local services
        services=$(resolve_services "$@")
        info "Building: $services"
        docker compose --profile all build $services
        success "Build complete!"
    fi
}

# =============================================================================
# Client Commands
# =============================================================================

cmd_test() {
    local user="${1:-}"
    local json_flag=""

    # Check for --json flag
    for arg in "$@"; do
        [[ "$arg" == "--json" ]] && json_flag="--json"
        [[ "$arg" != "--json" ]] && [[ -z "$user" ]] && user="$arg"
    done

    if [[ -z "$user" ]]; then
        error "Usage: moav test USERNAME [--json]"
        echo ""
        echo "Available users:"
        ls -1 outputs/bundles/ 2>/dev/null || echo "  No users found"
        exit 1
    fi

    local bundle_path="outputs/bundles/$user"
    if [[ ! -d "$bundle_path" ]]; then
        error "User bundle not found: $bundle_path"
        exit 1
    fi

    info "Testing connectivity for user: $user"

    # Build client image if needed
    if ! docker images --format "{{.Repository}}" 2>/dev/null | grep -q "^moav-client$"; then
        info "Building client image..."
        docker compose --profile client build client
    fi

    # Run test (mount bundle + dnstt outputs for pubkey)
    docker run --rm \
        -v "$(pwd)/$bundle_path:/config:ro" \
        -v "$(pwd)/outputs/dnstt:/dnstt:ro" \
        -e ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true \
        moav-client --test $json_flag
}

cmd_client() {
    local action="${1:-}"
    shift || true

    case "$action" in
        test)
            cmd_test "$@"
            ;;
        connect)
            local user=""
            local protocol="auto"

            # Parse arguments
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --protocol|-p)
                        protocol="${2:-auto}"
                        shift 2
                        ;;
                    --*)
                        error "Unknown option: $1"
                        exit 1
                        ;;
                    *)
                        [[ -z "$user" ]] && user="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$user" ]]; then
                error "Usage: moav client connect USERNAME [--protocol PROTOCOL]"
                echo ""
                echo "Protocols: auto, reality, trojan, hysteria2, wireguard, psiphon, tor, dnstt"
                echo ""
                echo "Available users:"
                ls -1 outputs/bundles/ 2>/dev/null || echo "  No users found"
                exit 1
            fi

            local bundle_path="outputs/bundles/$user"
            if [[ ! -d "$bundle_path" ]]; then
                error "User bundle not found: $bundle_path"
                exit 1
            fi

            # Read ports from .env or use alternative defaults (to avoid server conflicts)
            local socks_port="10800"
            local http_port="18080"

            if [[ -f ".env" ]]; then
                local env_socks=$(grep -E "^CLIENT_SOCKS_PORT=" .env 2>/dev/null | cut -d= -f2 | tr -d ' "')
                local env_http=$(grep -E "^CLIENT_HTTP_PORT=" .env 2>/dev/null | cut -d= -f2 | tr -d ' "')
                [[ -n "$env_socks" ]] && socks_port="$env_socks"
                [[ -n "$env_http" ]] && http_port="$env_http"
            fi

            info "Connecting as user: $user (protocol: $protocol)"
            info "SOCKS5 proxy will be available at localhost:$socks_port"
            info "HTTP proxy will be available at localhost:$http_port"

            # Build client image if needed
            if ! docker images --format "{{.Repository}}" 2>/dev/null | grep -q "^moav-client$"; then
                info "Building client image..."
                docker compose --profile client build client
            fi

            # Run client in foreground (mount bundle + dnstt outputs for pubkey)
            docker run --rm -it \
                -p "$socks_port:1080" \
                -p "$http_port:8080" \
                -v "$(pwd)/$bundle_path:/config:ro" \
                -v "$(pwd)/outputs/dnstt:/dnstt:ro" \
                -e ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true \
                moav-client --connect -p "$protocol"
            ;;
        build)
            info "Building client image..."
            docker compose --profile client build client
            success "Client image built!"
            ;;
        *)
            echo "Usage: moav client <command> [options]"
            echo ""
            echo "Commands:"
            echo "  test USERNAME [--json]        Test connectivity for a user"
            echo "  connect USERNAME [PROTOCOL]   Connect and expose local proxy"
            echo "  build                         Build the client image"
            echo ""
            echo "Protocols: auto, reality, trojan, hysteria2, wireguard, psiphon, tor, dnstt"
            echo ""
            echo "Examples:"
            echo "  moav client test joe              # Test all protocols for user joe"
            echo "  moav client test joe --json       # Output results as JSON"
            echo "  moav client connect joe           # Connect using auto-detection"
            echo "  moav client connect joe reality   # Connect using Reality protocol"
            ;;
    esac
}

# =============================================================================
# Migration: Export/Import
# =============================================================================

cmd_export() {
    print_section "Export MoaV Configuration"

    local output_file="${1:-}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local default_name="moav-backup-${timestamp}.tar.gz"

    if [[ -z "$output_file" ]]; then
        output_file="$default_name"
    fi

    # Ensure .tar.gz extension
    if [[ "$output_file" != *.tar.gz ]]; then
        output_file="${output_file}.tar.gz"
    fi

    info "Creating backup: $output_file"
    echo ""

    # Create temp directory for export
    local temp_dir=$(mktemp -d)
    local export_dir="$temp_dir/moav-export"
    mkdir -p "$export_dir"

    # 1. Export .env file
    if [[ -f ".env" ]]; then
        info "  Exporting .env..."
        cp ".env" "$export_dir/"
    else
        warn "  No .env file found"
    fi

    # 2. Export state from Docker volume (keys + users)
    info "  Exporting state (keys, users)..."
    if docker volume inspect moav_moav_state &>/dev/null; then
        mkdir -p "$export_dir/state"
        docker run --rm \
            -v moav_moav_state:/state:ro \
            -v "$export_dir/state:/backup" \
            alpine sh -c "cp -a /state/. /backup/ 2>/dev/null || true"

        # Verify key files were exported
        if [[ -f "$export_dir/state/keys/reality.env" ]]; then
            success "    Reality keys exported"
        fi
        if [[ -f "$export_dir/state/keys/wg-server.key" ]]; then
            success "    WireGuard keys exported"
        fi
        if [[ -f "$export_dir/state/keys/dnstt-server.key.hex" ]]; then
            success "    dnstt keys exported"
        fi

        # Count users
        local user_count=$(ls -1 "$export_dir/state/users" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$user_count" -gt 0 ]]; then
            success "    $user_count user(s) exported"
        fi
    else
        warn "  State volume not found (moav_moav_state)"
    fi

    # 3. Export configs directory
    if [[ -d "configs" ]]; then
        info "  Exporting configs..."
        mkdir -p "$export_dir/configs"
        cp -a configs/. "$export_dir/configs/" 2>/dev/null || true
    fi

    # 4. Export outputs/bundles (user configs)
    if [[ -d "outputs/bundles" ]]; then
        info "  Exporting user bundles..."
        mkdir -p "$export_dir/outputs/bundles"
        cp -a outputs/bundles/. "$export_dir/outputs/bundles/" 2>/dev/null || true
    fi

    # 5. Export dnstt outputs (public key for clients)
    if [[ -d "outputs/dnstt" ]]; then
        info "  Exporting dnstt outputs..."
        mkdir -p "$export_dir/outputs/dnstt"
        cp -a outputs/dnstt/. "$export_dir/outputs/dnstt/" 2>/dev/null || true
    fi

    # 6. Create manifest
    info "  Creating manifest..."
    cat > "$export_dir/manifest.json" <<EOF
{
    "version": "1.0",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "moav_version": "${MOAV_VERSION:-unknown}",
    "hostname": "$(hostname)",
    "server_ip": "$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo 'unknown')",
    "domain": "$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo 'unknown')"
}
EOF

    # 7. Create tarball
    info "  Creating archive..."
    tar -czf "$output_file" -C "$temp_dir" moav-export

    # Cleanup
    rm -rf "$temp_dir"

    local size=$(du -h "$output_file" | cut -f1)
    echo ""
    success "Backup created: $output_file ($size)"
    echo ""
    echo -e "${CYAN}Contents:${NC}"
    tar -tzf "$output_file" | head -30
    echo ""
    echo -e "${YELLOW}Security Note:${NC} This backup contains private keys."
    echo "  Transfer securely and delete after import."
    echo ""
    echo -e "${CYAN}To import on new server:${NC}"
    echo "  1. Copy this file to the new server"
    echo "  2. Run: moav import $output_file"
    echo "  3. Update .env with new SERVER_IP if needed"
    echo "  4. Run: moav migrate-ip NEW_IP"
}

cmd_import() {
    print_section "Import MoaV Configuration"

    local input_file="${1:-}"

    if [[ -z "$input_file" ]]; then
        error "Usage: moav import <backup-file.tar.gz>"
        exit 1
    fi

    if [[ ! -f "$input_file" ]]; then
        error "File not found: $input_file"
        exit 1
    fi

    info "Importing from: $input_file"
    echo ""

    # Check if this will overwrite existing data
    local has_existing=false
    if [[ -f ".env" ]] || docker volume inspect moav_moav_state &>/dev/null 2>&1; then
        has_existing=true
        warn "Existing configuration detected!"
        echo ""
        echo -e "${YELLOW}This will overwrite:${NC}"
        [[ -f ".env" ]] && echo "  - .env file"
        docker volume inspect moav_moav_state &>/dev/null 2>&1 && echo "  - State volume (keys, users)"
        [[ -d "configs" ]] && echo "  - configs directory"
        echo ""
        printf "Continue? [y/N] "
        read -r confirm < /dev/tty 2>/dev/null || confirm="n"
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            info "Import cancelled."
            exit 0
        fi
        echo ""
    fi

    # Extract to temp directory
    local temp_dir=$(mktemp -d)
    info "  Extracting archive..."
    tar -xzf "$input_file" -C "$temp_dir"

    local export_dir="$temp_dir/moav-export"
    if [[ ! -d "$export_dir" ]]; then
        error "Invalid backup format"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Show manifest
    if [[ -f "$export_dir/manifest.json" ]]; then
        echo ""
        echo -e "${CYAN}Backup Info:${NC}"
        cat "$export_dir/manifest.json" | grep -E '(created|server_ip|domain)' | sed 's/[",]//g' | sed 's/^/  /'
        echo ""
    fi

    # 1. Import .env file
    if [[ -f "$export_dir/.env" ]]; then
        info "  Importing .env..."
        cp "$export_dir/.env" ".env"
        success "    .env imported"
    fi

    # 2. Import state to Docker volume
    if [[ -d "$export_dir/state" ]]; then
        info "  Importing state (keys, users)..."

        # Create volume if it doesn't exist
        docker volume create moav_moav_state &>/dev/null || true

        # Copy state to volume
        docker run --rm \
            -v moav_moav_state:/state \
            -v "$export_dir/state:/backup:ro" \
            alpine sh -c "rm -rf /state/* && cp -a /backup/. /state/"

        success "    State imported to Docker volume"
    fi

    # 3. Import configs
    if [[ -d "$export_dir/configs" ]]; then
        info "  Importing configs..."
        mkdir -p configs
        cp -a "$export_dir/configs/." configs/
        success "    Configs imported"
    fi

    # 4. Import outputs/bundles
    if [[ -d "$export_dir/outputs/bundles" ]]; then
        info "  Importing user bundles..."
        mkdir -p outputs/bundles
        cp -a "$export_dir/outputs/bundles/." outputs/bundles/
        success "    User bundles imported"
    fi

    # 5. Import dnstt outputs
    if [[ -d "$export_dir/outputs/dnstt" ]]; then
        info "  Importing dnstt outputs..."
        mkdir -p outputs/dnstt
        cp -a "$export_dir/outputs/dnstt/." outputs/dnstt/
        success "    dnstt outputs imported"
    fi

    # Cleanup
    rm -rf "$temp_dir"

    echo ""
    success "Import complete!"
    echo ""

    # Check if IP migration is needed
    local old_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local current_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")

    if [[ -n "$old_ip" ]] && [[ -n "$current_ip" ]] && [[ "$old_ip" != "$current_ip" ]]; then
        echo ""
        warn "IP address mismatch detected!"
        echo "  Backup IP:  $old_ip"
        echo "  Current IP: $current_ip"
        echo ""
        echo -e "${CYAN}To update to new IP, run:${NC}"
        echo "  moav migrate-ip $current_ip"
        echo ""
    fi

    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Review .env and update SERVER_IP/DOMAIN if needed"
    echo "  2. Run: moav migrate-ip NEW_IP (if IP changed)"
    echo "  3. Run: moav start"
}

cmd_migrate_ip() {
    print_section "Migrate Server IP"

    local new_ip="${1:-}"

    if [[ -z "$new_ip" ]]; then
        # Try to detect current IP
        local detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
        if [[ -n "$detected_ip" ]]; then
            echo "Detected current IP: $detected_ip"
            echo ""
        fi
        error "Usage: moav migrate-ip <new-ip>"
        echo ""
        echo "This command updates SERVER_IP and regenerates all client configs."
        exit 1
    fi

    # Validate IP format (basic check)
    if ! echo "$new_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        error "Invalid IP address format: $new_ip"
        exit 1
    fi

    local old_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')

    if [[ -z "$old_ip" ]]; then
        error "Could not read current SERVER_IP from .env"
        exit 1
    fi

    if [[ "$old_ip" == "$new_ip" ]]; then
        info "IP address is already set to $new_ip"
        exit 0
    fi

    info "Migrating from $old_ip to $new_ip"
    echo ""

    # 1. Update .env
    info "  Updating .env..."
    sed -i.bak "s/^SERVER_IP=.*/SERVER_IP=\"$new_ip\"/" .env
    rm -f .env.bak
    success "    SERVER_IP updated"

    # 2. Update WireGuard server config (if exists)
    if [[ -f "configs/wireguard/wg0.conf" ]]; then
        info "  Updating WireGuard config..."
        # WireGuard server config doesn't contain server IP, but let's check
        success "    WireGuard config OK (no changes needed)"
    fi

    # 3. Regenerate user bundles
    info "  Regenerating user bundles..."
    local users_dir="outputs/bundles"
    if [[ -d "$users_dir" ]]; then
        local regenerated=0
        for user_dir in "$users_dir"/*/; do
            if [[ -d "$user_dir" ]]; then
                local username=$(basename "$user_dir")

                # Skip if it looks like a zip file name pattern
                [[ "$username" == *-configs ]] && continue
                [[ "$username" == *-moav-configs ]] && continue

                # Update Reality config
                if [[ -f "$user_dir/reality.txt" ]]; then
                    sed -i.bak "s/@$old_ip:/@$new_ip:/g" "$user_dir/reality.txt"
                    rm -f "$user_dir/reality.txt.bak"
                fi

                # Update sing-box configs
                for config in "$user_dir"/*-singbox.json; do
                    if [[ -f "$config" ]]; then
                        sed -i.bak "s/\"server\": \"$old_ip\"/\"server\": \"$new_ip\"/g" "$config"
                        rm -f "$config.bak"
                    fi
                done

                # Update Hysteria2 configs
                if [[ -f "$user_dir/hysteria2.txt" ]]; then
                    sed -i.bak "s/@$old_ip:/@$new_ip:/g" "$user_dir/hysteria2.txt"
                    rm -f "$user_dir/hysteria2.txt.bak"
                fi
                if [[ -f "$user_dir/hysteria2.yaml" ]]; then
                    sed -i.bak "s/server: $old_ip:/server: $new_ip:/g" "$user_dir/hysteria2.yaml"
                    rm -f "$user_dir/hysteria2.yaml.bak"
                fi

                # Update Trojan config
                if [[ -f "$user_dir/trojan.txt" ]]; then
                    sed -i.bak "s/@$old_ip:/@$new_ip:/g" "$user_dir/trojan.txt"
                    rm -f "$user_dir/trojan.txt.bak"
                fi

                # Update WireGuard direct config (wstunnel uses localhost, no change needed)
                if [[ -f "$user_dir/wireguard.conf" ]]; then
                    sed -i.bak "s/Endpoint = $old_ip:/Endpoint = $new_ip:/g" "$user_dir/wireguard.conf"
                    rm -f "$user_dir/wireguard.conf.bak"
                fi

                # Update dnstt instructions
                if [[ -f "$user_dir/dnstt-instructions.txt" ]]; then
                    sed -i.bak "s/$old_ip/$new_ip/g" "$user_dir/dnstt-instructions.txt"
                    rm -f "$user_dir/dnstt-instructions.txt.bak"
                fi

                # Update README
                if [[ -f "$user_dir/README.md" ]]; then
                    sed -i.bak "s/$old_ip/$new_ip/g" "$user_dir/README.md"
                    rm -f "$user_dir/README.md.bak"
                fi

                ((regenerated++)) || true
            fi
        done

        if [[ $regenerated -gt 0 ]]; then
            success "    Updated $regenerated user bundle(s)"
        else
            info "    No user bundles found"
        fi
    fi

    # 4. Regenerate QR codes (optional - requires qrencode)
    if command -v qrencode &>/dev/null; then
        info "  Regenerating QR codes..."
        local qr_count=0
        for user_dir in "$users_dir"/*/; do
            if [[ -d "$user_dir" ]]; then
                local username=$(basename "$user_dir")
                [[ "$username" == *-configs ]] && continue

                for txt_file in "$user_dir"/*.txt; do
                    if [[ -f "$txt_file" ]] && [[ "$txt_file" != *instructions* ]]; then
                        local qr_file="${txt_file%.txt}-qr.png"
                        qrencode -o "$qr_file" -s 6 "$(cat "$txt_file")" 2>/dev/null && ((qr_count++)) || true
                    fi
                done

                # WireGuard QR codes
                if [[ -f "$user_dir/wireguard.conf" ]]; then
                    qrencode -o "$user_dir/wireguard-qr.png" -s 6 -r "$user_dir/wireguard.conf" 2>/dev/null && ((qr_count++)) || true
                fi
            fi
        done
        if [[ $qr_count -gt 0 ]]; then
            success "    Regenerated $qr_count QR code(s)"
        fi
    else
        warn "  Skipping QR regeneration (qrencode not installed)"
    fi

    echo ""
    success "Migration complete!"
    echo ""
    echo -e "${CYAN}Summary:${NC}"
    echo "  Old IP: $old_ip"
    echo "  New IP: $new_ip"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Restart services: moav restart"
    echo "  2. Re-package user bundles: moav user package <username>"
    echo "  3. Distribute new configs to users"
    echo ""
    echo -e "${YELLOW}Note:${NC} Users will need updated configs to connect via the new IP."
}

# =============================================================================
# Entry Point
# =============================================================================

main_interactive() {
    print_header

    # Check prerequisites only if not already verified
    if ! prereqs_already_checked; then
        check_prerequisites
        echo ""
        sleep 1
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
        version|--version|-v)
            show_versions
            ;;
        install)
            do_install
            ;;
        uninstall)
            do_uninstall
            ;;
        update)
            cmd_update
            ;;
        check)
            cmd_check
            ;;
        bootstrap)
            cmd_bootstrap
            ;;
        profiles)
            cmd_profiles
            ;;
        start)
            shift
            cmd_start "$@"
            ;;
        stop)
            shift
            cmd_stop "$@"
            ;;
        restart)
            shift
            cmd_restart "$@"
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
            shift
            cmd_build "$@"
            ;;
        test)
            shift
            cmd_test "$@"
            ;;
        client)
            shift
            cmd_client "$@"
            ;;
        export)
            shift
            cmd_export "$@"
            ;;
        import)
            shift
            cmd_import "$@"
            ;;
        migrate-ip|migrate_ip|migrateip)
            shift
            cmd_migrate_ip "$@"
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
