#!/bin/bash
# =============================================================================
# MoaV Quick Installer
# Usage: curl -fsSL moav.sh/install.sh | bash
#
# This script will:
# 1. Install missing prerequisites (Docker, git, qrencode) with user confirmation
# 2. Clone MoaV to /opt/moav (or update if exists)
# 3. Guide you through the setup process
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/shayanb/MoaV.git"
INSTALL_DIR="${MOAV_INSTALL_DIR:-/opt/moav}"

# Helper functions
info() { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    # Check if we have a TTY for interactive input
    if [[ ! -t 0 ]] && [[ ! -e /dev/tty ]]; then
        # Non-interactive: use default
        [[ "$default" == "y" ]]
        return
    fi

    # Read from /dev/tty to work with curl | bash
    if [[ "$default" == "y" ]]; then
        printf "%s [Y/n] " "$prompt"
    else
        printf "%s [y/N] " "$prompt"
    fi

    if read -n 1 -r REPLY < /dev/tty 2>/dev/null; then
        echo ""
    else
        # Fallback if /dev/tty fails - use default
        echo ""
        [[ "$default" == "y" ]]
        return
    fi

    if [[ "$default" == "y" ]]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Detect OS
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

# Banner
echo -e "${CYAN}"
cat << 'EOF'
███╗   ███╗ ██████╗  █████╗ ██╗   ██╗
████╗ ████║██╔═══██╗██╔══██╗██║   ██║
██╔████╔██║██║   ██║███████║██║   ██║
██║╚██╔╝██║██║   ██║██╔══██║╚██╗ ██╔╝
██║ ╚═╝ ██║╚██████╔╝██║  ██║ ╚████╔╝
╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝  ╚═══╝

       Mother of all VPNs
EOF
echo -e "${NC}"

info "MoaV Installer"
echo ""

OS_TYPE=$(detect_os)
info "Detected OS: $OS_TYPE"
echo ""

# =============================================================================
# Check and Install Prerequisites
# =============================================================================

info "Checking prerequisites..."
echo ""

needs_install=()

# Check git
if command -v git &>/dev/null; then
    success "git is installed"
else
    warn "git is not installed"
    needs_install+=("git")
fi

# Check Docker
if command -v docker &>/dev/null; then
    success "Docker is installed"
else
    warn "Docker is not installed"
    needs_install+=("docker")
fi

# Check Docker Compose
if docker compose version &>/dev/null 2>&1; then
    success "Docker Compose is installed"
elif command -v docker-compose &>/dev/null; then
    success "docker-compose (legacy) is installed"
else
    if [[ ! " ${needs_install[*]} " =~ " docker " ]]; then
        warn "Docker Compose is not installed"
        needs_install+=("docker-compose")
    fi
fi

# Check if Docker is running (only if installed)
if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
        success "Docker daemon is running"
    else
        warn "Docker daemon is not running"
    fi
fi

# Check qrencode (optional but recommended)
if command -v qrencode &>/dev/null; then
    success "qrencode is installed"
else
    warn "qrencode is not installed (needed for QR codes)"
    needs_install+=("qrencode")
fi

# Check jq (required for user management)
if command -v jq &>/dev/null; then
    success "jq is installed"
else
    warn "jq is not installed (needed for user management)"
    needs_install+=("jq")
fi

echo ""

# =============================================================================
# Install Missing Prerequisites
# =============================================================================

if [[ ${#needs_install[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Missing packages: ${needs_install[*]}${NC}"
    echo ""

    if confirm "Install missing packages?"; then
        echo ""

        for pkg in "${needs_install[@]}"; do
            case "$pkg" in
                git)
                    info "Installing git..."
                    case "$OS_TYPE" in
                        debian)
                            sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y git
                            ;;
                        rhel)
                            sudo dnf install -y git || sudo yum install -y git
                            ;;
                        macos)
                            if command -v brew &>/dev/null; then
                                brew install git
                            else
                                error "Please install Xcode Command Line Tools: xcode-select --install"
                                exit 1
                            fi
                            ;;
                        alpine)
                            sudo apk add git
                            ;;
                        *)
                            error "Cannot auto-install git on this OS. Please install manually."
                            exit 1
                            ;;
                    esac
                    success "git installed"
                    ;;

                docker|docker-compose)
                    info "Installing Docker..."
                    case "$OS_TYPE" in
                        debian|rhel)
                            # Official Docker install script handles both Docker and Compose
                            # DEBIAN_FRONTEND prevents interactive prompts during install
                            curl -fsSL https://get.docker.com | sudo DEBIAN_FRONTEND=noninteractive sh

                            # Add current user to docker group
                            sudo usermod -aG docker "$(whoami)" 2>/dev/null || true

                            # Start Docker
                            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
                            sudo systemctl enable docker 2>/dev/null || true

                            success "Docker installed"
                            echo ""
                            warn "You may need to log out and back in for docker group permissions."
                            warn "Or run: newgrp docker"
                            ;;
                        macos)
                            error "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
                            echo "After installing, run this script again."
                            exit 1
                            ;;
                        alpine)
                            sudo apk add docker docker-compose
                            sudo rc-update add docker boot
                            sudo service docker start
                            success "Docker installed"
                            ;;
                        *)
                            error "Cannot auto-install Docker on this OS."
                            echo "Please install from: https://docs.docker.com/engine/install/"
                            exit 1
                            ;;
                    esac
                    # Skip docker-compose if we already installed docker (it includes compose)
                    if [[ "$pkg" == "docker" ]]; then
                        needs_install=("${needs_install[@]/docker-compose}")
                    fi
                    ;;

                qrencode)
                    info "Installing qrencode..."
                    case "$OS_TYPE" in
                        debian)
                            sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y qrencode
                            ;;
                        rhel)
                            sudo dnf install -y qrencode || sudo yum install -y qrencode
                            ;;
                        macos)
                            if command -v brew &>/dev/null; then
                                brew install qrencode
                            else
                                warn "Homebrew not installed. Skipping qrencode."
                                warn "Install with: brew install qrencode"
                                continue
                            fi
                            ;;
                        alpine)
                            sudo apk add libqrencode-tools
                            ;;
                        *)
                            warn "Cannot auto-install qrencode on this OS. Skipping."
                            continue
                            ;;
                    esac
                    success "qrencode installed"
                    ;;

                jq)
                    info "Installing jq..."
                    case "$OS_TYPE" in
                        debian)
                            sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y jq
                            ;;
                        rhel)
                            sudo dnf install -y jq || sudo yum install -y jq
                            ;;
                        macos)
                            if command -v brew &>/dev/null; then
                                brew install jq
                            else
                                warn "Homebrew not installed. Skipping jq."
                                warn "Install with: brew install jq"
                                continue
                            fi
                            ;;
                        alpine)
                            sudo apk add jq
                            ;;
                        *)
                            warn "Cannot auto-install jq on this OS. Skipping."
                            continue
                            ;;
                    esac
                    success "jq installed"
                    ;;
            esac
            echo ""
        done
    else
        if [[ " ${needs_install[*]} " =~ " docker " ]] || [[ " ${needs_install[*]} " =~ " git " ]]; then
            error "Docker and git are required. Please install them and try again."
            echo ""
            echo "Install Docker: https://docs.docker.com/engine/install/"
            exit 1
        fi
    fi
