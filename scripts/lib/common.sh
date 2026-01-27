#!/bin/bash
# Common utility functions

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Timestamp format: MM-DD HH:MM:SS
timestamp() {
    date '+%m-%d %H:%M:%S'
}

log_info() {
    echo -e "$(timestamp) - bootstrap - ${GREEN}INFO${NC} - $*"
}

log_warn() {
    echo -e "$(timestamp) - bootstrap - ${YELLOW}WARN${NC} - $*"
}

log_error() {
    echo -e "$(timestamp) - bootstrap - ${RED}ERROR${NC} - $*" >&2
}

# Generate a random password
generate_password() {
    local length="${1:-24}"
    pwgen -s "$length" 1
}

# Generate UUID
generate_uuid() {
    sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create directory if it doesn't exist
ensure_dir() {
    mkdir -p "$1"
}
