#!/bin/sh
# =============================================================================
# Grafana entrypoint with SSL certificate detection and custom branding
# =============================================================================

echo "[grafana] Starting MoaV Grafana Dashboard"

# Determine app title (for PWA name on phone home screen)
# Priority: GRAFANA_APP_TITLE > "MoaV - DOMAIN" > "MoaV - SERVER_IP" > "MoaV"
if [ -n "$GRAFANA_APP_TITLE" ]; then
    APP_TITLE="$GRAFANA_APP_TITLE"
elif [ -n "$DOMAIN" ]; then
    APP_TITLE="MoaV - ${DOMAIN}"
elif [ -n "$SERVER_IP" ]; then
    APP_TITLE="MoaV - ${SERVER_IP}"
else
    APP_TITLE="MoaV"
fi
echo "[grafana] App title: $APP_TITLE"

# Construct Grafana root URL from subdomain + domain
if [ -n "$GRAFANA_SUBDOMAIN" ] && [ -n "$DOMAIN" ]; then
    export GF_SERVER_ROOT_URL="https://${GRAFANA_SUBDOMAIN}.${DOMAIN}:2083/"
    echo "[grafana] Root URL: $GF_SERVER_ROOT_URL"
fi

# =============================================================================
# Install MoaV branding (Grafana OSS requires direct file replacement)
# Note: GF_BRANDING_* env vars are Enterprise-only features
# =============================================================================
GRAFANA_IMG="/usr/share/grafana/public/img"
GRAFANA_BUILD="/usr/share/grafana/public/build"

if [ -d "/branding" ]; then
    echo "[grafana] Installing MoaV branding..."

    # Replace favicon (browser tab icon)
    if [ -f "/branding/favicon.png" ]; then
        cp /branding/favicon.png "$GRAFANA_IMG/fav32.png" && echo "[grafana] Replaced fav32.png"
        cp /branding/favicon.png "$GRAFANA_IMG/apple-touch-icon.png" && echo "[grafana] Replaced apple-touch-icon.png"
    fi

    # Replace login page logo (Grafana uses grafana_icon.svg)
    # Create an SVG wrapper that embeds the PNG as base64
    if [ -f "/branding/logo.png" ]; then
        # Get image dimensions (default to 100x100 if not determinable)
        LOGO_B64=$(base64 -w0 /branding/logo.png 2>/dev/null || base64 /branding/logo.png)
        cat > "$GRAFANA_IMG/grafana_icon.svg" << SVGEOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100">
  <image width="100" height="100" xlink:href="data:image/png;base64,$LOGO_B64"/>
</svg>
SVGEOF
        echo "[grafana] Created grafana_icon.svg from logo.png"
    fi

    # Replace app title in JavaScript bundles (affects browser tab and PWA name)
    # This searches for the default "Grafana" title and replaces it
    if [ -d "$GRAFANA_BUILD" ]; then
        echo "[grafana] Patching app title to: $APP_TITLE"
        # Find and replace AppTitle in JS bundles
        for js_file in "$GRAFANA_BUILD"/*.js; do
            if [ -f "$js_file" ]; then
                # Replace various patterns where Grafana title appears
                if grep -q '"AppTitle","Grafana"' "$js_file" 2>/dev/null; then
                    sed -i "s/\"AppTitle\",\"Grafana\"/\"AppTitle\",\"$APP_TITLE\"/g" "$js_file"
                    echo "[grafana] Patched AppTitle in $(basename "$js_file")"
                fi
                # Also try other common patterns
                if grep -q 'title:"Grafana"' "$js_file" 2>/dev/null; then
                    sed -i "s/title:\"Grafana\"/title:\"$APP_TITLE\"/g" "$js_file"
                fi
            fi
        done
    fi

    echo "[grafana] MoaV branding installed"
fi

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