fi

# Verify Docker is working
if ! docker info &>/dev/null 2>&1; then
    echo ""
    warn "Docker daemon is not running."

    if [[ "$OS_TYPE" != "macos" ]]; then
        if confirm "Start Docker now?"; then
            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
            sleep 2

            if docker info &>/dev/null 2>&1; then
                success "Docker started"
            else
                error "Failed to start Docker. You may need to:"
                echo "  1. Log out and back in (for group permissions)"
                echo "  2. Run: sudo systemctl start docker"
                echo "  3. Run this script again"
                exit 1
            fi
        fi
    else
        error "Please start Docker Desktop and run this script again."
        exit 1
    fi
fi

echo ""

# =============================================================================
# Clone or Update MoaV
# =============================================================================

if [ -d "$INSTALL_DIR" ]; then
    warn "MoaV directory exists at $INSTALL_DIR"

    if confirm "Update existing installation?"; then
        info "Updating MoaV..."
        cd "$INSTALL_DIR"
        git pull origin main || git pull
        success "MoaV updated"
    else
        info "Using existing installation."
    fi
else
    info "Installing MoaV to $INSTALL_DIR..."

    # Check if we need sudo
    parent_dir=$(dirname "$INSTALL_DIR")
    if [ -w "$parent_dir" ] 2>/dev/null; then
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        info "Need sudo to create $INSTALL_DIR"
        sudo mkdir -p "$INSTALL_DIR"
        sudo chown "$(whoami)" "$INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi

    success "MoaV cloned"
fi

cd "$INSTALL_DIR"

