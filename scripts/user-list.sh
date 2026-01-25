#!/bin/bash
set -euo pipefail

# =============================================================================
# List all users
# Usage: ./scripts/user-list.sh
# =============================================================================

cd "$(dirname "$0")/.."

echo "=== MoaV Users ==="
echo ""

if [[ ! -f configs/sing-box/config.json ]]; then
    echo "No configuration found. Run bootstrap first."
    exit 1
fi

# Extract users from sing-box config
echo "Users in sing-box:"
jq -r '.inbounds[0].users[].name' configs/sing-box/config.json 2>/dev/null | sort | uniq | while read -r user; do
    bundle_status="[no bundle]"
    if [[ -d "outputs/bundles/$user" ]]; then
        bundle_status="[bundle: outputs/bundles/$user/]"
    fi
    echo "  - $user $bundle_status"
done

echo ""
echo "Total: $(jq -r '.inbounds[0].users | length' configs/sing-box/config.json 2>/dev/null || echo 0) users"
