#!/bin/bash
# TrustTunnel entrypoint script
set -e

CONFIG_DIR="/etc/trusttunnel"
LOG_LEVEL="${LOG_LEVEL:-info}"

echo "[TrustTunnel] Starting TrustTunnel VPN endpoint..."

# Check for required config files
if [[ ! -f "$CONFIG_DIR/vpn.toml" ]]; then
    echo "[TrustTunnel] ERROR: vpn.toml not found in $CONFIG_DIR"
    exit 1
fi

if [[ ! -f "$CONFIG_DIR/hosts.toml" ]]; then
    echo "[TrustTunnel] ERROR: hosts.toml not found in $CONFIG_DIR"
    exit 1
fi

if [[ ! -f "$CONFIG_DIR/credentials.toml" ]]; then
    echo "[TrustTunnel] ERROR: credentials.toml not found in $CONFIG_DIR"
    exit 1
fi

# Wait for certificates to be available
CERT_WAIT_TIMEOUT=60
CERT_WAIT_COUNT=0
DOMAIN="${DOMAIN:-}"

if [[ -n "$DOMAIN" ]]; then
    CERT_PATH="/certs/live/$DOMAIN/fullchain.pem"
    echo "[TrustTunnel] Waiting for TLS certificate at $CERT_PATH..."
    while [[ ! -f "$CERT_PATH" ]] && [[ $CERT_WAIT_COUNT -lt $CERT_WAIT_TIMEOUT ]]; do
        sleep 1
        ((CERT_WAIT_COUNT++))
    done

    if [[ ! -f "$CERT_PATH" ]]; then
        echo "[TrustTunnel] WARNING: Certificate not found after ${CERT_WAIT_TIMEOUT}s"
        echo "[TrustTunnel] TrustTunnel may fail to start without valid TLS certificates"
    else
        echo "[TrustTunnel] Certificate found!"
    fi
fi

echo "[TrustTunnel] Configuration:"
echo "  - Config: $CONFIG_DIR/vpn.toml"
echo "  - Hosts: $CONFIG_DIR/hosts.toml"
echo "  - Credentials: $CONFIG_DIR/credentials.toml"
echo "  - Log level: $LOG_LEVEL"

# Start TrustTunnel endpoint
cd /opt/trusttunnel
exec ./trusttunnel_endpoint \
    --loglvl "$LOG_LEVEL" \
    "$CONFIG_DIR/vpn.toml" \
    "$CONFIG_DIR/hosts.toml"
