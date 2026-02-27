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
# Save original working directory before changing to script dir
ORIGINAL_PWD="$PWD"

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
UPDATE_CACHE_FILE="/tmp/.moav_update_check"
LATEST_VERSION=""

# Handle Ctrl+C gracefully
goodbye() {
    echo ""
    echo -e "${CYAN}Goodbye! Stay safe out there.${NC}"
    echo ""
    exit 0
}
trap goodbye SIGINT

# =============================================================================
# Helper Functions
# =============================================================================

# Check for updates (async, cached for 1 hour)
check_for_updates() {
    local cache_file="$UPDATE_CACHE_FILE"
    local cache_max_age=3600  # 1 hour

    # Only check on main branch
    local branch
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$branch" != "main" && "$branch" != "master" ]]; then
        return
    fi

    # Check cache
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $cache_age -lt $cache_max_age ]]; then
            LATEST_VERSION=$(cat "$cache_file" 2>/dev/null)
            return
        fi
    fi

    # Fetch latest release (in background, don't block)
    {
        local latest
        latest=$(curl -s --max-time 3 "https://api.github.com/repos/shayanb/MoaV/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
        if [[ -n "$latest" && "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$latest" > "$cache_file"
        fi
    } &
}

# Read cached update info
get_latest_version() {
    if [[ -f "$UPDATE_CACHE_FILE" ]]; then
        cat "$UPDATE_CACHE_FILE" 2>/dev/null
    fi
}

# Compare semver versions: returns 0 if $1 > $2
version_gt() {
    local v1="$1" v2="$2"
    local IFS=.
    local i v1_parts=($v1) v2_parts=($v2)
    for ((i=0; i<3; i++)); do
        local n1="${v1_parts[i]:-0}"
        local n2="${v2_parts[i]:-0}"
        if ((n1 > n2)); then return 0; fi
        if ((n1 < n2)); then return 1; fi
    done
    return 1
}

print_header() {
    clear
    # Get current branch
    local branch
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    local version_line="v${VERSION}"
    if [[ -n "$branch" && "$branch" != "main" ]]; then
        version_line="v${VERSION} (${branch})"
    fi

    # Check for update (only on main branch)
    local update_line=""
    local latest
    latest=$(get_latest_version)
    if [[ -n "$latest" ]] && version_gt "$latest" "$VERSION"; then
        update_line="Update available: v${latest} (moav update)"
    fi

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
    printf "║  %-49s ║\n" "$version_line"
    if [[ -n "$update_line" ]]; then
        printf "║  ${NC}${YELLOW}%-49s${CYAN} ║\n" "$update_line"
    fi
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

get_admin_url() {
    # Get admin URL using DOMAIN or SERVER_IP from .env
    local admin_port="${PORT_ADMIN:-9443}"
    local domain=$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local server_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local admin_host="${domain:-${server_ip:-localhost}}"
    echo "https://${admin_host}:${admin_port}"
}

get_grafana_url() {
    # Get Grafana URL using DOMAIN or SERVER_IP from .env
    local grafana_port="${PORT_GRAFANA:-9444}"
    local domain=$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local server_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local grafana_host="${domain:-${server_ip:-localhost}}"
    echo "https://${grafana_host}:${grafana_port}"
}

get_grafana_cdn_url() {
    # Get Grafana CDN URL from GRAFANA_SUBDOMAIN + DOMAIN
    local grafana_subdomain=$(grep -E '^GRAFANA_SUBDOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local domain=$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -n "$grafana_subdomain" ]] && [[ -n "$domain" ]]; then
        echo "https://${grafana_subdomain}.${domain}:2083"
    fi
}

get_cdn_url() {
    # Get CDN URL for VLESS+WS from CDN_SUBDOMAIN + DOMAIN
    local cdn_subdomain=$(grep -E '^CDN_SUBDOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local domain=$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -n "$cdn_subdomain" ]] && [[ -n "$domain" ]]; then
        echo "https://${cdn_subdomain}.${domain}"
    fi
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
                echo ""
                echo -e "${CYAN}Configure your MoaV installation:${NC}"
                echo ""

                # Ask for domain
                echo -e "${WHITE}Domain name${NC} (required for TLS-based protocols)"
                echo "  Example: vpn.example.com"
                echo "  Leave empty to run only domain-less services"
                printf "  Domain: "
                read -r input_domain

                local domainless_mode=false
                if [[ -n "$input_domain" ]]; then
                    sed -i "s|^DOMAIN=.*|DOMAIN=\"$input_domain\"|" .env
                    success "Domain set to: $input_domain"
                    echo ""

                    # Ask for email (only if domain is set)
                    echo -e "${WHITE}Email address${NC} (for Let's Encrypt TLS certificate)"
                    printf "  Email: "
                    read -r input_email
                    if [[ -n "$input_email" ]]; then
                        sed -i "s|^ACME_EMAIL=.*|ACME_EMAIL=\"$input_email\"|" .env
                        success "Email set to: $input_email"
                    else
                        warn "No email set - you can edit .env later"
                    fi

                    # Detect server IP and show DNS template
                    echo ""
                    info "Detecting server IP..."
                    local detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
                    if [[ "$detected_ip" != "YOUR_SERVER_IP" ]]; then
                        success "Detected IP: $detected_ip"
                        # Save to .env
                        if grep -q "^SERVER_IP=" .env 2>/dev/null; then
                            sed -i "s|^SERVER_IP=.*|SERVER_IP=\"$detected_ip\"|" .env
                        else
                            echo "SERVER_IP=\"$detected_ip\"" >> .env
                        fi
                    fi
                    echo ""

                    # Show DNS configuration template
                    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
                    echo -e "${WHITE}  DNS Configuration Required${NC}"
                    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
                    echo ""
                    echo "  Add these DNS records in your DNS provider (e.g., Cloudflare):"
                    echo ""
                    echo -e "  ${WHITE}Required Records:${NC}"
                    printf "  %-8s %-12s %-20s %s\n" "Type" "Name" "Value" "Proxy"
                    printf "  %-8s %-12s %-20s %s\n" "────" "────" "─────" "────"
                    printf "  %-8s %-12s %-20s %s\n" "A" "@" "$detected_ip" "DNS only (gray)"
                    echo ""
                    echo -e "  ${WHITE}For DNS Tunnel (dnstt):${NC}"
                    printf "  %-8s %-12s %-20s %s\n" "A" "dns" "$detected_ip" "DNS only (gray)"
                    printf "  %-8s %-12s %-20s %s\n" "NS" "t" "dns.$input_domain" "-"
                    echo ""
                    echo -e "  ${WHITE}Optional - CDN Mode (Cloudflare proxied):${NC}"
                    printf "  %-8s %-12s %-20s %s\n" "A" "cdn" "$detected_ip" "Proxied (orange)"
                    printf "  %-8s %-12s %-20s %s\n" "A" "grafana" "$detected_ip" "Proxied (orange)"
                    echo ""
                    echo -e "  ${YELLOW}⚠ CDN Mode requires an Origin Rule in Cloudflare:${NC}"
                    echo "    Rules → Origin Rules → Create rule"
                    echo "    • Match: Hostname equals cdn.$input_domain"
                    echo "    • Action: Destination Port → Rewrite to 2082"
                    echo ""
                    echo -e "  See docs/DNS.md for detailed instructions."
                    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
                    echo ""

                    # Ask user to confirm DNS is configured
                    if ! confirm "Have you configured DNS records (or will do so now)?" "y"; then
                        echo ""
                        warn "DNS must be configured before services will work properly."
                        echo "  You can configure DNS later and run 'moav bootstrap' again."
                        echo ""
                    fi
                else
                    # No domain - warn about disabled services
                    echo ""
                    warn "No domain provided!"
                    echo ""
                    echo -e "  ${YELLOW}Services that require a domain (will be disabled):${NC}"
                    echo "    • Reality, Trojan, Hysteria2 (sing-box proxy)"
                    echo "    • DNS tunnel (dnstt)"
                    echo "    • Admin dashboard with HTTPS"
                    echo ""
                    echo -e "  ${GREEN}Services that work without a domain:${NC}"
                    echo "    • WireGuard (direct UDP)"
                    echo "    • Psiphon Conduit (bandwidth donation)"
                    echo "    • Tor Snowflake (bandwidth donation)"
                    echo ""

                    if confirm "Continue with domain-less mode?" "n"; then
                        domainless_mode=true
                        # Set default profiles to only include domain-less services (admin uses self-signed cert)
                        sed -i "s|^DEFAULT_PROFILES=.*|DEFAULT_PROFILES=\"wireguard admin conduit snowflake\"|" .env
                        # Disable all protocols that need domain (admin works with self-signed cert)
                        # Use grep to check if line exists, then sed to replace, or append if missing
                        for var in ENABLE_REALITY ENABLE_TROJAN ENABLE_HYSTERIA2 ENABLE_DNSTT ENABLE_TRUSTTUNNEL; do
                            if grep -q "^${var}=" .env 2>/dev/null; then
                                sed -i "s|^${var}=.*|${var}=false|" .env
                            else
                                echo "${var}=false" >> .env
                            fi
                        done
                        success "Domain-less mode enabled"
                        info "WireGuard, Admin (self-signed cert), Conduit, and Snowflake will be available"
                    else
                        echo ""
                        info "Please enter a domain to use all services."
                        echo "  You can edit .env later and run 'moav bootstrap' again."
                        return 0
                    fi
                fi
                echo ""

                # Generate or ask for admin password
                echo -e "${WHITE}Admin dashboard password${NC}"
                if [[ "$domainless_mode" == "true" ]]; then
                    echo "  (Admin will use self-signed certificate in domain-less mode)"
                fi
                echo "  Press Enter to generate a random password, or type your own"
                printf "  Password: "
                read -r input_password
                if [[ -z "$input_password" ]]; then
                    input_password=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
                fi
                sed -i "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=\"$input_password\"|" .env
                success "Admin password configured"
                echo ""

                # Show password prominently
                echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
                echo -e "  ${WHITE}Admin Password:${NC} ${CYAN}$input_password${NC}"
                echo ""
                echo -e "  ${YELLOW}⚠ IMPORTANT: Save this password! It's also stored in .env${NC}"
                echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
                echo ""
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
        if confirm "Install 'moav' command globally? (run from anywhere)" "y"; then
            do_install
        fi
    fi
}

prereqs_already_checked() {
    # Prerequisites must be re-checked if .env is missing
    [[ -f "$PREREQS_FILE" ]] && [[ -f ".env" ]]
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
    local wipe=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wipe)
                wipe=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                echo "Usage: moav uninstall [--wipe]"
                return 1
                ;;
        esac
    done

    echo ""
    if [[ "$wipe" == "true" ]]; then
        warn "This will COMPLETELY REMOVE MoaV including:"
        echo "  - All Docker containers and volumes"
        echo "  - All configuration files (.env, configs/)"
        echo "  - All generated keys and certificates"
        echo "  - All user bundles (outputs/)"
        echo "  - Global 'moav' command"
        echo ""
        warn "This cannot be undone! All keys and user configs will be lost."
    else
        info "This will remove:"
        echo "  - All Docker containers (data preserved in volumes)"
        echo "  - Global 'moav' command"
        echo ""
        echo "Preserved: .env, keys, user bundles, volumes"
        echo "Use --wipe to remove everything"
    fi
    echo ""

    read -r -p "Continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Cancelled"
        return 0
    fi

    echo ""

    # Stop and remove containers
    if command -v docker &>/dev/null && [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        info "Stopping Docker containers..."
        cd "$SCRIPT_DIR"

        # List running containers before removing
        local containers
        containers=$(docker compose --profile all ps -q 2>/dev/null || true)
        if [[ -n "$containers" ]]; then
            docker compose --profile all ps --format "  - {{.Name}}" 2>/dev/null || true
        fi

        if [[ "$wipe" == "true" ]]; then
            # Remove containers AND volumes
            docker compose --profile all down -v --remove-orphans 2>/dev/null || true
            echo "  Removed containers and volumes"
        else
            # Remove containers only, keep volumes
            docker compose --profile all down --remove-orphans 2>/dev/null || true
            echo "  Removed containers (volumes preserved)"
        fi
        success "Containers removed"
    fi

    # Wipe all generated files if --wipe
    if [[ "$wipe" == "true" ]]; then
        echo ""
        info "Removing configuration files..."

        # Remove .env
        if [[ -f "$SCRIPT_DIR/.env" ]]; then
            rm -f "$SCRIPT_DIR/.env"
            echo "  - .env"
        fi

        # Remove generated sing-box config
        if [[ -f "$SCRIPT_DIR/configs/sing-box/config.json" ]]; then
            rm -f "$SCRIPT_DIR/configs/sing-box/config.json"
            echo "  - configs/sing-box/config.json"
        fi

        # Remove generated dnstt files
        if ls "$SCRIPT_DIR/configs/dnstt/"*.key "$SCRIPT_DIR/configs/dnstt/server.conf" "$SCRIPT_DIR/configs/dnstt/server.pub" 2>/dev/null | head -1 >/dev/null; then
            rm -f "$SCRIPT_DIR/configs/dnstt/server.conf" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/dnstt/server.pub" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/dnstt/"*.key 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/dnstt/"*.key.hex 2>/dev/null
            echo "  - configs/dnstt/*"
        fi

        # Remove generated WireGuard files
        if [[ -f "$SCRIPT_DIR/configs/wireguard/wg0.conf" ]] || [[ -d "$SCRIPT_DIR/configs/wireguard/wg_confs" ]]; then
            rm -f "$SCRIPT_DIR/configs/wireguard/wg0.conf" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/wireguard/wg0.conf."* 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/wireguard/server.pub" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/wireguard/server.key" 2>/dev/null
            rm -rf "$SCRIPT_DIR/configs/wireguard/wg_confs/" 2>/dev/null
            rm -rf "$SCRIPT_DIR/configs/wireguard/coredns/" 2>/dev/null
            rm -rf "$SCRIPT_DIR/configs/wireguard/templates/" 2>/dev/null
            rm -rf "$SCRIPT_DIR/configs/wireguard/peer"* 2>/dev/null
            echo "  - configs/wireguard/*"
        fi

        # Remove generated AmneziaWG files
        if [[ -f "$SCRIPT_DIR/configs/amneziawg/awg0.conf" ]]; then
            rm -f "$SCRIPT_DIR/configs/amneziawg/awg0.conf" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/amneziawg/server.pub" 2>/dev/null
            echo "  - configs/amneziawg/*"
        fi

        # Remove generated TrustTunnel files
        if [[ -f "$SCRIPT_DIR/configs/trusttunnel/vpn.toml" ]]; then
            rm -f "$SCRIPT_DIR/configs/trusttunnel/vpn.toml" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/trusttunnel/hosts.toml" 2>/dev/null
            rm -f "$SCRIPT_DIR/configs/trusttunnel/credentials.toml" 2>/dev/null
            echo "  - configs/trusttunnel/*"
        fi

        # Remove outputs (bundles, keys)
        if [[ -d "$SCRIPT_DIR/outputs" ]] && [[ -n "$(ls -A "$SCRIPT_DIR/outputs" 2>/dev/null | grep -v .gitkeep)" ]]; then
            local bundle_count
            bundle_count=$(find "$SCRIPT_DIR/outputs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            find "$SCRIPT_DIR/outputs" -mindepth 1 -not -name '.gitkeep' -delete 2>/dev/null || true
            echo "  - outputs/ ($bundle_count user bundles)"
        fi

        # Remove state directory (user credentials)
        if [[ -d "$SCRIPT_DIR/state" ]]; then
            local user_count
            user_count=$(find "$SCRIPT_DIR/state/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            rm -rf "$SCRIPT_DIR/state/" 2>/dev/null
            echo "  - state/ ($user_count users)"
        fi

        # Remove certbot certificates
        if [[ -d "$SCRIPT_DIR/certbot" ]]; then
            rm -rf "$SCRIPT_DIR/certbot/" 2>/dev/null
            echo "  - certbot/"
        fi

        success "Configuration files removed"

        # Ask about Docker images
        echo ""

        # External images used by MoaV (from docker-compose.yml)
        local external_image_patterns="prom/prometheus|grafana/grafana|prom/node-exporter|gcr.io/cadvisor|ghcr.io/zxh326/clash-exporter|certbot/certbot|nginx:alpine"

        # Find MoaV-built images (moav-* prefix)
        local moav_images
        moav_images=$(docker images --format "{{.Repository}}:{{.Tag}} ({{.Size}})" 2>/dev/null | grep -E "^moav-" || true)

        # Find external images used by MoaV
        local external_images
        external_images=$(docker images --format "{{.Repository}}:{{.Tag}} ({{.Size}})" 2>/dev/null | grep -E "^($external_image_patterns)" || true)

        if [[ -n "$moav_images" ]] || [[ -n "$external_images" ]]; then
            info "Docker images found:"

            if [[ -n "$moav_images" ]]; then
                echo "  Built images:"
                echo "$moav_images" | while read -r img; do
                    echo "    - $img"
                done
            fi

            if [[ -n "$external_images" ]]; then
                echo "  External images (pulled):"
                echo "$external_images" | while read -r img; do
                    echo "    - $img"
                done
            fi

            echo ""
            read -r -p "Also remove Docker images? [y/N] " remove_images
            if [[ "$remove_images" =~ ^[Yy]$ ]]; then
                info "Removing Docker images..."
                # Remove moav-* images (include tag for images like moav-nginx:local)
                docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "^moav-" | xargs -r docker rmi -f 2>/dev/null || true
                # Remove external images
                docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "^($external_image_patterns)" | xargs -r docker rmi -f 2>/dev/null || true
                success "Docker images removed"
            else
                echo "  Docker images kept"
            fi
        fi
    fi

    # Remove global symlink
    if [[ -e "$INSTALL_PATH" ]]; then
        echo ""
        if [[ -L "$INSTALL_PATH" ]]; then
            info "Removing global command..."
            if [[ -w "$(dirname "$INSTALL_PATH")" ]]; then
                rm -f "$INSTALL_PATH"
            else
                sudo rm -f "$INSTALL_PATH"
            fi
            echo "  - $INSTALL_PATH"
            success "Global command removed"
        else
            warn "$INSTALL_PATH is not a symlink, not removing"
        fi
    fi

    echo ""
    if [[ "$wipe" == "true" ]]; then
        success "MoaV completely uninstalled"
        echo ""
        echo "To reinstall:"
        echo "  curl -fsSL moav.sh/install.sh | bash"
        echo ""
        echo "Or locally:"
        echo "  cp .env.example .env && ./moav.sh"
    else
        success "MoaV uninstalled (data preserved)"
        echo ""
        echo "To reinstall with existing data:"
        echo "  ./moav.sh install"
        echo "  moav start"
    fi
}

cmd_update() {
    local target_branch=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--branch)
                target_branch="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: moav update [-b BRANCH]"
                echo ""
                echo "Update MoaV to the latest version"
                echo ""
                echo "Options:"
                echo "  -b, --branch BRANCH   Switch to and pull specified branch"
                echo "                        Examples: main, dev, paqet"
                echo ""
                echo "Examples:"
                echo "  moav update              # Update current branch"
                echo "  moav update -b main      # Switch to main and update"
                echo "  moav update -b dev       # Switch to dev branch"
                return 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use 'moav update --help' for usage"
                return 1
                ;;
        esac
    done

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

    # Check current branch
    local current_branch
    current_branch=$(git -C "$install_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo -e "  Current branch: ${CYAN}$current_branch${NC}"

    # Show target branch if switching
    if [[ -n "$target_branch" ]]; then
        echo -e "  Target branch: ${GREEN}$target_branch${NC}"
    fi

    # Warn if not on main branch (and not switching)
    if [[ -z "$target_branch" && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
        echo ""
        echo -e "  ${YELLOW}⚠ Warning:${NC} You are on branch '${YELLOW}$current_branch${NC}' (not main)"
        echo -e "    This may be a development or feature branch."
        echo -e "    To switch to stable: ${WHITE}moav update -b main${NC}"
    fi
    echo ""

    # Check for local changes that would block git pull
    local changes
    changes=$(git -C "$install_dir" status --porcelain 2>/dev/null)

    if [[ -n "$changes" ]]; then
        echo -e "${YELLOW}⚠ Local changes detected:${NC}"
        echo ""
        # Show modified files (limit to 10 for readability)
        echo "$changes" | head -10 | while read -r line; do
            echo -e "    ${CYAN}$line${NC}"
        done
        local change_count
        change_count=$(echo "$changes" | wc -l | tr -d ' ')
        if [[ "$change_count" -gt 10 ]]; then
            echo -e "    ${DIM}... and $((change_count - 10)) more files${NC}"
        fi
        echo ""
        echo "These changes will conflict with the update."
        echo ""
        echo "Options:"
        echo -e "  ${WHITE}1)${NC} Stash changes (save temporarily, can restore later)"
        echo -e "  ${WHITE}2)${NC} Discard changes (reset to clean state - ${RED}LOSES YOUR CHANGES${NC})"
        echo -e "  ${WHITE}3)${NC} Abort (handle manually)"
        echo ""
        read -rp "Choice [1/2/3]: " choice

        case "$choice" in
            1|"")
                info "Stashing local changes..."
                local stash_msg="moav-update-$(date +%Y%m%d-%H%M%S)"
                if git -C "$install_dir" stash push -m "$stash_msg" --include-untracked; then
                    success "Changes stashed"
                    echo ""
                    echo -e "${CYAN}To restore your changes later:${NC}"
                    echo -e "  ${WHITE}cd $install_dir && git stash pop${NC}"
                    echo ""
                    echo -e "${DIM}Or view stashed changes: git stash list${NC}"
                    echo ""
                else
                    error "Failed to stash changes"
                    echo "  Try manually: cd $install_dir && git stash"
                    return 1
                fi
                ;;
            2)
                echo ""
                echo -e "${RED}WARNING: This will permanently discard all local changes!${NC}"
                read -rp "Are you sure? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    info "Discarding local changes..."
                    git -C "$install_dir" checkout -- . 2>/dev/null
                    git -C "$install_dir" clean -fd 2>/dev/null
                    success "Local changes discarded"
                    echo ""
                else
                    info "Aborted"
                    return 0
                fi
                ;;
            3|*)
                info "Aborted. Handle changes manually:"
                echo ""
                echo -e "  ${WHITE}cd $install_dir${NC}"
                echo -e "  ${WHITE}git status${NC}           # View changes"
                echo -e "  ${WHITE}git stash${NC}            # Save changes temporarily"
                echo -e "  ${WHITE}git checkout -- .${NC}    # Discard changes"
                echo -e "  ${WHITE}moav update${NC}          # Try again"
                echo ""
                return 0
                ;;
        esac
    fi

    # Fetch latest from remote
    info "Fetching from remote..."
    if ! git -C "$install_dir" fetch --all --prune 2>/dev/null; then
        warn "Failed to fetch, continuing with local data..."
    fi

    # Switch branch if requested
    if [[ -n "$target_branch" && "$target_branch" != "$current_branch" ]]; then
        info "Switching to branch: $target_branch"

        # Check if branch exists (locally or on remote)
        if ! git -C "$install_dir" show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null && \
           ! git -C "$install_dir" show-ref --verify --quiet "refs/remotes/origin/$target_branch" 2>/dev/null; then
            error "Branch '$target_branch' does not exist"
            echo ""
            echo "Available branches:"
            git -C "$install_dir" branch -a | sed 's/^/  /' | head -15
            return 1
        fi

        # Checkout the branch
        if ! git -C "$install_dir" checkout "$target_branch" 2>/dev/null; then
            error "Failed to checkout branch '$target_branch'"
            return 1
        fi
        success "Switched to branch: $target_branch"
        current_branch="$target_branch"
    fi

    # Pull latest changes
    info "Pulling latest changes..."
    if git -C "$install_dir" pull origin "$current_branch" 2>/dev/null || git -C "$install_dir" pull; then
        echo ""
        local new_commit
        new_commit=$(git -C "$install_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local new_branch
        new_branch=$(git -C "$install_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

        if [[ "$current_commit" == "$new_commit" ]]; then
            success "Already up to date (branch: $new_branch)"
        else
            success "Updated: $current_commit → $new_commit (branch: $new_branch)"
        fi

        # Check for component version updates
        check_component_versions
    else
        error "Failed to update. Check your network connection or git status."
        echo ""
        echo "Troubleshooting:"
        echo "  - Check network: ping github.com"
        echo "  - View git status: cd $install_dir && git status"
        echo "  - See docs: https://github.com/shayanb/MoaV/blob/main/docs/TROUBLESHOOTING.md#git-update-issues"
        return 1
    fi
}

# Check if component versions in .env are outdated compared to .env.example
check_component_versions() {
    local env_file="$SCRIPT_DIR/.env"
    local example_file="$SCRIPT_DIR/.env.example"

    # Skip if .env doesn't exist
    [[ ! -f "$env_file" ]] && return 0
    [[ ! -f "$example_file" ]] && return 0

    # List of version variables to check
    local version_vars=(
        "SINGBOX_VERSION"
        "WSTUNNEL_VERSION"
        "CONDUIT_VERSION"
        "SNOWFLAKE_VERSION"
        "TRUSTTUNNEL_VERSION"
        "TRUSTTUNNEL_CLIENT_VERSION"
    )

    local updates_available=()
    local services_to_rebuild=()

    for var in "${version_vars[@]}"; do
        local current_val example_val
        current_val=$(grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        example_val=$(grep "^${var}=" "$example_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")

        # Skip if either is empty
        [[ -z "$current_val" || -z "$example_val" ]] && continue

        # Check if versions differ
        if [[ "$current_val" != "$example_val" ]]; then
            updates_available+=("$var:$current_val:$example_val")

            # Map version var to service name for rebuild command
            case "$var" in
                SINGBOX_VERSION) services_to_rebuild+=("sing-box") ;;
                WSTUNNEL_VERSION) services_to_rebuild+=("wstunnel") ;;
                CONDUIT_VERSION) services_to_rebuild+=("psiphon-conduit") ;;
                SNOWFLAKE_VERSION) services_to_rebuild+=("snowflake") ;;
                TRUSTTUNNEL_VERSION|TRUSTTUNNEL_CLIENT_VERSION)
                    # Only add trusttunnel once
                    if [[ ! " ${services_to_rebuild[*]} " =~ " trusttunnel " ]]; then
                        services_to_rebuild+=("trusttunnel")
                    fi
                    ;;
            esac
        fi
    done

    # No updates available
    [[ ${#updates_available[@]} -eq 0 ]] && return 0

    echo ""
    info "Component updates available:"
    echo ""

    for update in "${updates_available[@]}"; do
        local var current new
        var=$(echo "$update" | cut -d: -f1)
        current=$(echo "$update" | cut -d: -f2)
        new=$(echo "$update" | cut -d: -f3)
        printf "  %-28s %s → ${GREEN}%s${NC}\n" "$var:" "$current" "$new"
    done

    echo ""
    read -r -p "Update component versions in .env? [y/N] " update_versions

    if [[ "$update_versions" =~ ^[Yy]$ ]]; then
        for update in "${updates_available[@]}"; do
            local var new
            var=$(echo "$update" | cut -d: -f1)
            new=$(echo "$update" | cut -d: -f3)

            # Update the version in .env
            if grep -q "^${var}=" "$env_file"; then
                sed -i "s/^${var}=.*/${var}=${new}/" "$env_file"
            else
                # Add if not present
                echo "${var}=${new}" >> "$env_file"
            fi
        done

        success "Component versions updated in .env"
        echo ""

        # Show rebuild command
        if [[ ${#services_to_rebuild[@]} -gt 0 ]]; then
            local services_str="${services_to_rebuild[*]}"
            echo -e "To apply updates, rebuild the affected containers:"
            echo ""
            echo -e "  ${WHITE}moav build ${services_str} --no-cache${NC}"
            echo ""
            echo -e "Or rebuild all: ${WHITE}moav build --no-cache${NC}"
        fi
    else
        echo ""
        echo "Versions not updated. To update later, compare:"
        echo "  .env.example (new versions) vs .env (your versions)"
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

    # Detect and save SERVER_IP to .env if not already set
    local current_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -z "$current_ip" ]]; then
        info "Detecting server public IP..."
        local detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
        if [[ -n "$detected_ip" ]]; then
            success "Detected IP: $detected_ip"
            # Save to .env for future use
            if grep -q "^SERVER_IP=" .env 2>/dev/null; then
                sed -i "s|^SERVER_IP=.*|SERVER_IP=\"$detected_ip\"|" .env
            else
                echo "SERVER_IP=\"$detected_ip\"" >> .env
            fi
            info "SERVER_IP saved to .env"
        else
            warn "Could not detect server IP - admin URL may show 'localhost'"
        fi
    fi

    info "Building bootstrap container..."
    docker compose --profile setup build bootstrap

    echo ""
    info "Running bootstrap..."
    if ! docker compose --profile setup run --rm bootstrap; then
        echo ""
        error "Bootstrap failed!"
        echo ""
        echo "Check the error messages above and fix the issues."
        echo "Common fixes:"
        echo "  • Set DOMAIN in .env, or disable TLS protocols"
        echo "  • Ensure DNS is configured correctly"
        echo "  • Check that required ports are available"
        return 1
    fi

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
        # Check DNS setup if dnstt is selected
        check_dns_for_dnstt

        echo ""
        info "Building selected services..."
        docker compose $SELECTED_PROFILE_STRING build

        echo ""
        if confirm "Start services now?" "y"; then
            # Ensure CLASH_API_SECRET is configured for monitoring
            local skip_monitoring=0
            ensure_clash_api_secret "$SELECTED_PROFILE_STRING" || skip_monitoring=1
            if [[ $skip_monitoring -eq 1 ]]; then
                # Remove monitoring from selected profiles
                SELECTED_PROFILE_STRING=$(echo "$SELECTED_PROFILE_STRING" | sed 's/--profile monitoring//g')
            fi

            info "Starting services..."
            docker compose $SELECTED_PROFILE_STRING up -d --remove-orphans
            echo ""
            success "Services started!"

            # Show URLs
            if echo "$SELECTED_PROFILE_STRING" | grep -qE "admin|all"; then
                echo -e "  ${CYAN}Admin Dashboard:${NC} $(get_admin_url)"
            fi
            if echo "$SELECTED_PROFILE_STRING" | grep -qE "monitoring"; then
                echo -e "  ${CYAN}Grafana:${NC}         $(get_grafana_url)"
            fi
            echo ""
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
# DNS Setup (for dnstt)
# =============================================================================

check_dns_for_dnstt() {
    # Check if dnstt is in selected profiles
    local has_dnstt=false
    for p in "${SELECTED_PROFILES[@]}"; do
        if [[ "$p" == "dnstt" || "$p" == "all" ]]; then
            has_dnstt=true
            break
        fi
    done

    if ! $has_dnstt; then
        return 0
    fi

    # Check if port 53 is in use
    if ss -ulnp 2>/dev/null | grep -q ':53 ' || netstat -ulnp 2>/dev/null | grep -q ':53 '; then
        echo ""
        warn "Port 53 is in use (likely by systemd-resolved)"
        echo "  dnstt requires port 53 to be free."
        echo ""

        if confirm "Disable systemd-resolved and configure direct DNS?" "y"; then
            setup_dns_for_dnstt
        else
            warn "dnstt may not work until port 53 is freed."
            echo "  Run 'moav setup-dns' later to fix this."
        fi
    fi
}

setup_dns_for_dnstt() {
    info "Setting up DNS for dnstt..."

    # Check if systemd-resolved is running
    if systemctl is-active systemd-resolved &>/dev/null; then
        info "  Stopping systemd-resolved..."
        sudo systemctl stop systemd-resolved 2>/dev/null || true
        sudo systemctl disable systemd-resolved 2>/dev/null || true
        success "    systemd-resolved stopped and disabled"
    fi

    # Check if /etc/resolv.conf is a symlink (common with systemd-resolved)
    if [[ -L /etc/resolv.conf ]]; then
        info "  Removing resolv.conf symlink..."
        sudo rm -f /etc/resolv.conf
    fi

    # Set up direct DNS resolution
    info "  Configuring direct DNS resolution..."
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
    success "    DNS configured (1.1.1.1, 8.8.8.8)"

    echo ""
    success "DNS setup complete. Port 53 is now available for dnstt."
}

cmd_setup_dns() {
    print_section "Setup DNS for dnstt"

    info "This will:"
    echo "  • Stop and disable systemd-resolved"
    echo "  • Configure direct DNS resolution (1.1.1.1, 8.8.8.8)"
    echo "  • Free port 53 for dnstt"
    echo ""

    if ! confirm "Continue?" "y"; then
        info "Cancelled."
        exit 0
    fi

    echo ""
    setup_dns_for_dnstt
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
    # Get all defined services from docker-compose
    local all_services
    all_services=$(docker compose --profile all config --services 2>/dev/null | sort)

    # Get service status from docker compose (including stopped with -a)
    local raw_status json_lines
    raw_status=$(docker compose --profile all ps -a --format json 2>/dev/null)

    # Read ENABLE_* settings to determine which services are disabled
    local env_file="$SCRIPT_DIR/.env"
    declare -A disabled_services

    if [[ -f "$env_file" ]]; then
        local enable_reality=$(grep "^ENABLE_REALITY=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_trojan=$(grep "^ENABLE_TROJAN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_hysteria2=$(grep "^ENABLE_HYSTERIA2=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_wireguard=$(grep "^ENABLE_WIREGUARD=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_dnstt=$(grep "^ENABLE_DNSTT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_admin=$(grep "^ENABLE_ADMIN_UI=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")

        # Mark services as disabled based on ENABLE_* settings
        # sing-box handles Reality, Trojan, Hysteria2
        if [[ "$enable_reality" != "true" ]] && [[ "$enable_trojan" != "true" ]] && [[ "$enable_hysteria2" != "true" ]]; then
            disabled_services["sing-box"]=1
            disabled_services["decoy"]=1
        fi
        [[ "$enable_wireguard" != "true" ]] && disabled_services["wireguard"]=1 && disabled_services["wstunnel"]=1
        [[ "$enable_dnstt" != "true" ]] && disabled_services["dnstt"]=1
        [[ "$enable_admin" != "true" ]] && disabled_services["admin"]=1
    fi

    print_section "Service Status"
    echo ""
    echo -e "  ${CYAN}┌──────────────────────┬──────────────┬─────────────────────┬──────────────┬─────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC} ${WHITE}Service${NC}              ${CYAN}│${NC} ${WHITE}Status${NC}       ${CYAN}│${NC} ${WHITE}Last Run${NC}            ${CYAN}│${NC} ${WHITE}Uptime${NC}       ${CYAN}│${NC} ${WHITE}Ports${NC}           ${CYAN}│${NC}"
    echo -e "  ${CYAN}├──────────────────────┼──────────────┼─────────────────────┼──────────────┼─────────────────┤${NC}"

    # Track which services we've displayed
    declare -A displayed_services

    # Handle both JSON array format and NDJSON (one object per line)
    if [[ -n "$raw_status" ]] && [[ "$raw_status" != "[]" ]]; then
        if [[ "$raw_status" == "["* ]]; then
            # Convert JSON array to one object per line (split on },{ )
            json_lines=$(echo "$raw_status" | sed 's/^\[//;s/\]$//;s/},{/}\n{/g')
        else
            json_lines="$raw_status"
        fi

        # Parse JSON and display each service (using here-string to avoid subshell)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            local name service state ports health status_str created_at uptime last_run finished_at
            # Parse JSON fields (handle both "Key":"value" and "Key": "value" formats)
            name=$(echo "$line" | grep -oE '"Name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            service=$(echo "$line" | grep -oE '"Service"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            state=$(echo "$line" | grep -oE '"State"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            health=$(echo "$line" | grep -oE '"Health"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            status_str=$(echo "$line" | grep -oE '"Status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            created_at=$(echo "$line" | grep -oE '"CreatedAt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            ports=$(echo "$line" | grep -o '"Publishers":\[[^]]*\]' | grep -o '"PublishedPort":[0-9]*' | cut -d':' -f2 | sort -u | grep -v '^0$' | tr '\n' ',' | sed 's/,$//' || true)

            [[ -z "$name" ]] && continue

            # If Service field is missing, try to find matching service from all_services
            if [[ -z "$service" ]]; then
                local stripped="${name#moav-}"
                # Check if any service name contains or matches the stripped container name
                while IFS= read -r candidate; do
                    [[ -z "$candidate" ]] && continue
                    # Match: "psiphon-conduit" contains "conduit", or "sing-box" == "sing-box"
                    if [[ "$candidate" == *"$stripped"* ]] || [[ "$stripped" == "$candidate" ]]; then
                        service="$candidate"
                        break
                    fi
                done <<< "$all_services"
            fi

            # Use service name for display (fall back to stripped container name if still unknown)
            local short_name="${service:-${name#moav-}}"
            # Track by service name to avoid duplicates
            [[ -n "$service" ]] && displayed_services["$service"]=1

            # Format last run datetime
            last_run="-"
            if [[ -n "$created_at" ]]; then
                last_run=$(echo "$created_at" | cut -d' ' -f1,2)
            fi

            # For stopped containers, try to get finished time
            if [[ "$state" == "exited" ]]; then
                # Try to get FinishedAt from docker inspect
                finished_at=$(docker inspect --format '{{.State.FinishedAt}}' "$name" 2>/dev/null | cut -d'T' -f1,2 | tr 'T' ' ' | cut -d'.' -f1)
                if [[ -n "$finished_at" ]] && [[ "$finished_at" != "0001-01-01" ]]; then
                    last_run="$finished_at"
                fi
            fi

            # Parse uptime from Status field
            uptime="-"
            if [[ "$state" == "running" ]] && [[ "$status_str" =~ ^Up[[:space:]]+(.*) ]]; then
                uptime="${BASH_REMATCH[1]}"
                uptime="${uptime%% (*}"
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
                status_color="${DIM}"
                status_display="○ exited "
                uptime="-"
            else
                status_color="${YELLOW}"
                status_display="◐ ${state}"
            fi

            [[ -z "$ports" ]] && ports="-"

            # Check if service is disabled and add indicator
            local display_name="$short_name"
            local name_color=""
            if [[ -n "${disabled_services[$short_name]:-}" ]]; then
                display_name="${short_name}*"
                name_color="${DIM}"
            fi

            # Note: %-14s for status to account for 3-byte Unicode symbols (●○◐) displaying as 1 char
            printf "  ${CYAN}│${NC} ${name_color}%-20s${NC} ${CYAN}│${NC} ${status_color}%-14s${NC} ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-15s ${CYAN}│${NC}\n" \
                "$display_name" "$status_display" "$last_run" "$uptime" "$ports"
        done <<< "$json_lines"
    fi

    # Show services that have never been started (not in docker ps -a)
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if [[ -z "${displayed_services[$service]:-}" ]]; then
            # Check if service is disabled
            local display_name="$service"
            local name_color="${DIM}"
            if [[ -n "${disabled_services[$service]:-}" ]]; then
                display_name="${service}*"
            fi

            printf "  ${CYAN}│${NC} ${name_color}%-20s${NC} ${CYAN}│${NC} ${DIM}%-12s${NC} ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-15s ${CYAN}│${NC}\n" \
                "$display_name" "- never" "-" "-" "-"
        fi
    done <<< "$all_services"

    echo -e "  ${CYAN}└──────────────────────┴──────────────┴─────────────────────┴──────────────┴─────────────────┘${NC}"

    # Show legend if there are disabled services
    local has_disabled=false
    for key in "${!disabled_services[@]}"; do
        has_disabled=true
        break
    done
    if [[ "$has_disabled" == "true" ]]; then
        echo -e "  ${DIM}* = disabled in .env (won't start with 'moav start')${NC}"
    fi

    # Explain certbot status (often confusing to users)
    echo ""
    echo -e "  ${DIM}Note: certbot is a one-time service that obtains SSL certificates.${NC}"
    echo -e "  ${DIM}      Status 'Exited (0)' means it completed successfully.${NC}"
    echo ""
}

# Display service selection menu and populate SELECTED_PROFILES array
# Usage: select_profiles [mode]
#   mode: "save" to update .env, "start" for start menu, "stop" for stop menu
select_profiles() {
    local mode="${1:-}"
    SELECTED_PROFILES=()

    case "$mode" in
        start)   print_section "Start Services" ;;
        stop)    print_section "Stop Services" ;;
        restart) print_section "Restart Services" ;;
        *)       print_section "Select Services" ;;
    esac

    # Read ENABLE_* settings to show disabled status
    local env_file="$SCRIPT_DIR/.env"
    local proxy_enabled=true
    local wg_enabled=true
    local dnstt_enabled=true
    local amneziawg_enabled=true
    local trusttunnel_enabled=true
    local admin_enabled=true

    if [[ -f "$env_file" ]]; then
        local enable_reality=$(grep "^ENABLE_REALITY=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_trojan=$(grep "^ENABLE_TROJAN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_hysteria2=$(grep "^ENABLE_HYSTERIA2=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_wireguard=$(grep "^ENABLE_WIREGUARD=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_amneziawg=$(grep "^ENABLE_AMNEZIAWG=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_dnstt=$(grep "^ENABLE_DNSTT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_trusttunnel=$(grep "^ENABLE_TRUSTTUNNEL=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_admin=$(grep "^ENABLE_ADMIN_UI=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")

        # proxy is disabled if all three protocols are disabled
        if [[ "$enable_reality" != "true" ]] && [[ "$enable_trojan" != "true" ]] && [[ "$enable_hysteria2" != "true" ]]; then
            proxy_enabled=false
        fi
        [[ "$enable_wireguard" != "true" ]] && wg_enabled=false
        [[ "$enable_amneziawg" != "true" ]] && amneziawg_enabled=false
        [[ "$enable_dnstt" != "true" ]] && dnstt_enabled=false
        [[ "$enable_trusttunnel" != "true" ]] && trusttunnel_enabled=false
        [[ "$enable_admin" != "true" ]] && admin_enabled=false
    fi

    # Build menu lines with disabled indicators
    local proxy_line wg_line amneziawg_line dnstt_line trusttunnel_line admin_line

    if [[ "$proxy_enabled" == "true" ]]; then
        proxy_line="  ${CYAN}│${NC}  ${GREEN}1${NC}   proxy        Reality, Trojan, Hysteria2 (v2ray apps)       ${CYAN}│${NC}"
    else
        proxy_line="  ${CYAN}│${NC}  ${DIM}1   proxy        Reality, Trojan, Hysteria2 (disabled)${NC}        ${CYAN}│${NC}"
    fi

    if [[ "$wg_enabled" == "true" ]]; then
        wg_line="  ${CYAN}│${NC}  ${GREEN}2${NC}   wireguard    WireGuard VPN + WebSocket tunnel              ${CYAN}│${NC}"
    else
        wg_line="  ${CYAN}│${NC}  ${DIM}2   wireguard    WireGuard VPN (disabled)${NC}                      ${CYAN}│${NC}"
    fi

    if [[ "$amneziawg_enabled" == "true" ]]; then
        amneziawg_line="  ${CYAN}│${NC}  ${GREEN}3${NC}   amneziawg    AmneziaWG (obfuscated WireGuard)               ${CYAN}│${NC}"
    else
        amneziawg_line="  ${CYAN}│${NC}  ${DIM}3   amneziawg    AmneziaWG (disabled)${NC}                         ${CYAN}│${NC}"
    fi

    if [[ "$dnstt_enabled" == "true" ]]; then
        dnstt_line="  ${CYAN}│${NC}  ${YELLOW}4${NC}   dnstt        DNS tunnel ${DIM}(slow, last resort)${NC}                ${CYAN}│${NC}"
    else
        dnstt_line="  ${CYAN}│${NC}  ${DIM}4   dnstt        DNS tunnel (disabled)${NC}                        ${CYAN}│${NC}"
    fi

    if [[ "$trusttunnel_enabled" == "true" ]]; then
        trusttunnel_line="  ${CYAN}│${NC}  ${GREEN}5${NC}   trusttunnel  TrustTunnel VPN (HTTP/2 + QUIC)               ${CYAN}│${NC}"
    else
        trusttunnel_line="  ${CYAN}│${NC}  ${DIM}5   trusttunnel  TrustTunnel VPN (disabled)${NC}                    ${CYAN}│${NC}"
    fi

    if [[ "$admin_enabled" == "true" ]]; then
        admin_line="  ${CYAN}│${NC}  ${GREEN}6${NC}   admin        Stats dashboard (port 9443)                   ${CYAN}│${NC}"
    else
        admin_line="  ${CYAN}│${NC}  ${DIM}6   admin        Stats dashboard (disabled)${NC}                   ${CYAN}│${NC}"
    fi

    echo ""
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  ${WHITE}#${NC}   ${WHITE}Profile${NC}      ${WHITE}Description${NC}                                   ${CYAN}│${NC}"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "$proxy_line"
    echo -e "$wg_line"
    echo -e "$amneziawg_line"
    echo -e "$dnstt_line"
    echo -e "$trusttunnel_line"
    echo -e "$admin_line"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${CYAN}│${NC}  ${BLUE}7${NC}   conduit      Donate bandwidth via Psiphon                  ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${BLUE}8${NC}   snowflake    Donate bandwidth via Tor                      ${CYAN}│${NC}"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${CYAN}│${NC}  ${BLUE}9${NC}   monitoring   Grafana + Prometheus (requires 2GB RAM)       ${CYAN}│${NC}"
    echo -e "  ${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}a${NC}   ${GREEN}ALL${NC}          All services ${GREEN}(Recommended)${NC}                    ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${DIM}0${NC}   ${DIM}Back${NC}         Back to main menu                             ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    prompt "Enter choices (e.g., 1 2 4 or 1,2,4 or 'a' for all): "
    read -r choices < /dev/tty 2>/dev/null || choices=""

    if [[ "$choices" == "0" || -z "$choices" ]]; then
        return 2  # Return 2 to signal "go back" vs 1 for error
    fi

    # Support both space and comma separators
    choices="${choices//,/ }"

    if [[ "$choices" == "a" || "$choices" == "A" ]]; then
        # Build profile list based on ENABLE_* settings in .env
        # This way "all" means "all enabled services", not literally everything
        local env_file="$SCRIPT_DIR/.env"

        # Check which protocols are enabled
        local enable_reality=$(grep "^ENABLE_REALITY=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_trojan=$(grep "^ENABLE_TROJAN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_hysteria2=$(grep "^ENABLE_HYSTERIA2=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_wireguard=$(grep "^ENABLE_WIREGUARD=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_amneziawg=$(grep "^ENABLE_AMNEZIAWG=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_dnstt=$(grep "^ENABLE_DNSTT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_trusttunnel=$(grep "^ENABLE_TRUSTTUNNEL=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        local enable_admin=$(grep "^ENABLE_ADMIN_UI=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")

        # Build profiles list based on enabled services
        SELECTED_PROFILES=()

        # proxy profile (Reality, Trojan, Hysteria2)
        if [[ "$enable_reality" == "true" ]] || [[ "$enable_trojan" == "true" ]] || [[ "$enable_hysteria2" == "true" ]]; then
            SELECTED_PROFILES+=("proxy")
        fi

        # wireguard profile
        if [[ "$enable_wireguard" == "true" ]]; then
            SELECTED_PROFILES+=("wireguard")
        fi

        # amneziawg profile
        if [[ "$enable_amneziawg" == "true" ]]; then
            SELECTED_PROFILES+=("amneziawg")
        fi

        # dnstt profile
        if [[ "$enable_dnstt" == "true" ]]; then
            SELECTED_PROFILES+=("dnstt")
        fi

        # trusttunnel profile
        if [[ "$enable_trusttunnel" == "true" ]]; then
            SELECTED_PROFILES+=("trusttunnel")
        fi

        # admin profile
        if [[ "$enable_admin" == "true" ]]; then
            SELECTED_PROFILES+=("admin")
        fi

        # Always include donation services when selecting "all"
        SELECTED_PROFILES+=("conduit")
        SELECTED_PROFILES+=("snowflake")

        # Check if monitoring should be included
        local enable_monitoring=$(grep "^ENABLE_MONITORING=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        if [[ "$enable_monitoring" == "true" ]]; then
            SELECTED_PROFILES+=("monitoring")
        elif [[ "$enable_monitoring" != "false" ]]; then
            # Not explicitly set - ask user
            echo ""
            warn "Monitoring stack (Grafana + Prometheus) requires at least 2GB RAM."
            if confirm "Enable monitoring?" "n"; then
                # Update .env to enable monitoring
                if grep -q "^ENABLE_MONITORING=" "$env_file" 2>/dev/null; then
                    sed -i.bak "s/^ENABLE_MONITORING=.*/ENABLE_MONITORING=true/" "$env_file"
                    rm -f "$env_file.bak"
                else
                    # Add if not present
                    echo "ENABLE_MONITORING=true" >> "$env_file"
                fi
                SELECTED_PROFILES+=("monitoring")
                success "Monitoring enabled"
            else
                # Explicitly disable to avoid asking again
                if grep -q "^ENABLE_MONITORING=" "$env_file" 2>/dev/null; then
                    sed -i.bak "s/^ENABLE_MONITORING=.*/ENABLE_MONITORING=false/" "$env_file"
                    rm -f "$env_file.bak"
                else
                    echo "ENABLE_MONITORING=false" >> "$env_file"
                fi
                info "Monitoring skipped. Enable later with: moav start monitoring"
            fi
        fi
        # If explicitly false, don't include monitoring

        # If nothing enabled (shouldn't happen), fall back to donation-only
        if [[ ${#SELECTED_PROFILES[@]} -eq 0 ]]; then
            SELECTED_PROFILES=("conduit" "snowflake")
        fi

        # Show what "all enabled" actually means
        echo ""
        info "Selected profiles based on your configuration: ${SELECTED_PROFILES[*]}"
    else
        for choice in $choices; do
            case $choice in
                1) SELECTED_PROFILES+=("proxy") ;;
                2) SELECTED_PROFILES+=("wireguard") ;;
                3) SELECTED_PROFILES+=("amneziawg") ;;
                4) SELECTED_PROFILES+=("dnstt") ;;
                5) SELECTED_PROFILES+=("trusttunnel") ;;
                6) SELECTED_PROFILES+=("admin") ;;
                7) SELECTED_PROFILES+=("conduit") ;;
                8) SELECTED_PROFILES+=("snowflake") ;;
                9) SELECTED_PROFILES+=("monitoring") ;;
            esac
        done
    fi

    # dnstt requires sing-box (proxy profile) to forward traffic
    # Auto-add proxy if dnstt is selected but proxy isn't (only for start operations)
    if [[ "$mode" != "stop" ]] && [[ "$mode" != "restart" ]]; then
        local has_dnstt=false has_proxy=false
        for p in "${SELECTED_PROFILES[@]}"; do
            [[ "$p" == "dnstt" ]] && has_dnstt=true
            [[ "$p" == "proxy" ]] && has_proxy=true
        done
        if [[ "$has_dnstt" == "true" ]] && [[ "$has_proxy" == "false" ]]; then
            info "dnstt requires proxy services - auto-adding proxy profile"
            SELECTED_PROFILES+=("proxy")
        fi
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
    if [[ "$mode" == "save" ]]; then
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

    # Update or add DEFAULT_PROFILES in .env (with quotes to handle spaces)
    if grep -q "^DEFAULT_PROFILES=" "$env_file" 2>/dev/null; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^DEFAULT_PROFILES=.*/DEFAULT_PROFILES=\"$profiles_str\"/" "$env_file"
        else
            sed -i "s/^DEFAULT_PROFILES=.*/DEFAULT_PROFILES=\"$profiles_str\"/" "$env_file"
        fi
    else
        # Add new line
        echo "" >> "$env_file"
        echo "# Default profiles for 'moav start'" >> "$env_file"
        echo "DEFAULT_PROFILES=\"$profiles_str\"" >> "$env_file"
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

# Ensure CLASH_API_SECRET is set in .env for monitoring
# This is needed for clash-exporter to authenticate with sing-box Clash API
# Returns: 0 = continue, 1 = skip monitoring (user declined when using 'all' profile)
ensure_clash_api_secret() {
    local profiles="$1"
    local env_file="$SCRIPT_DIR/.env"

    # Only needed if monitoring or all profile is being started
    if ! echo "$profiles" | grep -qE "monitoring|all"; then
        return 0
    fi

    # Check if ENABLE_MONITORING is explicitly set to false
    local enable_monitoring
    enable_monitoring=$(grep "^ENABLE_MONITORING=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
    if [[ "$enable_monitoring" == "false" ]]; then
        echo ""
        warn "Monitoring is currently disabled in .env (ENABLE_MONITORING=false)"
        if confirm "Enable monitoring?" "y"; then
            # Update ENABLE_MONITORING to true in .env
            sed -i.bak "s/^ENABLE_MONITORING=false/ENABLE_MONITORING=true/" "$env_file"
            rm -f "$env_file.bak"
            success "ENABLE_MONITORING set to true"
        else
            info "Skipping monitoring. Starting other services..."
            return 1  # Signal caller to skip monitoring
        fi
    fi

    # Check if CLASH_API_SECRET is already set in .env (non-empty)
    # Note: || true needed because set -o pipefail causes exit if grep finds nothing
    local current_secret
    current_secret=$(grep "^CLASH_API_SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)

    # Get the authoritative secret from state volume (source of truth from bootstrap)
    local state_secret
    state_secret=$(docker run --rm -v moav_moav_state:/state alpine cat /state/keys/clash-api.env 2>/dev/null | grep "^CLASH_API_SECRET=" | cut -d'=' -f2 || true)

    # If .env matches state, we're good
    if [[ -n "$current_secret" ]] && [[ "$current_secret" == "$state_secret" ]]; then
        return 0  # Already configured and in sync
    fi

    # If .env has a value but it doesn't match state, it's stale
    if [[ -n "$current_secret" ]] && [[ -n "$state_secret" ]] && [[ "$current_secret" != "$state_secret" ]]; then
        warn "CLASH_API_SECRET in .env doesn't match state volume (stale after re-bootstrap)"
        info "Syncing CLASH_API_SECRET from state volume..."
        sed -i.bak "s/^CLASH_API_SECRET=.*/CLASH_API_SECRET=$state_secret/" "$env_file"
        rm -f "$env_file.bak"
        success "CLASH_API_SECRET synced"
        return 0
    fi

    # .env is empty — first-time monitoring setup
    # If using 'all' profile, ask user if they want to enable monitoring (requires 2GB RAM)
    if [[ -z "$current_secret" ]]; then
        if echo "$profiles" | grep -qE "\ball\b|--profile all"; then
            echo ""
            warn "Monitoring requires at least 2GB RAM to run properly."
            echo "  The monitoring stack includes Grafana, Prometheus, and exporters."
            echo ""
            if ! confirm "Enable monitoring? (You can start it later with 'moav start monitoring')" "n"; then
                info "Skipping monitoring. Starting other services..."
                return 1  # Signal caller to skip monitoring
            fi
        fi
    fi

    # Try to use state secret, fall back to sing-box config
    local secret="$state_secret"
    if [[ -z "$secret" ]]; then
        # Try to extract from existing sing-box config.json
        if [[ -f "$SCRIPT_DIR/configs/sing-box/config.json" ]]; then
            secret=$(grep -o '"secret"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCRIPT_DIR/configs/sing-box/config.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
        fi
    fi

    if [[ -n "$secret" ]]; then
        info "Configuring CLASH_API_SECRET for monitoring..."
        # Update .env file
        if grep -q "^CLASH_API_SECRET=" "$env_file" 2>/dev/null; then
            sed -i.bak "s/^CLASH_API_SECRET=.*/CLASH_API_SECRET=$secret/" "$env_file"
            rm -f "$env_file.bak"
        else
            # Append to file
            echo "" >> "$env_file"
            echo "# Clash API secret for monitoring (auto-configured)" >> "$env_file"
            echo "CLASH_API_SECRET=$secret" >> "$env_file"
        fi
        success "CLASH_API_SECRET configured"
    else
        warn "Could not find CLASH_API_SECRET. Clash exporter may not authenticate properly."
        echo "  If sing-box metrics show empty, run: moav bootstrap"
    fi
    return 0
}

start_services() {
    # Use the unified service selection menu
    SELECTED_PROFILE_STRING=""
    local ret=0
    select_profiles "start" || ret=$?
    [[ $ret -eq 2 ]] && return 2  # User chose "Back"
    [[ $ret -ne 0 ]] && return 1

    local profiles="$SELECTED_PROFILE_STRING"
    if [[ -z "$profiles" ]]; then
        warn "No profiles selected"
        return 1
    fi

    # Check if bootstrap has been run
    if ! check_bootstrap; then
        warn "Bootstrap has not been run yet!"
        echo ""
        info "Bootstrap is required for first-time setup."
        echo ""

        if confirm "Run bootstrap now?" "y"; then
            run_bootstrap || return 1
            echo ""
        else
            warn "Cannot start services without bootstrap."
            return 1
        fi
    fi

    # Ensure CLASH_API_SECRET is configured for monitoring
    # Returns 1 if user declined monitoring when using 'all' profile
    local skip_monitoring=0
    ensure_clash_api_secret "$profiles" || skip_monitoring=1
    if [[ $skip_monitoring -eq 1 ]]; then
        # Replace 'all' with individual profiles excluding monitoring
        profiles="--profile proxy --profile wireguard --profile dnstt --profile trusttunnel --profile admin --profile conduit --profile snowflake"
    fi

    echo ""
    info "Building containers (if needed)..."

    local cmd="docker compose $profiles up -d --remove-orphans"

    if run_command "$cmd" "Starting services"; then
        echo ""
        success "Services started!"
        echo ""
        # Show admin URL if admin was started
        if echo "$profiles" | grep -qE "admin|all"; then
            echo -e "  ${CYAN}Admin Dashboard:${NC} $(get_admin_url)"
        fi
        # Show Grafana URL if monitoring was started
        if echo "$profiles" | grep -qE "monitoring|all"; then
            echo -e "  ${CYAN}Grafana:${NC}         $(get_grafana_url)"
            local grafana_cdn=$(get_grafana_cdn_url)
            if [[ -n "$grafana_cdn" ]]; then
                echo -e "  ${CYAN}Grafana (CDN):${NC}   $grafana_cdn"
            fi
        fi

        if echo "$profiles" | grep -qE "admin|monitoring|all"; then
            echo ""
        fi
        show_log_help
    fi
}

stop_services() {
    # Check if any services are running
    local running_services
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | sort)

    if [[ -z "$running_services" ]]; then
        print_section "Stop Services"
        warn "No services are currently running"
        return 0
    fi

    # Use the unified service selection menu
    SELECTED_PROFILE_STRING=""
    local ret=0
    select_profiles "stop" || ret=$?
    [[ $ret -eq 2 ]] && return 2  # User chose "Back"
    [[ $ret -ne 0 ]] && return 1

    local profiles="$SELECTED_PROFILE_STRING"
    if [[ -z "$profiles" ]]; then
        warn "No profiles selected"
        return 1
    fi

    echo ""
    info "Stopping services..."

    if [[ "$profiles" == "--profile all" ]]; then
        docker compose --profile all stop
    else
        # Stop each selected profile
        docker compose $profiles stop
    fi

    success "Services stopped!"
}

restart_services() {
    # Check if any services are running
    local running_services
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | sort)

    if [[ -z "$running_services" ]]; then
        print_section "Restart Services"
        warn "No services are currently running"
        return 0
    fi

    # Use the unified service selection menu
    SELECTED_PROFILE_STRING=""
    local ret=0
    select_profiles "restart" || ret=$?
    [[ $ret -eq 2 ]] && return 2  # User chose "Back"
    [[ $ret -ne 0 ]] && return 1

    local profiles="$SELECTED_PROFILE_STRING"
    if [[ -z "$profiles" ]]; then
        warn "No profiles selected"
        return 1
    fi

    echo ""
    info "Restarting services..."

    if [[ "$profiles" == "--profile all" ]]; then
        docker compose --profile all restart
    else
        docker compose $profiles restart
    fi

    success "Services restarted!"
}

# Format Docker timestamps from ISO to readable format
# 2026-02-04T20:17:10.426340440Z -> 2026-02-04 20:17:10
format_log_timestamps() {
    sed -u 's/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)T\([0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\)\.[0-9]*Z/\1 \2/g'
}

view_logs() {
    local log_interrupted=false

    while true; do
        log_interrupted=false
        print_section "View Logs"

        # Get all services (running or not)
        local all_services
        all_services=$(docker compose ps --services -a 2>/dev/null | sort)

        echo "Options:"
        echo ""
        echo -e "  ${WHITE}a)${NC} All services (follow)"
        echo -e "  ${WHITE}t)${NC} Last 100 lines + follow (all services)"

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
        echo -e "  ${WHITE}0)${NC} Back to main menu"
        echo ""

        prompt "Choice: "
        read -r choice < /dev/tty 2>/dev/null || choice=""

        case $choice in
            a|A)
                echo ""
                info "Showing logs for all services. Press Ctrl+C to return to menu."
                echo ""
                # Trap SIGINT to return to menu instead of exiting
                trap 'log_interrupted=true' INT
                docker compose --ansi always --profile all logs -t -f 2>/dev/null | format_log_timestamps || true
                trap - INT
                [[ "$log_interrupted" == "true" ]] && echo "" && info "Returning to log menu..."
                ;;
            t|T)
                echo ""
                info "Showing last 100 lines + follow. Press Ctrl+C to return to menu."
                echo ""
                trap 'log_interrupted=true' INT
                docker compose --ansi always --profile all logs -t --tail=100 -f 2>/dev/null | format_log_timestamps || true
                trap - INT
                [[ "$log_interrupted" == "true" ]] && echo "" && info "Returning to log menu..."
                ;;
            0|"")
                return 0
                ;;
            [1-9]*)
                local idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#services_array[@]} ]]; then
                    local service="${services_array[$idx]}"
                    echo ""
                    info "Showing logs for $service. Press Ctrl+C to return to menu."
                    echo ""
                    # Trap SIGINT to return to menu instead of exiting
                    trap 'log_interrupted=true' INT
                    docker compose --ansi always logs -t -f "$service" 2>/dev/null | format_log_timestamps || true
                    trap - INT
                    [[ "$log_interrupted" == "true" ]] && echo "" && info "Returning to log menu..."
                else
                    warn "Invalid choice"
                fi
                ;;
            *)
                warn "Invalid choice"
                ;;
        esac
    done
}

show_log_help() {
    echo -e "${CYAN}Log Commands:${NC}"
    echo "  • View all logs:      docker compose logs -t -f"
    echo "  • View service logs:  docker compose logs -t -f sing-box"
    echo "  • Last 100 lines:     docker compose logs -t --tail=100"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  • Check status:       docker compose ps"
    echo "  • Stop all:           docker compose --profile all stop"
    echo "  • Restart service:    docker compose restart sing-box"
}

# =============================================================================
# User Management
# =============================================================================

user_management() {
    while true; do
        print_section "User Management"

        echo "User management options:"
        echo ""
        echo -e "  ${WHITE}1)${NC} List all users"
        echo -e "  ${WHITE}2)${NC} Add new user"
        echo -e "  ${WHITE}3)${NC} Revoke user"
        echo -e "  ${WHITE}4)${NC} Package user (create zip)"
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
                press_enter
                ;;
            3)
                revoke_user
                press_enter
                ;;
            4)
                package_user
                press_enter
                ;;
            0|q|Q)
                return 0
                ;;
            *)
                ;;
        esac
    done
}

migration_menu() {
    print_section "Export/Import (Migration)"

    echo "Migration options:"
    echo ""
    echo -e "  ${WHITE}1)${NC} Export configuration backup"
    echo -e "  ${WHITE}2)${NC} Import configuration backup"
    echo -e "  ${WHITE}3)${NC} Migrate to new IP address"
    echo -e "  ${WHITE}4)${NC} Regenerate all user bundles"
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
            local current_ipv6=$(grep -E '^SERVER_IPV6=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
            local detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
            local detected_ipv6=$(curl -6 -s --max-time 3 https://api6.ipify.org 2>/dev/null || echo "")
            [[ -n "$current_ip" ]] && echo "Current IP in .env: $current_ip"
            [[ -n "$current_ipv6" ]] && echo "Current IPv6 in .env: $current_ipv6"
            [[ -n "$detected_ip" ]] && echo "Detected server IP: $detected_ip"
            [[ -n "$detected_ipv6" ]] && echo "Detected server IPv6: $detected_ipv6"
            echo ""
            prompt "New IP address: "
            read -r new_ip < /dev/tty 2>/dev/null || new_ip=""
            if [[ -n "$new_ip" ]]; then
                cmd_migrate_ip "$new_ip"
            else
                warn "No IP specified"
            fi
            ;;
        4)
            cmd_regenerate_users
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
    echo "  • sing-box (Reality, Trojan, Hysteria2, CDN VLESS+WS)"
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

package_user() {
    print_section "Package User"

    echo "Current users:"
    list_users
    echo ""

    prompt "Enter username to package: "
    read -r username < /dev/tty 2>/dev/null || username=""

    if [[ -z "$username" ]]; then
        warn "Username cannot be empty"
        return 1
    fi

    local bundle_dir="outputs/bundles/$username"
    if [[ ! -d "$bundle_dir" ]]; then
        error "User bundle not found: $bundle_dir"
        return 1
    fi

    local zip_file="outputs/bundles/${username}-configs.zip"

    # Check for zip command
    if ! command -v zip &>/dev/null; then
        error "zip command not found. Install with: apt install zip"
        return 1
    fi

    info "Creating package for $username..."

    # Create zip from bundle directory
    (cd outputs/bundles && zip -r "${username}-configs.zip" "$username" -x "*.DS_Store")

    if [[ -f "$zip_file" ]]; then
        local size=$(du -h "$zip_file" | cut -f1)
        success "Package created: $zip_file ($size)"
    else
        error "Failed to create package"
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
            # Show admin URL if admin is running
            if echo "$running" | grep -q "admin"; then
                echo -e "  ${CYAN}↳${NC} Admin: ${CYAN}$(get_admin_url)${NC}"
            fi
            # Show Grafana URL if grafana is running
            if echo "$running" | grep -q "grafana"; then
                echo -e "  ${CYAN}↳${NC} Grafana: ${CYAN}$(get_grafana_url)${NC}"
            fi
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
            1) r=0; start_services || r=$?; [[ $r -eq 2 ]] || press_enter ;;
            2) r=0; stop_services || r=$?; [[ $r -eq 2 ]] || press_enter ;;
            3) r=0; restart_services || r=$?; [[ $r -eq 2 ]] || press_enter ;;
            4) show_status; press_enter ;;
            5) view_logs ;;  # view_logs has its own loop, no press_enter needed
            6) user_management ;;  # user_management has its own loop
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
    echo "  uninstall [--wipe]    Remove containers and global command (--wipe removes all data)"
    echo "  update [-b BRANCH]    Update MoaV (git pull), optionally switch branch"
    echo "  check                 Run prerequisites check"
    echo "  bootstrap             Run first-time setup (includes service selection)"
    echo "  domainless            Enable domain-less mode (WireGuard, Conduit, Snowflake only)"
    echo "  profiles              Change default services for 'moav start'"
    echo "  start [PROFILE...]    Start services (uses DEFAULT_PROFILES from .env)"
    echo "  stop [SERVICE...] [-r] Stop services (default: all, -r removes containers)"
    echo "  restart [SERVICE...]  Restart services (default: all)"
    echo "  status                Show service status"
    echo "  logs [SERVICE...] [-n] View logs (default: all, follow mode, -n for no-follow)"
    echo "  users                 List all users"
    echo "  user list             List all users"
    echo "  user add NAME [NAME2...] [-p]  Add user(s) (--package creates zip)"
    echo "  user add --batch N [--prefix P]  Create N users (e.g., user01, user02...)"
    echo "  user revoke NAME      Revoke a user"
    echo "  user package NAME     Create distributable zip for existing user"
    echo "  build [SERVICE|PROFILE] [--no-cache]  Build services or profile"
    echo "  build --local [SERVICE|all]          Build images locally (for blocked registries)"
    echo "  test USERNAME         Test connectivity for a user"
    echo "  client                Client mode (test/connect)"
    echo ""
    echo "Migration:"
    echo "  export [FILE]         Export full config backup (keys, users, .env)"
    echo "  import FILE           Import config backup from file"
    echo "  migrate-ip NEW_IP     Update SERVER_IP and regenerate all configs"
    echo "  regenerate-users      Regenerate all user bundles with current .env"
    echo "  setup-dns             Free port 53 for dnstt (disables systemd-resolved)"
    echo ""
    echo "Profiles: proxy, wireguard, amneziawg, dnstt, trusttunnel, admin, conduit, snowflake, client, all"
    echo "Services: sing-box, decoy, wstunnel, wireguard, amneziawg, dnstt, trusttunnel, admin, psiphon-conduit, snowflake"
    echo "Aliases:  proxy/singbox/reality→sing-box, wg→wireguard, awg→amneziawg, dns→dnstt, conduit→psiphon-conduit"
    echo ""
    echo "Examples:"
    echo "  moav                           # Interactive menu"
    echo "  moav install                   # Install globally (run from anywhere)"
    echo "  moav update                    # Update MoaV (git pull)"
    echo "  moav update -b dev             # Switch to dev branch and update"
    echo "  moav start                     # Start all services"
    echo "  moav start proxy admin         # Start proxy and admin profiles"
    echo "  moav stop conduit              # Stop specific service"
    echo "  moav logs sing-box             # Follow sing-box logs (Ctrl+C to exit)"
    echo "  moav logs -n                   # Show last 100 lines without following"
    echo "  moav build conduit --no-cache  # Rebuild service without cache"
    echo "  moav build monitoring          # Build all services in monitoring profile"
    echo "  moav build --local             # Build blocked images (cadvisor, clash-exporter)"
    echo "  moav build --local prometheus  # Build specific external image locally"
    echo "  moav build --local all         # Build EVERYTHING locally (no registry pulls)"
    echo "  moav profiles                  # Change default services"
    echo "  moav user add john             # Add user 'john'"
    echo "  moav user add john --package   # Add user and create zip bundle"
    echo "  moav user add alice bob charlie  # Add multiple users"
    echo "  moav user add --batch 5        # Create user01..user05"
    echo "  moav user add --batch 10 --prefix team -p  # Create team01..team10 with packages"
    echo "  moav test joe                  # Test connectivity for user joe"
    echo "  moav test joe -v               # Test with verbose output for debugging"
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

cmd_domainless() {
    print_header
    print_section "Enable Domain-less Mode"

    echo ""
    info "Domain-less mode disables TLS-based protocols that require a domain."
    echo ""
    echo -e "  ${YELLOW}Will be disabled:${NC}"
    echo "    • Reality, Trojan, Hysteria2 (sing-box proxy)"
    echo "    • DNS tunnel (dnstt)"
    echo "    • Admin dashboard with HTTPS"
    echo ""
    echo -e "  ${GREEN}Will remain available:${NC}"
    echo "    • WireGuard (direct UDP)"
    echo "    • Psiphon Conduit (bandwidth donation)"
    echo "    • Tor Snowflake (bandwidth donation)"
    echo ""

    if ! confirm "Enable domain-less mode?" "y"; then
        info "Cancelled."
        return 0
    fi

    # Check if .env exists
    if [[ ! -f ".env" ]]; then
        if [[ -f ".env.example" ]]; then
            cp .env.example .env
            success "Created .env from .env.example"
        else
            error ".env file not found"
            return 1
        fi
    fi

    # Disable TLS-based protocols (add if not present, update if present)
    for var in ENABLE_REALITY ENABLE_TROJAN ENABLE_HYSTERIA2 ENABLE_DNSTT ENABLE_ADMIN_UI; do
        if grep -q "^${var}=" .env; then
            sed -i "s/^${var}=.*/${var}=false/" .env
        else
            echo "${var}=false" >> .env
        fi
    done

    # Clear DOMAIN (add if not present)
    if grep -q "^DOMAIN=" .env; then
        sed -i 's/^DOMAIN=.*/DOMAIN=/' .env
    else
        echo "DOMAIN=" >> .env
    fi

    # Set default profiles (add if not present)
    if grep -q "^DEFAULT_PROFILES=" .env; then
        sed -i 's/^DEFAULT_PROFILES=.*/DEFAULT_PROFILES="wireguard conduit snowflake"/' .env
    else
        echo 'DEFAULT_PROFILES="wireguard conduit snowflake"' >> .env
    fi

    echo ""
    success "Domain-less mode enabled!"
    echo ""

    # Verify changes in .env
    info "Settings in .env:"
    grep -E "^(DOMAIN|ENABLE_|DEFAULT_PROFILES)=" .env | head -15
    echo ""

    # Verify docker-compose sees them correctly
    info "Verifying docker-compose reads these values..."
    local compose_check
    compose_check=$(docker compose --profile setup config 2>/dev/null | grep -E "ENABLE_REALITY|ENABLE_TROJAN" | head -2)
    if echo "$compose_check" | grep -q "false"; then
        success "Docker compose sees the correct values"
    else
        warn "Docker compose may not be reading .env correctly!"
        echo "  Docker compose sees:"
        echo "$compose_check"
        echo ""
        echo "  Try running: docker compose --profile setup config | grep ENABLE"
    fi
    echo ""

    # Clear bootstrap flag if exists
    if check_bootstrap; then
        info "Clearing previous bootstrap to regenerate configs..."
        docker run --rm -v moav_moav_state:/state alpine rm -f /state/.bootstrapped 2>/dev/null || true
    fi

    echo ""
    if confirm "Run bootstrap now to generate WireGuard configs?" "y"; then
        run_bootstrap
    else
        info "Run 'moav bootstrap' when ready."
    fi
}

cmd_bootstrap() {
    print_header
    check_prerequisites
    echo ""

    # Check if already bootstrapped
    if check_bootstrap; then
        warn "Bootstrap has already been run!"
        echo ""
        info "Running bootstrap again will:"
        echo "  • Preserve existing keys and secrets (only generate missing ones)"
        echo "  • Preserve existing user credentials (UUIDs, passwords)"
        echo "  • Regenerate config files (sing-box, WireGuard, AmneziaWG)"
        echo "  • Generate configs for any newly enabled protocols"
        echo "  • Obtain TLS certificates if missing"
        echo ""
        info "Existing client configurations will remain valid."
        echo ""
        if ! confirm "Are you sure you want to re-run bootstrap?" "n"; then
            info "Bootstrap cancelled."
            return 0
        fi
        # Clear the bootstrapped flag so bootstrap.sh doesn't exit early
        info "Clearing bootstrap flag..."
        docker run --rm -v moav_moav_state:/state alpine rm -f /state/.bootstrapped
    else
        info "Bootstrap will perform first-time setup:"
        echo "  • Generate encryption keys"
        echo "  • Obtain TLS certificate from Let's Encrypt"
        echo "  • Create initial users"
        echo "  • Generate client configuration bundles"
        echo ""
        if ! confirm "Continue with bootstrap?" "y"; then
            info "Bootstrap cancelled."
            return 0
        fi
    fi

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
    local valid_profiles="proxy wireguard amneziawg dnstt trusttunnel admin conduit snowflake monitoring client all setup"

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
            # No defaults set - show interactive menu
            select_profiles "start"
            if [[ ${#SELECTED_PROFILES[@]} -eq 0 ]]; then
                info "No services selected"
                return 0
            fi
            for p in "${SELECTED_PROFILES[@]}"; do
                profiles+="--profile $p "
            done
        fi
    else
        local individual_services=""
        for p in "$@"; do
            # Resolve profile aliases (e.g., sing-box -> proxy)
            local resolved
            resolved=$(resolve_profile "$p")

            # Check if it's a valid profile
            if echo "$valid_profiles" | grep -qw "$resolved"; then
                profiles+="--profile $resolved "
            else
                # Try resolving as individual service name
                local svc
                svc=$(resolve_service "$p")
                individual_services+="$svc "
            fi
        done

        # If we have individual services but no profiles, figure out which profiles they need
        if [[ -n "$individual_services" ]] && [[ -z "$profiles" ]]; then
            info "Starting individual services: $individual_services"
            docker compose --profile all up -d $individual_services
            success "Services started!"
            return 0
        elif [[ -n "$individual_services" ]]; then
            warn "Ignoring individual services ($individual_services) when mixed with profiles"
        fi
    fi

    if [[ -z "$profiles" ]]; then
        error "No service selected"
        echo "Valid profiles: $valid_profiles"
        echo "Aliases: sing-box/singbox/reality/trojan/hysteria→proxy, wg→wireguard, awg→amneziawg, dns→dnstt, grafana/prometheus→monitoring"
        exit 1
    fi

    # Check if bootstrap has been run (skip for setup profile)
    if [[ ! "$profiles" =~ "setup" ]] && ! check_bootstrap; then
        warn "Bootstrap has not been run yet!"
        echo ""
        info "Bootstrap is required for first-time setup."
        echo "  It generates keys, obtains TLS certificates, and creates users."
        echo ""

        if confirm "Run bootstrap now?" "y"; then
            run_bootstrap || exit 1
            echo ""
        else
            error "Cannot start services without bootstrap."
            echo "  Run 'moav bootstrap' first, or use 'moav' for interactive setup."
            exit 1
        fi
    fi

    # Ensure CLASH_API_SECRET is configured for monitoring
    # Returns 1 if user declined monitoring when using 'all' profile
    local skip_monitoring=0
    ensure_clash_api_secret "$profiles" || skip_monitoring=1
    if [[ $skip_monitoring -eq 1 ]]; then
        # Replace 'all' with individual profiles excluding monitoring
        profiles="--profile proxy --profile wireguard --profile dnstt --profile trusttunnel --profile admin --profile conduit --profile snowflake"
    fi

    # Check port 53 if dnstt is being started
    if echo "$profiles" | grep -qE "dnstt|all"; then
        if ss -ulnp 2>/dev/null | grep -q ':53 ' || netstat -ulnp 2>/dev/null | grep -q ':53 '; then
            echo ""
            warn "Port 53 is in use (likely by systemd-resolved)"
            echo "  dnstt requires port 53 to be free."
            echo ""
            if confirm "Disable systemd-resolved and configure direct DNS?" "y"; then
                setup_dns_for_dnstt
            else
                warn "dnstt may fail to start. Run 'moav setup-dns' later to fix this."
            fi
        fi
    fi

    info "Starting services..."
    docker compose $profiles up -d --remove-orphans
    success "Services started!"
    echo ""
    # Show admin URL if admin was started
    if echo "$profiles" | grep -qE "admin|all"; then
        echo -e "  ${CYAN}Admin Dashboard:${NC} $(get_admin_url)"
    fi
    # Show Grafana URL if monitoring was started
    if echo "$profiles" | grep -qE "monitoring|all"; then
        echo -e "  ${CYAN}Grafana:${NC}         $(get_grafana_url)"
        local grafana_cdn=$(get_grafana_cdn_url)
        if [[ -n "$grafana_cdn" ]]; then
            echo -e "  ${CYAN}Grafana (CDN):${NC}   $grafana_cdn"
        fi
    fi

    if echo "$profiles" | grep -qE "admin|monitoring|proxy|all"; then
        echo ""
    fi
}

# Resolve profile name aliases to actual docker-compose profile names
resolve_profile() {
    local profile="$1"
    case "$profile" in
        sing-box|singbox|sing|reality|trojan|hysteria|hysteria2|hy2)
            echo "proxy" ;;
        wg)
            echo "wireguard" ;;
        awg)
            echo "amneziawg" ;;
        dns)
            echo "dnstt" ;;
        psiphon)
            echo "conduit" ;;
        grafana|grafana-proxy|grafana-cdn|prometheus|metrics)
            echo "monitoring" ;;
        *)
            echo "$profile" ;;
    esac
}

