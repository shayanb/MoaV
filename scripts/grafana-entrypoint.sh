#!/bin/sh
# =============================================================================
# Grafana entrypoint with SSL certificate detection
# =============================================================================

echo "[grafana] Starting MoaV Grafana Dashboard"

# Set dynamic app title (affects PWA name on phone)
# Priority: GRAFANA_APP_TITLE > "MoaV - DOMAIN" > "MoaV - SERVER_IP" > "MoaV Monitoring"
if [ -n "$GRAFANA_APP_TITLE" ]; then
    export GF_BRANDING_APP_TITLE="$GRAFANA_APP_TITLE"
elif [ -n "$DOMAIN" ]; then
    export GF_BRANDING_APP_TITLE="MoaV - ${DOMAIN}"
elif [ -n "$SERVER_IP" ]; then
    export GF_BRANDING_APP_TITLE="MoaV - ${SERVER_IP}"
else
    export GF_BRANDING_APP_TITLE="MoaV Monitoring"
fi
echo "[grafana] App title: $GF_BRANDING_APP_TITLE"

# Install MoaV branding (logo, favicon)
if [ -d "/branding" ] && [ -f "/branding/logo.png" ]; then
    echo "[grafana] Installing branding files..."
    if cp /branding/logo.png /usr/share/grafana/public/img/moav_logo.png; then
        echo "[grafana] Copied logo.png"
    else
        echo "[grafana] ERROR: Failed to copy logo.png"
    fi
    if cp /branding/favicon.png /usr/share/grafana/public/img/moav_favicon.png; then
        echo "[grafana] Copied favicon.png"
    else
        echo "[grafana] ERROR: Failed to copy favicon.png"
    fi
    if cp /branding/favicon.ico /usr/share/grafana/public/img/moav_favicon.ico; then
        echo "[grafana] Copied favicon.ico"
    else
        echo "[grafana] ERROR: Failed to copy favicon.ico"
    fi

    # Verify files exist
    if [ -f "/usr/share/grafana/public/img/moav_logo.png" ]; then
        echo "[grafana] MoaV branding installed successfully"
    else
        echo "[grafana] WARNING: Branding files not found after copy"
    fi
fi

# Set branding env vars (must be done before exec, using URL paths)
export GF_BRANDING_LOGIN_LOGO="/public/img/moav_logo.png"
export GF_BRANDING_MENU_LOGO="/public/img/moav_favicon.png"
export GF_BRANDING_FAV_ICON="/public/img/moav_favicon.ico"
echo "[grafana] Branding env vars set"

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

# Background task to star all MoaV dashboards after Grafana is ready
star_dashboards() {
    echo "[grafana] Waiting for Grafana to be ready..."
    sleep 15  # Wait for Grafana to fully start

    # Wait for Grafana API to be available (up to 60 seconds)
    for i in $(seq 1 12); do
        if wget -q -O /dev/null "http://localhost:3000/api/health" 2>/dev/null; then
            break
        fi
        sleep 5
    done

    # Get admin password from env
    ADMIN_PASS="${GF_SECURITY_ADMIN_PASSWORD:-admin}"
    AUTH="admin:${ADMIN_PASS}"
    API="http://localhost:3000/api"

    # Star all MoaV dashboards
    for uid in moav-system moav-containers moav-singbox moav-wireguard moav-snowflake moav-conduit; do
        wget -q -O /dev/null --header="Content-Type: application/json" \
            --post-data="" \
            --auth-no-challenge \
            --user="admin" --password="${ADMIN_PASS}" \
            "${API}/user/stars/dashboard/uid/${uid}" 2>/dev/null && \
            echo "[grafana] Starred dashboard: ${uid}"
    done
    echo "[grafana] Dashboard starring complete"
}

# Run starring in background
star_dashboards &

# Run Grafana
exec /run.sh
