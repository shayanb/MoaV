#!/bin/sh
# =============================================================================
# Snowflake Proxy entrypoint with bandwidth limiting
# =============================================================================

SNOWFLAKE_BANDWIDTH="${SNOWFLAKE_BANDWIDTH:-50}"
SNOWFLAKE_CAPACITY="${SNOWFLAKE_CAPACITY:-20}"

echo "[snowflake] Starting Tor Snowflake Proxy"
echo "[snowflake] Bandwidth limit: ${SNOWFLAKE_BANDWIDTH} Mbps"
echo "[snowflake] Max clients: ${SNOWFLAKE_CAPACITY}"

# Set up bandwidth limiting using tc (traffic control)
# This requires NET_ADMIN capability
setup_bandwidth_limit() {
    # Find the default interface
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -z "$IFACE" ]; then
        echo "[snowflake] WARNING: Could not determine network interface, skipping bandwidth limit"
        return 1
    fi

    echo "[snowflake] Setting up ${SNOWFLAKE_BANDWIDTH}Mbps limit on $IFACE"

    # Clear existing qdisc (ignore errors if none exists)
    tc qdisc del dev "$IFACE" root 2>/dev/null || true

    # Add HTB qdisc with bandwidth limit
    # Convert Mbps to kbit (1 Mbps = 1000 kbit)
    RATE_KBIT=$((SNOWFLAKE_BANDWIDTH * 1000))

    # Set up rate limiting
    tc qdisc add dev "$IFACE" root tbf rate ${RATE_KBIT}kbit burst 32kbit latency 400ms

    if [ $? -eq 0 ]; then
        echo "[snowflake] Bandwidth limit configured successfully"
        return 0
    else
        echo "[snowflake] WARNING: Failed to set bandwidth limit"
        return 1
    fi
}

# Try to set up bandwidth limiting (requires NET_ADMIN)
if [ "$(id -u)" = "0" ]; then
    setup_bandwidth_limit || echo "[snowflake] Continuing without bandwidth limit"
fi

# Run the proxy with capacity limit
# Drop privileges to nobody using su-exec if running as root
if [ "$(id -u)" = "0" ]; then
    echo "[snowflake] Dropping privileges to nobody"
    exec su-exec nobody /bin/proxy \
        -capacity "${SNOWFLAKE_CAPACITY}" \
        -summary-interval 1h \
        -verbose
else
    exec /bin/proxy \
        -capacity "${SNOWFLAKE_CAPACITY}" \
        -summary-interval 1h \
        -verbose
fi