# Resolve service name aliases to actual docker-compose service names
resolve_service() {
    local svc="$1"
    case "$svc" in
        conduit|psiphon)              echo "psiphon-conduit" ;;
        singbox|sing|proxy|reality)   echo "sing-box" ;;
        wg)                           echo "wireguard" ;;
        ws|tunnel)                    echo "wstunnel" ;;
        dns)                          echo "dnstt" ;;
        snow|tor)                     echo "snowflake" ;;
        # Monitoring services (pass through or resolve aliases)
        grafana-cdn)                  echo "grafana-proxy" ;;
        grafana|grafana-proxy|prometheus|cadvisor|node-exporter|clash-exporter|wireguard-exporter|snowflake-exporter|singbox-exporter)
            echo "$svc" ;;
        *)                            echo "$svc" ;;
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
    local remove_containers=false
    local args=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remove|-r)
                remove_containers=true
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#args[@]} -eq 0 ]] || [[ "${args[0]}" == "all" ]]; then
        if [[ "$remove_containers" == "true" ]]; then
            info "Stopping and removing all containers..."
            docker compose --profile all down
            success "All services stopped and removed!"
        else
            info "Stopping all services..."
            docker compose --profile all stop
            success "All services stopped!"
        fi
    else
        # Check if argument is a profile name
        local profiles="proxy wireguard amneziawg dnstt trusttunnel admin conduit snowflake monitoring"
        local profile_match=""
        for p in $profiles; do
            if [[ "${args[0]}" == "$p" ]]; then
                profile_match="$p"
                break
            fi
        done

        if [[ -n "$profile_match" ]]; then
            # Handle profile stop
            if [[ "$remove_containers" == "true" ]]; then
                info "Stopping and removing $profile_match profile..."
                docker compose --profile "$profile_match" down
            else
                info "Stopping $profile_match profile..."
                docker compose --profile "$profile_match" stop
            fi
            success "Profile $profile_match stopped!"
        else
            local services
            services=$(resolve_services "${args[@]}")
            if [[ -z "$services" ]]; then
                error "No valid services to stop"
                return 1
            fi
            if [[ "$remove_containers" == "true" ]]; then
                info "Stopping and removing: $services"
                docker compose rm -sf $services
            else
                info "Stopping: $services"
                docker compose stop $services
            fi
            success "Services stopped!"
        fi
    fi
}

