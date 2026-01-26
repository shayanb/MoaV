#!/bin/bash
set -euo pipefail

# =============================================================================
# Fetch Psiphon Conduit keypair and generate Ryve deep link
# =============================================================================

cd "$(dirname "$0")/.."

CONDUIT_NAME="${1:-MoaV Conduit}"

echo "=========================================="
echo "       Psiphon Conduit Info"
echo "=========================================="
echo ""

# Check if container is running
if ! docker compose ps psiphon-conduit --status running &>/dev/null; then
    echo "ERROR: Conduit container is not running"
    echo "Start with: docker compose --profile conduit up -d psiphon-conduit"
    exit 1
fi

echo "=== Container Status ==="
docker compose ps psiphon-conduit
echo ""

# Check for conduit_key.json
if ! docker compose exec -T psiphon-conduit test -f /data/conduit_key.json 2>/dev/null; then
    echo "ERROR: Key file not found at /data/conduit_key.json"
    echo "Conduit may not have initialized yet. Check logs:"
    echo "  docker compose logs psiphon-conduit"
    exit 1
fi

echo "=== Key File ==="
echo "/data/conduit_key.json"
echo ""

# Extract the private key (86 chars, base64 without padding)
KEY=$(docker compose exec -T psiphon-conduit cat /data/conduit_key.json 2>/dev/null | tr -d '\r')

# Parse JSON without jq - extract privateKeyBase64
PRIVATE_KEY=$(echo "$KEY" | grep -o '"privateKeyBase64"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)".*/\1/')

if [[ -z "$PRIVATE_KEY" ]]; then
    echo "ERROR: Could not extract privateKeyBase64 from key file"
    echo "Raw content:"
    echo "$KEY"
    exit 1
fi

echo "=== Private Key ==="
echo "$PRIVATE_KEY"
echo ""

# Build JSON payload (compact, no spaces)
PAYLOAD="{\"version\":1,\"data\":{\"key\":\"${PRIVATE_KEY}\",\"name\":\"${CONDUIT_NAME}\"}}"

# Base64url encode with padding
ENCODED=$(echo -n "$PAYLOAD" | base64 | tr -d '\n' | tr '+/' '-_')

# Build deep link
DEEP_LINK="network.ryve.app://(app)/conduits?claim=${ENCODED}"

echo "=== Ryve Deep Link ==="
echo ""
echo "$DEEP_LINK"
echo ""
echo "=========================================="
echo "Copy this link and open on your phone to import in Ryve"
echo "=========================================="
