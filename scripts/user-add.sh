#!/bin/bash
set -euo pipefail

# =============================================================================
# Add a new user to all enabled services
# Usage: ./scripts/user-add.sh <username>
# =============================================================================

cd "$(dirname "$0")/.."

source scripts/lib/common.sh

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 john"
    exit 1
fi

# Validate username
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid username. Use only letters, numbers, underscores, and hyphens."
    exit 1
fi

# Check if user already exists
if [[ -d "outputs/bundles/$USERNAME" ]]; then
    log_error "User '$USERNAME' already exists. Use a different name or revoke first."
    exit 1
fi

log_info "Adding user: $USERNAME"

# Run the bootstrap container to generate user
docker compose run --rm \
    -e USER_ID="$USERNAME" \
    -v "$(pwd)/configs:/configs" \
    -v "$(pwd)/outputs:/outputs" \
    bootstrap /app/generate-single-user.sh "$USERNAME"

# Reload sing-box to pick up new config
docker compose exec sing-box sing-box reload 2>/dev/null || \
    docker compose restart sing-box

log_info "User '$USERNAME' created successfully!"
log_info "Bundle location: outputs/bundles/$USERNAME/"
