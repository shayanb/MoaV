#!/bin/sh
# =============================================================================
# Snowflake Proxy entrypoint with bandwidth limiting and logging
# =============================================================================

SNOWFLAKE_BANDWIDTH="${SNOWFLAKE_BANDWIDTH:-50}"
SNOWFLAKE_CAPACITY="${SNOWFLAKE_CAPACITY:-20}"
LOG_FILE="/var/log/snowflake/snowflake.log"

# Ensure log directory exists
mkdir -p /var/log/snowflake

echo "[snowflake] Starting Tor Snowflake Proxy"
echo "[snowflake] Bandwidth limit: ${SNOWFLAKE_BANDWIDTH} Mbps"
echo "[snowflake] Max clients: ${SNOWFLAKE_CAPACITY}"
echo "[snowflake] Log file: ${LOG_FILE}"

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

    # Convert Mbps to kbit (1 Mbps = 1000 kbit)
    RATE_KBIT=$((SNOWFLAKE_BANDWIDTH * 1000))

    # Set up rate limiting using TBF (Token Bucket Filter)
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
setup_bandwidth_limit || echo "[snowflake] Continuing without bandwidth limit"

# Run the proxy with output tee'd to both stdout and log file (for metrics exporter)
echo "[snowflake] Starting proxy..."
exec /bin/proxy \
    -capacity "${SNOWFLAKE_CAPACITY}" \
    -summary-interval 90s \
    -verbose 2>&1 | tee -a "${LOG_FILE}"
