#!/bin/sh

# =============================================================================
# Admin dashboard entrypoint with logging
# =============================================================================

echo "[admin] Starting MoaV Admin Dashboard"
echo "[admin] Port: 8443"

# Check for SSL certificates
CERT_DIRS=$(find /certs/live -maxdepth 1 -type d 2>/dev/null | tail -n +2 | head -1)
if [ -n "$CERT_DIRS" ]; then
    echo "[admin] SSL: Enabled (found certificates)"
else
    echo "[admin] SSL: Disabled (no certificates found)"
fi

# Run the dashboard
echo "[admin] Starting uvicorn server..."
exec python main.py
