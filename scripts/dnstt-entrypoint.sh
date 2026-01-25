#!/bin/sh
set -e

# =============================================================================
# dnstt server entrypoint
# =============================================================================

DNSTT_DOMAIN="${DNSTT_DOMAIN:-t.example.com}"
DNSTT_LISTEN="${DNSTT_LISTEN:-:5353}"
DNSTT_UPSTREAM="${DNSTT_UPSTREAM:-127.0.0.1:8080}"
DNSTT_KEY_FILE="${DNSTT_KEY_FILE:-/state/keys/dnstt-server.key.hex}"

echo "[dnstt] Starting dnstt-server"
echo "[dnstt] Domain: $DNSTT_DOMAIN"
echo "[dnstt] Listen: $DNSTT_LISTEN"
echo "[dnstt] Upstream: $DNSTT_UPSTREAM"

# Wait for key file
timeout=60
elapsed=0
while [ ! -f "$DNSTT_KEY_FILE" ]; do
    echo "[dnstt] Waiting for key file at $DNSTT_KEY_FILE..."
    sleep 2
    elapsed=$((elapsed + 2))
    if [ $elapsed -ge $timeout ]; then
        echo "[dnstt] ERROR: Key file not found after ${timeout}s. Run bootstrap first."
        exit 1
    fi
done

# Read the hex-encoded private key
PRIVKEY=$(cat "$DNSTT_KEY_FILE" | tr -d '\n\r ')

echo "[dnstt] Private key loaded (${#PRIVKEY} chars)"

exec dnstt-server -udp "$DNSTT_LISTEN" -privkey "$PRIVKEY" "$DNSTT_DOMAIN" "$DNSTT_UPSTREAM"