# Make scripts executable
chmod +x moav.sh
chmod +x scripts/*.sh 2>/dev/null || true

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  MoaV installed successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
# Next Steps
# =============================================================================

echo -e "${CYAN}What would you like to do next?${NC}"
echo ""
echo "  1) Run interactive setup (recommended for first-time)"
echo "  2) Just show me the next steps"
echo "  0) Exit"
echo ""

printf "Choice [1]: "
if ! read -n 1 -r choice < /dev/tty 2>/dev/null; then
    choice="1"  # Default to running setup
fi
echo ""

case "${choice:-1}" in
    1)
        echo ""
        info "Starting MoaV setup..."
        echo ""

        # Check if .env exists and configure it
        if [[ ! -f ".env" ]]; then
            if [[ -f ".env.example" ]]; then
                cp .env.example .env
                success "Created .env from .env.example"
            fi
        fi

        # Configure required settings interactively
        if [[ -f ".env" ]]; then
            echo ""
            echo -e "${CYAN}Configure your MoaV installation:${NC}"
            echo ""

            # Get current values
            current_domain=$(grep -E "^DOMAIN=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
            current_email=$(grep -E "^ACME_EMAIL=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")

            # Ask for domain
            echo -e "${WHITE}Domain name${NC} (for Trojan, Hysteria2, dnstt, admin dashboard)"
            echo "  Example: vpn.example.com"
            echo "  Note: Reality protocol works without a domain (impersonates microsoft.com)"
            if [[ -n "$current_domain" && "$current_domain" != "your-domain.com" ]]; then
                printf "  Domain [%s]: " "$current_domain"
            else
                printf "  Domain: "
            fi
            read -r input_domain < /dev/tty 2>/dev/null || input_domain=""
            if [[ -n "$input_domain" ]]; then
                sed -i "s|^DOMAIN=.*|DOMAIN=\"$input_domain\"|" .env
                success "Domain set to: $input_domain"
            elif [[ -n "$current_domain" && "$current_domain" != "your-domain.com" ]]; then
                success "Using existing domain: $current_domain"
            else
                warn "No domain set - you'll need to edit .env manually"
            fi
            echo ""

            # Ask for email
            echo -e "${WHITE}Email address${NC} (for Let's Encrypt TLS certificate)"
            if [[ -n "$current_email" && "$current_email" != "your-email@example.com" ]]; then
                printf "  Email [%s]: " "$current_email"
            else
                printf "  Email: "
            fi
            read -r input_email < /dev/tty 2>/dev/null || input_email=""
            if [[ -n "$input_email" ]]; then
                sed -i "s|^ACME_EMAIL=.*|ACME_EMAIL=\"$input_email\"|" .env
                success "Email set to: $input_email"
            elif [[ -n "$current_email" && "$current_email" != "your-email@example.com" ]]; then
                success "Using existing email: $current_email"
            else
                warn "No email set - you'll need to edit .env manually"
            fi
            echo ""

            # Generate or ask for admin password
            current_password=$(grep -E "^ADMIN_PASSWORD=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
            echo -e "${WHITE}Admin dashboard password${NC}"
            echo "  Press Enter to generate a random password, or type your own"
            printf "  Password: "
            read -r input_password < /dev/tty 2>/dev/null || input_password=""

            if [[ -z "$input_password" ]]; then
                # Generate random password
                input_password=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
                echo ""
            fi
            sed -i "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=\"$input_password\"|" .env
            success "Admin password configured"
            echo ""

            # Show summary with password prominently displayed
            echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
            echo -e "${WHITE}  Configuration saved to .env${NC}"
            echo ""
            echo -e "  ${WHITE}Admin Password:${NC} ${CYAN}$input_password${NC}"
            echo ""
            echo -e "  ${YELLOW}⚠ IMPORTANT: Write down this password or find it in .env${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
            echo ""
            printf "Press Enter to continue..."
            read -r < /dev/tty 2>/dev/null || true
            echo ""
        fi

        # Ask about global installation
        echo ""
        echo -e "${CYAN}Install 'moav' command globally?${NC}"
        echo "  This lets you run 'moav' from anywhere instead of './moav.sh'"
        echo ""
        if confirm "Install globally?" "y"; then
            ./moav.sh install
        fi

        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE}  MoaV is ready!${NC}"
        echo ""
        echo -e "  Installed at: ${CYAN}$INSTALL_DIR${NC}"
        echo -e "  Run:          ${WHITE}moav${NC} (if installed globally)"
        echo -e "                ${WHITE}cd $INSTALL_DIR && ./moav.sh${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo ""

        exec ./moav.sh
        ;;
    2|*)
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo ""
        echo "  1. Configure your environment:"
        echo -e "     ${WHITE}cd $INSTALL_DIR${NC}"
        echo -e "     ${WHITE}cp .env.example .env${NC}"
        echo -e "     ${WHITE}nano .env${NC}  # Set DOMAIN, ACME_EMAIL, ADMIN_PASSWORD"
        echo ""
        echo "  2. Run the interactive setup:"
        echo -e "     ${WHITE}./moav.sh${NC}"
        echo ""
        echo "  3. (Optional) Install 'moav' command globally:"
        echo -e "     ${WHITE}./moav.sh install${NC}"
        echo ""
        echo -e "${CYAN}Documentation:${NC} https://github.com/shayanb/MoaV"
        echo -e "${CYAN}Website:${NC} https://moav.sh"
        echo ""
        ;;
esac
