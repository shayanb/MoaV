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
                            sudo apt update && sudo apt install -y git
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
                            curl -fsSL https://get.docker.com | sh

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
                            sudo apt update && sudo apt install -y qrencode
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

        # Check if .env exists
        if [[ ! -f ".env" ]]; then
            if [[ -f ".env.example" ]]; then
                cp .env.example .env
                success "Created .env from .env.example"
                echo ""
                warn "Please edit .env with your settings before continuing."
                echo ""
                echo -e "${CYAN}Required settings:${NC}"
                echo "  DOMAIN=your-domain.com"
                echo "  ACME_EMAIL=your-email@example.com"
                echo "  ADMIN_PASSWORD=your-secure-password"
                echo ""

                if confirm "Open .env in editor now?" "y"; then
                    ${EDITOR:-nano} .env
                fi
            fi
        fi

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
