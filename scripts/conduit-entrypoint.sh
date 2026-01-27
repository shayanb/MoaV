#!/bin/sh
set -e

# =============================================================================
# Psiphon Conduit entrypoint
# =============================================================================

# Log with timestamp (MM-DD HH:MM:SS - SERVICE - MESSAGE)
log() {
    echo "$(date '+%m-%d %H:%M:%S') - conduit - $*"
}

CONDUIT_BANDWIDTH="${CONDUIT_BANDWIDTH:-200}"
CONDUIT_MAX_CLIENTS="${CONDUIT_MAX_CLIENTS:-100}"
CONDUIT_DATA_DIR="${CONDUIT_DATA_DIR:-/data}"
CONDUIT_STATS_ENABLED="${CONDUIT_STATS_ENABLED:-true}"

log "Starting Psiphon Conduit"
log "Bandwidth limit: ${CONDUIT_BANDWIDTH} Mbps"
log "Max clients: $CONDUIT_MAX_CLIENTS"
log "Data directory: $CONDUIT_DATA_DIR"

# Start stats collector in background if enabled
if [ "$CONDUIT_STATS_ENABLED" = "true" ] && [ -x /usr/local/bin/conduit-stats ]; then
    log "Starting stats collector in background"
    /usr/local/bin/conduit-stats &
    STATS_PID=$!
    log "Stats collector PID: $STATS_PID"
fi

# Handle shutdown gracefully - use signal numbers for POSIX compatibility
# 15 = SIGTERM, 2 = SIGINT
cleanup() {
    log "Shutting down..."
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
/app/conduit start \
    -d "$CONDUIT_DATA_DIR" \
    -b "$CONDUIT_BANDWIDTH" \
    -m "$CONDUIT_MAX_CLIENTS" \
    -v &
CONDUIT_PID=$!

# Wait for conduit to exit
wait $CONDUIT_PID
