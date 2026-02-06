#!/bin/sh
set -e

# =============================================================================
# Psiphon Conduit entrypoint
# =============================================================================

CONDUIT_BANDWIDTH="${CONDUIT_BANDWIDTH:-200}"
CONDUIT_MAX_CLIENTS="${CONDUIT_MAX_CLIENTS:-100}"
CONDUIT_DATA_DIR="${CONDUIT_DATA_DIR:-/data}"
CONDUIT_STATS_ENABLED="${CONDUIT_STATS_ENABLED:-false}"

echo "[conduit] Starting Psiphon Conduit"
echo "[conduit] Bandwidth limit: ${CONDUIT_BANDWIDTH} Mbps"
echo "[conduit] Max clients: $CONDUIT_MAX_CLIENTS"
echo "[conduit] Data directory: $CONDUIT_DATA_DIR"

# Start stats collector in background if enabled
if [ "$CONDUIT_STATS_ENABLED" = "true" ] && [ -x /usr/local/bin/conduit-stats ]; then
    echo "[conduit] Starting stats collector in background"
    /usr/local/bin/conduit-stats &
    STATS_PID=$!
    echo "[conduit] Stats collector PID: $STATS_PID"
fi

# Handle shutdown gracefully - use signal numbers for POSIX compatibility
# 15 = SIGTERM, 2 = SIGINT
cleanup() {
    echo "[conduit] Shutting down..."
    if [ -n "$STATS_PID" ]; then
        kill "$STATS_PID" 2>/dev/null || true
    fi
    if [ -n "$CONDUIT_PID" ]; then
        kill "$CONDUIT_PID" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup 15 2

# Run conduit in foreground
# Strip application timestamps (Docker already adds them)
/app/conduit start \
    -d "$CONDUIT_DATA_DIR" \
    -b "$CONDUIT_BANDWIDTH" \
    -m "$CONDUIT_MAX_CLIENTS" \
    -v 2>&1 | sed -u 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\} //' &
CONDUIT_PID=$!

# Wait for conduit to exit
wait $CONDUIT_PID
