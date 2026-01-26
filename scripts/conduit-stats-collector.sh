#!/bin/sh
# =============================================================================
# Conduit Stats Collector - Runs inside the conduit container
# Collects traffic stats with GeoIP country breakdown
# =============================================================================

STATS_FILE="${STATS_FILE:-/state/conduit-stats.json}"
CAPTURE_DURATION="${CAPTURE_DURATION:-10}"

# Write stats to file
write_stats() {
    cat > "$STATS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds 2>/dev/null || date)",
    "status": "$1",
    "connections": {"connecting": 0, "connected": 0},
    "bandwidth": {"upload": "0 B", "download": "0 B"},
    "traffic_from": $2,
    "traffic_to": $3,
    "capture_duration": $CAPTURE_DURATION,
    "error": null
}
EOF
}

# Get country for IP using geoiplookup
get_country() {
    result=$(geoiplookup "$1" 2>/dev/null | head -1)

    if echo "$result" | grep -q "IP Address not found"; then
        echo "Unknown"
        return
    fi

    # Extract country code and name
    country=$(echo "$result" | sed 's/.*: //' | cut -d',' -f1-2 | xargs)

    if [ -z "$country" ]; then
        echo "Unknown"
        return
    fi

    # Special handling for Iran
    if echo "$country" | grep -q "^IR"; then
        echo "IR, Iran - #FreeIran"
    else
        echo "$country"
    fi
}

