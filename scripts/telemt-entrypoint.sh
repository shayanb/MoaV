#!/bin/bash
set -euo pipefail

# =============================================================================
# MoaV telemt (Telegram MTProxy) entrypoint
# =============================================================================

CONFIG_FILE="/etc/telemt/config.toml"

echo "================================================"
echo "  MoaV Telegram MTProxy (telemt)"
echo "================================================"

# Wait for config file (bootstrap may still be generating it)
WAIT_TIMEOUT=30
WAITED=0
while [[ ! -f "$CONFIG_FILE" ]]; do
    if [[ $WAITED -ge $WAIT_TIMEOUT ]]; then
        echo "[telemt] ERROR: Config file not found after ${WAIT_TIMEOUT}s: $CONFIG_FILE"
        echo "[telemt] Run 'moav setup' or check bootstrap logs"
        exit 1
    fi
    echo "[telemt] Waiting for config file... (${WAITED}s)"
    sleep 2
    WAITED=$((WAITED + 2))
done

# Extract info from config for logging
PORT=$(grep -E '^\s*port\s*=' "$CONFIG_FILE" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
TLS_DOMAIN=$(grep -E '^\s*tls_domain\s*=' "$CONFIG_FILE" | head -1 | sed 's/.*=\s*"//' | sed 's/".*//')
USER_COUNT=$(grep -c '=' <(sed -n '/\[access\.users\]/,/^\[/p' "$CONFIG_FILE" 2>/dev/null) 2>/dev/null || echo "0")

echo "[telemt] Config: $CONFIG_FILE"
echo "[telemt] Listen: 0.0.0.0:${PORT:-993}"
echo "[telemt] TLS domain: ${TLS_DOMAIN:-unknown}"
echo "[telemt] Users: ${USER_COUNT}"
echo "================================================"

# Start telemt with config file
cd /app
exec telemt "$CONFIG_FILE"
