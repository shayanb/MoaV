#!/bin/sh
# =============================================================================
# Snowflake Proxy entrypoint with bandwidth limiting
# =============================================================================

# Log with timestamp (MM-DD HH:MM:SS - SERVICE - MESSAGE)
log() {
    echo "$(date '+%m-%d %H:%M:%S') - snowflake - $*"
}

SNOWFLAKE_BANDWIDTH="${SNOWFLAKE_BANDWIDTH:-50}"
SNOWFLAKE_CAPACITY="${SNOWFLAKE_CAPACITY:-20}"

log "Starting Tor Snowflake Proxy"
log "Bandwidth limit: ${SNOWFLAKE_BANDWIDTH} Mbps"
log "Max clients: ${SNOWFLAKE_CAPACITY}"

# Set up bandwidth limiting using tc (traffic control)
# This requires NET_ADMIN capability
setup_bandwidth_limit() {
    # Find the default interface
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -z "$IFACE" ]; then
        log "WARNING: Could not determine network interface, skipping bandwidth limit"
        return 1
    fi

    log "Setting up ${SNOWFLAKE_BANDWIDTH}Mbps limit on $IFACE"

    # Clear existing qdisc (ignore errors if none exists)
    tc qdisc del dev "$IFACE" root 2>/dev/null || true

    # Convert Mbps to kbit (1 Mbps = 1000 kbit)
    RATE_KBIT=$((SNOWFLAKE_BANDWIDTH * 1000))

    # Set up rate limiting using TBF (Token Bucket Filter)
    tc qdisc add dev "$IFACE" root tbf rate ${RATE_KBIT}kbit burst 32kbit latency 400ms

    if [ $? -eq 0 ]; then
        log "Bandwidth limit configured successfully"
        return 0
    else
        log "WARNING: Failed to set bandwidth limit"
        return 1
    fi
}

# Try to set up bandwidth limiting (requires NET_ADMIN)
setup_bandwidth_limit || log "Continuing without bandwidth limit"

# Run the proxy with capacity limit
log "Starting proxy..."
exec /bin/proxy \
    -capacity "${SNOWFLAKE_CAPACITY}" \
    -summary-interval 1h \
    -verbose
