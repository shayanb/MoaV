#!/bin/sh
# =============================================================================
# Grafana entrypoint with SSL certificate detection
# =============================================================================

echo "[grafana] Starting MoaV Grafana Dashboard"

# Find SSL certificates (same logic as admin)
find_certificates() {
    # Check for Let's Encrypt certificates first
    for cert_dir in /certs/live/*/; do
        if [ -d "$cert_dir" ]; then
            key_path="${cert_dir}privkey.pem"
            cert_path="${cert_dir}fullchain.pem"
            if [ -f "$key_path" ] && [ -f "$cert_path" ]; then
                echo "$key_path $cert_path"
                return 0
            fi
        fi
    done

    # Fallback to self-signed certificate
    if [ -f "/certs/selfsigned/privkey.pem" ] && [ -f "/certs/selfsigned/fullchain.pem" ]; then
        echo "/certs/selfsigned/privkey.pem /certs/selfsigned/fullchain.pem"
        return 0
    fi

    return 1
}

# Wait for certificates (up to 30 seconds)
waited=0
max_wait=30
while [ $waited -lt $max_wait ]; do
    certs=$(find_certificates)
    if [ -n "$certs" ]; then
        break
    fi
    echo "[grafana] Waiting for certificates..."
    sleep 5
    waited=$((waited + 5))
done

certs=$(find_certificates)
if [ -n "$certs" ]; then
    key_file=$(echo "$certs" | cut -d' ' -f1)
    cert_file=$(echo "$certs" | cut -d' ' -f2)
    echo "[grafana] SSL: Enabled"
    echo "[grafana] Key: $key_file"
    echo "[grafana] Cert: $cert_file"

    # Set Grafana SSL environment variables
    export GF_SERVER_PROTOCOL=https
    export GF_SERVER_CERT_KEY="$key_file"
    export GF_SERVER_CERT_FILE="$cert_file"
else
    echo "[grafana] SSL: Disabled (no certificates found)"
    export GF_SERVER_PROTOCOL=http
fi

# Test certificate readability and fall back to HTTP if not readable
if [ -n "$GF_SERVER_CERT_KEY" ]; then
    certs_ok=true
    if [ -r "$GF_SERVER_CERT_KEY" ]; then
        echo "[grafana] Key file readable: OK"
    else
        echo "[grafana] WARNING: Cannot read key file: $GF_SERVER_CERT_KEY"
        ls -la "$GF_SERVER_CERT_KEY" 2>&1 || echo "[grafana] File does not exist"
        certs_ok=false
    fi
    if [ -r "$GF_SERVER_CERT_FILE" ]; then
        echo "[grafana] Cert file readable: OK"
    else
        echo "[grafana] WARNING: Cannot read cert file: $GF_SERVER_CERT_FILE"
        ls -la "$GF_SERVER_CERT_FILE" 2>&1 || echo "[grafana] File does not exist"
        certs_ok=false
    fi

    # Fall back to HTTP if certs aren't readable
    if [ "$certs_ok" = "false" ]; then
        echo "[grafana] Falling back to HTTP mode"
        unset GF_SERVER_CERT_KEY
        unset GF_SERVER_CERT_FILE
        export GF_SERVER_PROTOCOL=http
    fi
fi

echo "[grafana] Starting Grafana server (protocol: $GF_SERVER_PROTOCOL)..."

# Run Grafana
exec /run.sh
