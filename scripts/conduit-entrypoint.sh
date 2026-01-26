#!/bin/sh
set -e

# =============================================================================
# Psiphon Conduit entrypoint
# =============================================================================

CONDUIT_BANDWIDTH="${CONDUIT_BANDWIDTH:-200}"
CONDUIT_MAX_CLIENTS="${CONDUIT_MAX_CLIENTS:-100}"
CONDUIT_DATA_DIR="${CONDUIT_DATA_DIR:-/data}"

echo "[conduit] Starting Psiphon Conduit"
echo "[conduit] Bandwidth limit: ${CONDUIT_BANDWIDTH} Mbps"
echo "[conduit] Max clients: $CONDUIT_MAX_CLIENTS"
echo "[conduit] Data directory: $CONDUIT_DATA_DIR"

exec /app/conduit start \
    -d "$CONDUIT_DATA_DIR" \
    -b "$CONDUIT_BANDWIDTH" \
    -m "$CONDUIT_MAX_CLIENTS" \
    -v
