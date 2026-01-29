#!/bin/bash
# =============================================================================
# MoaV Quick Installer
# Usage: curl -fsSL moav.sh/install.sh | bash
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/shayanb/MoaV.git"
INSTALL_DIR="${MOAV_INSTALL_DIR:-/opt/moav}"

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

echo -e "${BLUE}Installing MoaV...${NC}"
echo ""

# Check for required tools
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is required but not installed.${NC}"
        return 1
    fi
}

echo -e "${BLUE}Checking prerequisites...${NC}"

missing=0
for cmd in git docker; do
    if check_command "$cmd"; then
        echo -e "  ${GREEN}✓${NC} $cmd"
    else
        missing=1
    fi
done

# Check Docker Compose
if docker compose version &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} docker compose"
elif docker-compose version &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} docker-compose"
else
    echo -e "  ${RED}✗${NC} docker compose (not found)"
    missing=1
fi

if [ $missing -eq 1 ]; then
    echo ""
    echo -e "${RED}Please install missing prerequisites and try again.${NC}"
    echo ""
    echo "Install Docker: https://docs.docker.com/engine/install/"
    exit 1
fi

echo ""

# Clone or update repository
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}MoaV directory exists at $INSTALL_DIR${NC}"
    read -p "Update existing installation? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Updating MoaV...${NC}"
        cd "$INSTALL_DIR"
        git pull origin main
    else
        echo -e "${YELLOW}Skipping update.${NC}"
    fi
else
    echo -e "${BLUE}Cloning MoaV to $INSTALL_DIR...${NC}"

    # Check if we need sudo
    if [ -w "$(dirname "$INSTALL_DIR")" ]; then
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        echo -e "${YELLOW}Need sudo to create $INSTALL_DIR${NC}"
        sudo git clone "$REPO_URL" "$INSTALL_DIR"
        sudo chown -R "$(whoami)" "$INSTALL_DIR"
    fi
fi

cd "$INSTALL_DIR"

# Make moav.sh executable
chmod +x moav.sh

echo ""
echo -e "${GREEN}✓ MoaV installed successfully!${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo ""
echo "  1. Configure your environment:"
echo -e "     ${BLUE}cd $INSTALL_DIR${NC}"
echo -e "     ${BLUE}cp .env.example .env${NC}"
echo -e "     ${BLUE}nano .env${NC}  # Set DOMAIN, ACME_EMAIL, etc."
echo ""
echo "  2. Run the interactive setup:"
echo -e "     ${BLUE}./moav.sh${NC}"
echo ""
echo "  3. (Optional) Install globally:"
echo -e "     ${BLUE}./moav.sh install${NC}"
echo ""
echo -e "${CYAN}Documentation: https://github.com/shayanb/MoaV${NC}"
echo ""