cmd_restart() {
    if [[ $# -eq 0 ]] || [[ "$1" == "all" ]]; then
        info "Restarting all services..."
        docker compose --profile all restart
        success "All services restarted!"
    elif [[ $# -eq 1 ]]; then
        # Single argument - check if it's a profile name
        local profiles="proxy wireguard dnstt trusttunnel admin conduit snowflake monitoring"
        local profile_match=""
        for p in $profiles; do
            if [[ "$1" == "$p" ]]; then
                profile_match="$p"
                break
            fi
        done

        if [[ -n "$profile_match" ]]; then
            # Handle profile restart - restart all services in that profile
            info "Restarting $profile_match profile services..."
            docker compose --profile "$profile_match" restart
            success "Profile $profile_match restarted!"
        else
            local services
            services=$(resolve_services "$@")
            if [[ -z "$services" ]]; then
                error "No valid services to restart"
                return 1
            fi
            info "Restarting: $services"
            docker compose restart $services
            success "Services restarted!"
        fi
    else
        # Multiple arguments - resolve all as service names
        local services
        services=$(resolve_services "$@")
        if [[ -z "$services" ]]; then
            error "No valid services to restart"
            return 1
        fi
        info "Restarting: $services"
        docker compose restart $services
        success "Services restarted!"
    fi
}

cmd_status() {
    # Simple header without clearing terminal
    local singbox_ver wstunnel_ver conduit_ver branch
    singbox_ver=$(get_component_version "SINGBOX_VERSION" "1.12.17")
    wstunnel_ver=$(get_component_version "WSTUNNEL_VERSION" "10.5.1")
    conduit_ver=$(get_component_version "CONDUIT_VERSION" "1.2.0")
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    local version_str="v${VERSION}"
    if [[ -n "$branch" && "$branch" != "main" ]]; then
        version_str="v${VERSION} (${branch})"
    fi

    echo ""
    echo -e "${CYAN}MoaV${NC} ${version_str}  ${DIM}│${NC}  ${DIM}sing-box ${singbox_ver}  wstunnel ${wstunnel_ver}  conduit ${conduit_ver}${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    show_status

    # Show admin and grafana URLs if running
    local running=$(get_running_services)
    local show_urls=0
    if echo "$running" | grep -q "admin"; then
        [[ $show_urls -eq 0 ]] && echo ""
        echo -e "  ${CYAN}Admin Dashboard:${NC} $(get_admin_url)"
        show_urls=1
    fi
    if echo "$running" | grep -q "grafana"; then
        [[ $show_urls -eq 0 ]] && echo ""
        echo -e "  ${CYAN}Grafana:${NC}         $(get_grafana_url)"
        local grafana_cdn=$(get_grafana_cdn_url)
        if [[ -n "$grafana_cdn" ]]; then
            echo -e "  ${CYAN}Grafana (CDN):${NC}   $grafana_cdn"
        fi
        show_urls=1
    fi


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
    local cmd="docker compose --ansi always"
    if [[ -z "$services_to_log" ]]; then
        cmd="$cmd --profile all"
    fi
    cmd="$cmd logs -t --tail $tail_lines"

    if [[ "$follow" == "true" ]]; then
        echo -e "${CYAN}Following logs (Ctrl+C to exit)...${NC}"
        echo ""
        $cmd -f $services_to_log | format_log_timestamps
    else
        $cmd $services_to_log | format_log_timestamps
    fi
}

cmd_users() {
    list_users
}

cmd_user() {
    local action="${1:-}"
    shift 1 2>/dev/null || shift $# # Shift past action to get remaining args
    local username="${1:-}"

    case "$action" in
        list|ls)
            list_users
            ;;
        add)
            # Check for batch mode or multiple usernames
            if [[ "${1:-}" == "--batch" ]] || [[ "${1:-}" == "-b" ]]; then
                # Batch mode - pass all args to script
                if [[ -x "./scripts/user-add.sh" ]]; then
                    ./scripts/user-add.sh "$@"
                else
                    error "User add script not found"
                    exit 1
                fi
            elif [[ -z "${1:-}" ]]; then
                error "Usage: moav user add USERNAME [USERNAME2...] [--package]"
                error "       moav user add --batch N [--prefix NAME] [--package]"
                exit 1
            else
                # Single or multiple usernames - validate each, then pass all to script
                local usernames=()
                local flags=()
                for arg in "$@"; do
                    if [[ "$arg" == --* ]] || [[ "$arg" == -* ]]; then
                        flags+=("$arg")
                    else
                        if [[ ! "$arg" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                            error "Invalid username '$arg'. Use only letters, numbers, underscores, and hyphens"
                            exit 1
                        fi
                        usernames+=("$arg")
                    fi
                done
                if [[ ${#usernames[@]} -eq 0 ]]; then
                    error "No usernames provided"
                    exit 1
                fi
                if [[ -x "./scripts/user-add.sh" ]]; then
                    ./scripts/user-add.sh "${usernames[@]}" "${flags[@]}"
                else
                    error "User add script not found"
                    exit 1
                fi
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
    local no_cache=""
    local build_local=""
    local services_args=()

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --no-cache) no_cache="--no-cache" ;;
            --local) build_local="true" ;;
            *) services_args+=("$arg") ;;
        esac
    done

    # Check if .env exists
    if [[ ! -f ".env" ]]; then
        echo ""
        warn "No .env file found. Build may fail or show warnings about missing variables."
        echo ""
        echo "  You have two options:"
        echo -e "    1. Run ${CYAN}moav bootstrap${NC} first to set up configuration"
        echo "    2. Copy .env.example to .env and configure manually"
        echo ""
        if ! confirm "Continue building anyway?" "n"; then
            echo ""
            info "Run 'moav bootstrap' or 'cp .env.example .env' first"
            return 0
        fi
        echo ""
    fi

    # Handle --local: build images locally from Dockerfiles
    if [[ "$build_local" == "true" ]]; then
        build_local_images "$no_cache" "${services_args[@]}"
        return $?
    fi

    if [[ ${#services_args[@]} -eq 0 ]] || [[ "${services_args[0]}" == "all" ]]; then
        info "Building all services${no_cache:+ (no cache)}..."
        # Go services compile from source and download modules from proxy.golang.org.
        # Building them in parallel with 10+ other images saturates the network,
        # causing TLS handshake timeouts. Build Go services sequentially first
        # to populate the BuildKit cache mounts, then build everything in parallel
        # (Go module downloads will be instant from cache).
        local go_services=("amneziawg" "dnstt" "snowflake")

        # Phase 1: Build Go services sequentially to populate module cache
        info "Phase 1/2: Building Go services (populating module cache)..."
        for svc in "${go_services[@]}"; do
            if docker compose --profile all config --services 2>/dev/null | grep -q "^${svc}$"; then
                info "  Building ${svc}..."
                docker compose --profile all build $no_cache "$svc"
            fi
        done

        # Phase 2: Build all services in parallel
        # Go services will rebuild but module downloads are instant (BuildKit cache mounts)
        info "Phase 2/2: Building all services..."
        docker compose --profile all build $no_cache
        success "All services built!"
    else
        # Check if argument is a profile name
        local profiles="proxy wireguard amneziawg dnstt trusttunnel admin conduit snowflake monitoring"
        local profile_match=""
        for p in $profiles; do
            if [[ "${services_args[0]}" == "$p" ]]; then
                profile_match="$p"
                break
            fi
        done

        if [[ -n "$profile_match" ]]; then
            # Build all services in the profile
            info "Building $profile_match profile${no_cache:+ (no cache)}..."
            docker compose --profile "$profile_match" build $no_cache
            success "Profile $profile_match built!"
        else
            local services
            services=$(resolve_services "${services_args[@]}")
            # Remove empty values and trim whitespace
            services=$(echo "$services" | xargs)
            if [[ -z "$services" ]]; then
                info "No buildable services specified"
                return 0
            fi
            # Check if any services are image-only (need --local build)
            local compose_services=()
            local local_services=()
            for svc in $services; do
                if [[ -n "${LOCAL_BUILD_MAP[$svc]:-}" ]]; then
                    local_services+=("$svc")
                else
                    compose_services+=("$svc")
                fi
            done
            # Build compose services normally
            if [[ ${#compose_services[@]} -gt 0 ]]; then
                info "Building: ${compose_services[*]}${no_cache:+ (no cache)}"
                docker compose --profile all build $no_cache ${compose_services[@]}
                success "Build complete!"
            fi
            # Auto-redirect image-only services to local build
            if [[ ${#local_services[@]} -gt 0 ]]; then
                info "Building locally: ${local_services[*]} (image-only services)"
                build_local_images "$no_cache" "${local_services[@]}"
            fi
        fi
    fi
}

# Map of services that can be built locally
# Format: "dockerfile|image_tag|image_env_var|version_env_var|version_arg|description"
declare -A LOCAL_BUILD_MAP=(
    ["cadvisor"]="dockerfiles/Dockerfile.cadvisor|moav-cadvisor:local|IMAGE_CADVISOR|CADVISOR_VERSION|CADVISOR_VERSION|cAdvisor container metrics (gcr.io)"
    ["clash-exporter"]="dockerfiles/Dockerfile.clash-exporter|moav-clash-exporter:local|IMAGE_CLASH_EXPORTER|CLASH_EXPORTER_VERSION|CLASH_EXPORTER_VERSION|Clash API exporter (ghcr.io)"
    ["prometheus"]="dockerfiles/Dockerfile.prometheus|moav-prometheus:local|IMAGE_PROMETHEUS|PROMETHEUS_VERSION|PROMETHEUS_VERSION|Prometheus time-series DB"
    ["grafana"]="dockerfiles/Dockerfile.grafana|moav-grafana:local|IMAGE_GRAFANA|GRAFANA_VERSION|GRAFANA_VERSION|Grafana dashboards"
    ["node-exporter"]="dockerfiles/Dockerfile.node-exporter|moav-node-exporter:local|IMAGE_NODE_EXPORTER|NODE_EXPORTER_VERSION|NODE_EXPORTER_VERSION|Node system metrics"
    ["nginx"]="dockerfiles/Dockerfile.nginx|moav-nginx:local|IMAGE_NGINX||NGINX_VERSION|Nginx web server"
    ["certbot"]="dockerfiles/Dockerfile.certbot|moav-certbot:local|IMAGE_CERTBOT||CERTBOT_VERSION|Let's Encrypt client"
)

# Default services to build with --local (commonly blocked registries)
DEFAULT_LOCAL_BUILDS="cadvisor clash-exporter"

# Build images locally for regions with blocked registries
build_local_images() {
    local no_cache="${1:-}"
    shift
    local services_to_build=("$@")
    local env_file=".env"
    local built_count=0

    print_section "Building Local Images"
    echo ""
    echo "This builds images from source for regions where container registries are blocked."
    echo ""

    # If no services specified, use defaults (commonly blocked)
    if [[ ${#services_to_build[@]} -eq 0 ]]; then
        read -ra services_to_build <<< "$DEFAULT_LOCAL_BUILDS"
        echo "Building default images (gcr.io/ghcr.io - commonly blocked):"
        for svc in "${services_to_build[@]}"; do
            echo "  - $svc"
        done
    elif [[ "${services_to_build[0]}" == "all" ]]; then
        # First, build all services that use docker-compose build
        echo "Step 1: Building all docker-compose services..."
        echo ""
        if docker compose --profile all build $no_cache; then
            success "Docker-compose services built!"
        else
            error "Failed to build some docker-compose services"
        fi
        echo ""

        # Then build external images
        echo "Step 2: Building external images locally..."
        services_to_build=("${!LOCAL_BUILD_MAP[@]}")
        echo "Images to build:"
        for svc in "${services_to_build[@]}"; do
            echo "  - $svc"
        done
    else
        echo "Building specified images:"
        for svc in "${services_to_build[@]}"; do
            echo "  - $svc"
        done
    fi
    echo ""

    # Build each service
    for service in "${services_to_build[@]}"; do
        local build_info="${LOCAL_BUILD_MAP[$service]}"

        if [[ -z "$build_info" ]]; then
            warn "Unknown service for local build: $service"
            echo "Available services: ${!LOCAL_BUILD_MAP[*]}"
            continue
        fi

        # Parse build info (dockerfile|image_tag|image_env_var|version_env_var|version_arg|description)
        IFS='|' read -r dockerfile image_tag image_env_var version_env_var version_arg description <<< "$build_info"

        # Check Dockerfile exists
        if [[ ! -f "$dockerfile" ]]; then
            error "Dockerfile not found: $dockerfile"
            continue
        fi

        # Get version from .env if available
        local version_value=""
        local build_args=""
        if [[ -n "$version_env_var" ]] && [[ -f "$env_file" ]]; then
            version_value=$(grep "^${version_env_var}=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
            if [[ -n "$version_value" ]] && [[ -n "$version_arg" ]]; then
                build_args="--build-arg ${version_arg}=${version_value}"
            fi
        fi

        info "Building $service ($description)${version_value:+ v$version_value}..."
        if docker build $no_cache $build_args -f "$dockerfile" -t "$image_tag" .; then
            success "$service built: $image_tag"
            built_count=$((built_count + 1))

            # Update .env to use local image
            if [[ -f "$env_file" ]] && [[ -n "$image_env_var" ]]; then
                update_env_var "$env_file" "$image_env_var" "$image_tag"
            fi
        else
            error "Failed to build $service"
        fi
        echo ""
    done

    if [[ $built_count -eq 0 ]]; then
        error "No images were built successfully"
        return 1
    fi

    success "$built_count local image(s) built successfully!"
    echo ""
    echo "Your .env has been updated to use the local images."
    echo "Run 'moav start' to use them."
    echo ""
    echo "To see all available images for local build:"
    echo "  moav build --local --list"
}

# Helper: update or add environment variable in .env
update_env_var() {
    local env_file="$1"
    local var_name="$2"
    local var_value="$3"

    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        sed -i.bak "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
    elif grep -q "^# ${var_name}=" "$env_file" 2>/dev/null; then
        sed -i.bak "s|^# ${var_name}=.*|${var_name}=${var_value}|" "$env_file"
    else
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
    rm -f "$env_file.bak"
}

# =============================================================================
# Client Commands
# =============================================================================

cmd_test() {
    local user=""
    local json_flag=""
    local verbose_flag=""

    # Parse flags
    for arg in "$@"; do
        case "$arg" in
            --json) json_flag="--json" ;;
            -v|--verbose) verbose_flag="--verbose" ;;
            -*) error "Unknown flag: $arg"; exit 1 ;;
            *) [[ -z "$user" ]] && user="$arg" ;;
        esac
    done

    if [[ -z "$user" ]]; then
        error "Usage: moav test USERNAME [--json] [-v|--verbose]"
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
        moav-client --test $json_flag $verbose_flag
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

    else
        warn "  State volume not found (moav_moav_state)"
    fi

    # Count actual users from bundles directory
    local user_count=0
    if [[ -d "outputs/bundles" ]]; then
        for user_dir in outputs/bundles/*/; do
            if [[ -d "$user_dir" ]]; then
                local username=$(basename "$user_dir")
                # Skip zip file extractions and temp directories
                [[ "$username" == *-configs ]] && continue
                [[ "$username" == *-moav-configs ]] && continue
                ((user_count++)) || true
            fi
        done
    fi
    if [[ "$user_count" -gt 0 ]]; then
        success "    $user_count user(s) found"
    fi

    # 2b. Export conduit data (Psiphon key)
    if docker volume inspect moav_moav_conduit &>/dev/null; then
        info "  Exporting conduit data..."
        mkdir -p "$export_dir/conduit"
        docker run --rm \
            -v moav_moav_conduit:/data:ro \
            -v "$export_dir/conduit:/backup" \
            alpine sh -c "cp -a /data/. /backup/ 2>/dev/null || true"
        success "    Conduit data exported"
    fi

    # 2c. Export TLS certificates
    if docker volume inspect moav_moav_certs &>/dev/null; then
        info "  Exporting TLS certificates..."
        mkdir -p "$export_dir/certs"
        docker run --rm \
            -v moav_moav_certs:/certs:ro \
            -v "$export_dir/certs:/backup" \
            alpine sh -c "cp -a /certs/. /backup/ 2>/dev/null || true"
        success "    TLS certificates exported"
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

    # Resolve relative paths from original working directory
    if [[ "$input_file" != /* ]]; then
        if [[ -f "$ORIGINAL_PWD/$input_file" ]]; then
            input_file="$ORIGINAL_PWD/$input_file"
        fi
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

    # 2b. Import conduit data (Psiphon key)
    if [[ -d "$export_dir/conduit" ]]; then
        info "  Importing conduit data..."
        docker volume create moav_moav_conduit &>/dev/null || true
        docker run --rm \
            -v moav_moav_conduit:/data \
            -v "$export_dir/conduit:/backup:ro" \
            alpine sh -c "rm -rf /data/* && cp -a /backup/. /data/"
        success "    Conduit data imported"
    fi

    # 2c. Import TLS certificates
    if [[ -d "$export_dir/certs" ]]; then
        info "  Importing TLS certificates..."
        docker volume create moav_moav_certs &>/dev/null || true
        docker run --rm \
            -v moav_moav_certs:/certs \
            -v "$export_dir/certs:/backup:ro" \
            alpine sh -c "rm -rf /certs/* && cp -a /backup/. /certs/"
        success "    TLS certificates imported"
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
    echo "  2. Regenerate user configs: moav regenerate-users"
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

    # If old_ip is empty (auto-detect mode), try to detect current IP for config updates
    if [[ -z "$old_ip" ]]; then
        info "SERVER_IP not set in .env (auto-detect mode)"
        old_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
        if [[ -z "$old_ip" ]]; then
            warn "Could not detect current IP. Will set new IP but cannot update existing configs."
            echo "  Run user regeneration manually after migration if needed."
            echo ""
        else
            info "Detected current IP: $old_ip"
        fi
    fi

    if [[ "$old_ip" == "$new_ip" ]]; then
        info "IP address is already set to $new_ip"
        exit 0
    fi

    if [[ -n "$old_ip" ]]; then
        info "Migrating from $old_ip to $new_ip"
    else
        info "Setting IP to $new_ip"
    fi
    echo ""

    # Detect IPv6 if available
    local new_ipv6=""
    local old_ipv6=$(grep -E '^SERVER_IPV6=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ "$old_ipv6" != "disabled" ]]; then
        new_ipv6=$(curl -6 -s --max-time 3 https://api6.ipify.org 2>/dev/null || echo "")
        if [[ -n "$new_ipv6" ]]; then
            info "Detected IPv6: $new_ipv6"
        fi
    fi

    # 1. Update .env
    info "  Updating .env..."
    sed -i.bak "s/^SERVER_IP=.*/SERVER_IP=\"$new_ip\"/" .env
    rm -f .env.bak
    success "    SERVER_IP updated"

    # Update IPv6 if detected
    if [[ -n "$new_ipv6" ]]; then
        if grep -q "^SERVER_IPV6=" .env; then
            sed -i.bak "s/^SERVER_IPV6=.*/SERVER_IPV6=\"$new_ipv6\"/" .env
        else
            echo "SERVER_IPV6=\"$new_ipv6\"" >> .env
        fi
        rm -f .env.bak
        success "    SERVER_IPV6 updated"
    fi

    # 2. Update WireGuard server config (if exists)
    if [[ -f "configs/wireguard/wg0.conf" ]]; then
        info "  Updating WireGuard config..."
        # WireGuard server config doesn't contain server IP, but let's check
        success "    WireGuard config OK (no changes needed)"
    fi

    # 3. Regenerate user bundles (only if we have old_ip to replace)
    info "  Regenerating user bundles..."
    local users_dir="outputs/bundles"
    if [[ -z "$old_ip" ]]; then
        warn "    Cannot update configs without old IP. Skipping bundle regeneration."
        echo "    Run 'moav user package <username>' to regenerate individual user bundles."
    elif [[ -d "$users_dir" ]]; then
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

                # Update WireGuard IPv6 config if exists
                if [[ -f "$user_dir/wireguard-ipv6.conf" ]] && [[ -n "$new_ipv6" ]]; then
                    # Update IPv6 endpoint (format: [ipv6]:port)
                    if [[ -n "$old_ipv6" ]]; then
                        sed -i.bak "s/Endpoint = \[$old_ipv6\]:/Endpoint = [$new_ipv6]:/g" "$user_dir/wireguard-ipv6.conf"
                    else
                        sed -i.bak "s/Endpoint = \[[^]]*\]:/Endpoint = [$new_ipv6]:/g" "$user_dir/wireguard-ipv6.conf"
                    fi
                    rm -f "$user_dir/wireguard-ipv6.conf.bak"
                fi

                # Update IPv6 link files if they exist
                for ipv6_file in "$user_dir"/*-ipv6.txt; do
                    if [[ -f "$ipv6_file" ]] && [[ -n "$new_ipv6" ]]; then
                        if [[ -n "$old_ipv6" ]]; then
                            sed -i.bak "s/@\[$old_ipv6\]:/@[$new_ipv6]:/g" "$ipv6_file"
                        fi
                        rm -f "$ipv6_file.bak"
                    fi
                done

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
    # Only regenerate if we updated the configs above
    if [[ -z "$old_ip" ]]; then
        : # Skip QR regeneration since configs weren't updated
    elif command -v qrencode &>/dev/null; then
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
    if [[ -n "$old_ip" ]]; then
        echo "  Old IP: $old_ip"
    else
        echo "  Old IP: (was auto-detect)"
    fi
    echo "  New IP: $new_ip"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Restart services: moav restart"
    echo "  2. Re-package user bundles: moav user package <username>"
    echo "  3. Distribute new configs to users"
    echo ""
    echo -e "${YELLOW}Note:${NC} Users will need updated configs to connect via the new IP."
    echo "      Or they can manually update the IP in their client app."
}

cmd_regenerate_users() {
    print_section "Regenerate User Bundles"

    info "This will regenerate all user config bundles using current .env settings."
    echo "  - Credentials (UUIDs, passwords, keys) remain unchanged"
    echo "  - IP and domain will be updated from .env"
    echo ""

    # Check if bootstrap has been run
    if ! check_bootstrap; then
        error "Bootstrap has not been run. Run 'moav bootstrap' first."
        exit 1
    fi

    # Load current settings
    local server_ip=$(grep -E '^SERVER_IP=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local server_ipv6=$(grep -E '^SERVER_IPV6=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local domain=$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')

    # Auto-detect IP if not set
    if [[ -z "$server_ip" ]]; then
        server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
        if [[ -n "$server_ip" ]]; then
            info "SERVER_IP not set, using detected IP: $server_ip"
        else
            error "Could not determine server IP. Set SERVER_IP in .env"
            exit 1
        fi
    fi

    # Auto-detect IPv6 if not set or disabled
    if [[ -z "$server_ipv6" ]] && [[ "$server_ipv6" != "disabled" ]]; then
        server_ipv6=$(curl -6 -s --max-time 3 https://api6.ipify.org 2>/dev/null || echo "")
    fi
    [[ "$server_ipv6" == "disabled" ]] && server_ipv6=""

    echo -e "  Server IP:   ${CYAN}$server_ip${NC}"
    if [[ -n "$server_ipv6" ]]; then
        echo -e "  Server IPv6: ${CYAN}$server_ipv6${NC}"
    fi
    echo -e "  Domain:      ${CYAN}${domain:-not set}${NC}"

    # Show CDN domain if configured
    local cdn_subdomain_preview=$(grep -E '^CDN_SUBDOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -n "$cdn_subdomain_preview" && -n "$domain" ]]; then
        echo -e "  CDN Domain:  ${CYAN}${cdn_subdomain_preview}.${domain}${NC}"
    fi
    echo ""

    if ! confirm "Regenerate all user bundles?" "y"; then
        info "Cancelled."
        exit 0
    fi

    echo ""

    # Find existing users from bundles directory
    info "Finding existing users..."

    local user_count=0
    local users_found=""

    # List users from the outputs/bundles directory (the authoritative source)
    if [[ -d "outputs/bundles" ]]; then
        for user_dir in outputs/bundles/*/; do
            if [[ -d "$user_dir" ]]; then
                local username=$(basename "$user_dir")
                # Skip zip file extractions and temp directories
                [[ "$username" == *-configs ]] && continue
                [[ "$username" == *-moav-configs ]] && continue
                [[ "$username" == "." ]] && continue
                users_found="$users_found $username"
            fi
        done
        users_found=$(echo "$users_found" | xargs)  # Trim whitespace
    fi

    if [[ -z "$users_found" ]]; then
        warn "No users found in outputs/bundles/."
        echo "  Users are created during bootstrap or with 'moav user add'"
        exit 0
    fi

    echo "  Found users: $users_found"
    echo ""

    info "Regenerating bundles..."

    # Construct CDN_DOMAIN from CDN_SUBDOMAIN + DOMAIN if not explicitly set
    local cdn_domain=$(grep -E '^CDN_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local cdn_subdomain=$(grep -E '^CDN_SUBDOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -z "$cdn_domain" && -n "$cdn_subdomain" && -n "$domain" ]]; then
        cdn_domain="${cdn_subdomain}.${domain}"
    fi
    local cdn_ws_path=$(grep -E '^CDN_WS_PATH=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    cdn_ws_path="${cdn_ws_path:-/ws}"

    # Load ENABLE_* settings from .env
    local enable_reality=$(grep -E '^ENABLE_REALITY=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local enable_trojan=$(grep -E '^ENABLE_TROJAN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local enable_hysteria2=$(grep -E '^ENABLE_HYSTERIA2=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local enable_wireguard=$(grep -E '^ENABLE_WIREGUARD=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local enable_amneziawg=$(grep -E '^ENABLE_AMNEZIAWG=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local enable_dnstt=$(grep -E '^ENABLE_DNSTT=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
    local enable_trusttunnel=$(grep -E '^ENABLE_TRUSTTUNNEL=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')

    # Run the regeneration using bootstrap container
    # This mounts all necessary volumes and has the generate scripts
    for username in $users_found; do
        echo -n "  Regenerating $username... "

        if docker compose run --rm -T \
            -e "SERVER_IP=$server_ip" \
            -e "SERVER_IPV6=$server_ipv6" \
            -e "DOMAIN=$domain" \
            -e "CDN_SUBDOMAIN=$cdn_subdomain" \
            -e "CDN_DOMAIN=$cdn_domain" \
            -e "CDN_WS_PATH=$cdn_ws_path" \
            -e "ENABLE_REALITY=${enable_reality:-true}" \
            -e "ENABLE_TROJAN=${enable_trojan:-true}" \
            -e "ENABLE_HYSTERIA2=${enable_hysteria2:-true}" \
            -e "ENABLE_WIREGUARD=${enable_wireguard:-true}" \
            -e "ENABLE_AMNEZIAWG=${enable_amneziawg:-true}" \
            -e "ENABLE_DNSTT=${enable_dnstt:-true}" \
            -e "ENABLE_TRUSTTUNNEL=${enable_trusttunnel:-true}" \
            bootstrap /app/generate-user.sh "$username" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            ((user_count++)) || true
        else
            echo -e "${RED}✗${NC}"
            warn "    Failed to regenerate $username"
        fi
    done

    echo ""

    if [[ $user_count -gt 0 ]]; then
        success "Regenerated $user_count user bundle(s)"
        echo ""
        echo -e "${CYAN}Bundles location:${NC} outputs/bundles/"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Distribute new configs to users"
        echo "  2. Or create zip packages: moav user package <username>"
        echo ""
        echo -e "${YELLOW}Note:${NC} Users can also manually update the IP in their client app"
        echo "      since credentials haven't changed."
    else
        warn "No bundles were regenerated."
    fi
}

# =============================================================================
# Entry Point
# =============================================================================

main_interactive() {
    # Start async update check (won't block, results cached for next header display)
    check_for_updates

    # Check prerequisites only if not already verified
    # Also re-check if .env is missing (user may have deleted it)
    if ! prereqs_already_checked; then
        print_header
        # Clear stale prereqs flag if .env is missing
        if [[ -f "$PREREQS_FILE" ]] && [[ ! -f ".env" ]]; then
            rm -f "$PREREQS_FILE"
        fi
        echo -e "${DIM}First run - checking prerequisites...${NC}"
        echo ""
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
            shift
            do_uninstall "$@"
            ;;
        update)
            shift
            cmd_update "$@"
            ;;
        check)
            cmd_check
            ;;
        bootstrap)
            cmd_bootstrap
            ;;
        domainless|domain-less|no-domain)
            cmd_domainless
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
        regenerate-users|regenerate_users|regen-users)
            cmd_regenerate_users
            ;;
        setup-dns|setup_dns|dns-setup)
            cmd_setup_dns
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
