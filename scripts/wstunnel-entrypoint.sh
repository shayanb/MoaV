#!/bin/sh

# =============================================================================
# wstunnel entrypoint with logging
# =============================================================================

# Log with timestamp (MM-DD HH:MM:SS - SERVICE - MESSAGE)
log() {
    echo "$(date '+%m-%d %H:%M:%S') - wstunnel - $*"
}

WSTUNNEL_LISTEN="${WSTUNNEL_LISTEN:-0.0.0.0:8080}"
WSTUNNEL_RESTRICT="${WSTUNNEL_RESTRICT:-127.0.0.1:51820}"

log "Starting wstunnel WebSocket server"
log "Listen: ws://$WSTUNNEL_LISTEN"
log "Restrict to: $WSTUNNEL_RESTRICT"

# Run wstunnel server
log "Starting server..."
exec /app/wstunnel server --restrict-to "$WSTUNNEL_RESTRICT" "ws://$WSTUNNEL_LISTEN"
