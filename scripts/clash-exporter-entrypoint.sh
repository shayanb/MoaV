#!/bin/sh
# =============================================================================
# Clash Exporter entrypoint - reads Clash API secret from state
# =============================================================================

echo "[clash-exporter] Starting Clash Exporter"

# Read Clash API secret from state file
if [ -f "/state/keys/clash-api.env" ]; then
    export CLASH_TOKEN=$(grep "^CLASH_API_SECRET=" /state/keys/clash-api.env | cut -d'=' -f2)
    if [ -n "$CLASH_TOKEN" ]; then
        echo "[clash-exporter] Loaded API secret from state"
    fi
fi

# Default host if not set
CLASH_HOST="${CLASH_HOST:-moav-sing-box:9090}"
export CLASH_HOST

echo "[clash-exporter] Connecting to: $CLASH_HOST"

# Wait for sing-box to be ready
echo "[clash-exporter] Waiting for sing-box..."
waited=0
max_wait=60
while [ $waited -lt $max_wait ]; do
    if wget -q --spider "http://${CLASH_HOST}/version" 2>/dev/null; then
        echo "[clash-exporter] sing-box is ready"
        break
    fi
    sleep 2
    waited=$((waited + 2))
done

if [ $waited -ge $max_wait ]; then
    echo "[clash-exporter] WARNING: sing-box not responding, starting anyway..."
fi

# Run the exporter
exec /app/clash-exporter "$@"