# Capture traffic and aggregate by country
capture_traffic() {
    # Get local IP and interface
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}' | head -1)
    iface=$(ip route get 1.1.1.1 2>/dev/null | grep -o 'dev [^ ]*' | awk '{print $2}' | head -1)

    if [ -z "$iface" ]; then
        iface="eth0"
    fi

    if [ -z "$local_ip" ]; then
        echo "[stats] ERROR: Could not determine local IP"
        write_stats "error" "[]" "[]"
        return 1
    fi

    # Limit packets to avoid CPU overload (sample ~5000 packets max)
    MAX_PACKETS="${MAX_PACKETS:-5000}"

    echo "[stats] Capturing on $iface (local: $local_ip) for ${CAPTURE_DURATION}s (max ${MAX_PACKETS} packets)..."

    # Temp files
    from_file="/tmp/traffic_from_$$"
    to_file="/tmp/traffic_to_$$"

    # Capture and process in one pipeline using awk (much faster than shell loop)
    # tcpdump output format: "IP src.port > dst.port: ..."
    # -c limits packet count to prevent CPU overload
    timeout "$CAPTURE_DURATION" tcpdump -ni "$iface" -l -q -c "$MAX_PACKETS" \
        'ip and (tcp or udp) and not port 53' 2>/dev/null | \
    awk -v local="$local_ip" -v from_file="$from_file" -v to_file="$to_file" '
        # Helper: check if IP is private
        function is_private(ip) {
            if (ip ~ /^10\./) return 1
            if (ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) return 1
            if (ip ~ /^192\.168\./) return 1
            if (ip ~ /^127\./) return 1
            if (ip ~ /^0\./) return 1
            return 0
        }

        # Extract IPs from each line
        {
            # Find all IP addresses in the line
            n = 0
            for (i = 1; i <= NF; i++) {
                # Match IP pattern (may have .port suffix)
                if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
                    gsub(/\.[0-9]+:?$/, "", $i)  # Remove port
                    gsub(/:$/, "", $i)           # Remove trailing colon
                    if (n == 0) src = $i
                    else if (n == 1) dst = $i
                    n++
                    if (n >= 2) break
                }
            }

            if (n < 2) next
            if (src == dst) next

            # Determine direction based on local IP
            if (src == local) {
                if (!is_private(dst)) print dst >> to_file
            } else if (dst == local) {
                if (!is_private(src)) print src >> from_file
            }
        }
    ' || true

    # Check if we got any data
    if [ ! -s "$from_file" ] && [ ! -s "$to_file" ]; then
        echo "[stats] No external traffic captured"
        write_stats "running" "[]" "[]"
        rm -f "$from_file" "$to_file"
        return 0
    fi

    # Count unique IPs and aggregate
    from_ips="/tmp/from_ips_$$"
    to_ips="/tmp/to_ips_$$"

    sort "$from_file" 2>/dev/null | uniq -c | sort -rn > "$from_ips" || true
    sort "$to_file" 2>/dev/null | uniq -c | sort -rn > "$to_ips" || true

    # Convert to country stats
    from_countries="/tmp/from_countries_$$"
    to_countries="/tmp/to_countries_$$"
    > "$from_countries"
    > "$to_countries"

    # Process FROM IPs (incoming traffic)
    while read count ip; do
        [ -z "$ip" ] && continue
        country=$(get_country "$ip")
        # Estimate bytes: count * 100 (avg packet size estimate)
        bytes=$((count * 100))
        echo "${country}|${bytes}|1" >> "$from_countries"
    done < "$from_ips"

    # Process TO IPs (outgoing traffic)
    while read count ip; do
        [ -z "$ip" ] && continue
        country=$(get_country "$ip")
        bytes=$((count * 100))
        echo "${country}|${bytes}|1" >> "$to_countries"
    done < "$to_ips"

    # Aggregate by country and generate JSON
    from_json=$(awk -F'|' '
        { traffic[$1]+=$2; count[$1]+=$3 }
        END {
            n=0
            for(c in traffic) {
                if(n>0) printf ","
                bytes=traffic[c]
                if(bytes<1024) { val=bytes; unit="B" }
                else if(bytes<1048576) { val=bytes/1024; unit="KB" }
                else if(bytes<1073741824) { val=bytes/1048576; unit="MB" }
                else { val=bytes/1073741824; unit="GB" }
                gsub(/"/, "\\\"", c)
                printf "{\"country\":\"%s\",\"bytes\":%d,\"formatted\":\"%.2f %s\",\"ips\":%d}", c, traffic[c], val, unit, count[c]
                n++
            }
        }
    ' "$from_countries" 2>/dev/null)

    to_json=$(awk -F'|' '
        { traffic[$1]+=$2; count[$1]+=$3 }
        END {
            n=0
            for(c in traffic) {
                if(n>0) printf ","
                bytes=traffic[c]
                if(bytes<1024) { val=bytes; unit="B" }
                else if(bytes<1048576) { val=bytes/1024; unit="KB" }
                else if(bytes<1073741824) { val=bytes/1048576; unit="MB" }
                else { val=bytes/1073741824; unit="GB" }
                gsub(/"/, "\\\"", c)
                printf "{\"country\":\"%s\",\"bytes\":%d,\"formatted\":\"%.2f %s\",\"ips\":%d}", c, traffic[c], val, unit, count[c]
                n++
            }
        }
    ' "$to_countries" 2>/dev/null)

    # Cleanup temp files
    rm -f "$from_file" "$to_file" "$from_ips" "$to_ips" "$from_countries" "$to_countries"

    # Write final stats
    write_stats "running" "[${from_json}]" "[${to_json}]"

    echo "[stats] Done - from: $(echo "$from_json" | grep -c country || echo 0) countries, to: $(echo "$to_json" | grep -c country || echo 0) countries"
}

# Main loop
main() {
    echo "[conduit-stats] Starting stats collector"
    echo "[conduit-stats] Stats file: $STATS_FILE"
    echo "[conduit-stats] Capture duration: ${CAPTURE_DURATION}s"

    # Ensure state directory exists
    mkdir -p "$(dirname "$STATS_FILE")" 2>/dev/null || true

    # Initial stats
    write_stats "initializing" "[]" "[]"

    # Wait for conduit to start
    sleep 5

    while true; do
        capture_traffic
        sleep 5
    done
}

# Single collection mode for CLI
if [ "${1:-}" = "--once" ]; then
    mkdir -p "$(dirname "$STATS_FILE")" 2>/dev/null || true
    capture_traffic
    cat "$STATS_FILE"
    exit 0
fi

main
