#!/bin/sh

# =============================================================================
# Admin dashboard entrypoint with logging
# =============================================================================

# Log with timestamp (MM-DD HH:MM:SS - SERVICE - MESSAGE)
log() {
    echo "$(date '+%m-%d %H:%M:%S') - admin - $*"
}

log "Starting MoaV Admin Dashboard"
log "Port: 8443"

# Check for SSL certificates
CERT_DIRS=$(find /certs/live -maxdepth 1 -type d 2>/dev/null | tail -n +2 | head -1)
if [ -n "$CERT_DIRS" ]; then
    log "SSL: Enabled (found certificates)"
else
    log "SSL: Disabled (no certificates found)"
fi

# Run the dashboard
log "Starting uvicorn server..."
exec python main.py
