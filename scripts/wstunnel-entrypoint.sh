#!/bin/sh

# =============================================================================
# wstunnel entrypoint with logging
# =============================================================================

WSTUNNEL_LISTEN="${WSTUNNEL_LISTEN:-0.0.0.0:8080}"
WSTUNNEL_RESTRICT="${WSTUNNEL_RESTRICT:-127.0.0.1:51820}"

echo "[wstunnel] Starting wstunnel WebSocket server"
echo "[wstunnel] Listen: ws://$WSTUNNEL_LISTEN"
echo "[wstunnel] Restrict to: $WSTUNNEL_RESTRICT"

# Run wstunnel server
echo "[wstunnel] Starting server..."
exec /app/wstunnel server --restrict-to "$WSTUNNEL_RESTRICT" "ws://$WSTUNNEL_LISTEN"
