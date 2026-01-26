#!/bin/sh
# =============================================================================
# Conduit Stats Collector - Runs inside the conduit container
# Collects traffic stats with GeoIP country breakdown
# =============================================================================

STATS_FILE="${STATS_FILE:-/state/conduit-stats.json}"
CAPTURE_DURATION="${CAPTURE_DURATION:-10}"

# Get local IP address
get_local_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}' | head -1
}

# Get primary network interface
get_interface() {
    ip route get 1.1.1.1 2>/dev/null | grep -o 'dev [^ ]*' | awk '{print $2}' | head -1
}

# Get country for IP using geoiplookup
get_country() {
    local ip="$1"
    local result=$(geoiplookup "$ip" 2>/dev/null | head -1)

    if echo "$result" | grep -q "IP Address not found"; then
        echo "Unknown"
        return
    fi

    # Extract country code and name
    local country=$(echo "$result" | sed 's/.*: //' | cut -d',' -f1-2 | xargs)

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

# Write initial/empty stats
write_stats() {
    local status="$1"
    local traffic_from="$2"
    local traffic_to="$3"

    cat > "$STATS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "status": "$status",
    "connections": {"connecting": 0, "connected": 0},
    "bandwidth": {"upload": "0 B", "download": "0 B"},
    "traffic_from": $traffic_from,
    "traffic_to": $traffic_to,
    "capture_duration": $CAPTURE_DURATION,
    "error": null
}
EOF
}

# Capture traffic and aggregate by country
capture_traffic() {
    local local_ip=$(get_local_ip)
    local iface=$(get_interface)

    if [ -z "$iface" ]; then
        iface="eth0"
    fi

    if [ -z "$local_ip" ]; then
        echo "[stats] Could not determine local IP"
        write_stats "error" "[]" "[]"
        return
    fi

    echo "[stats] Capturing on $iface (local IP: $local_ip) for ${CAPTURE_DURATION}s..."

    # Capture traffic - extract IPs and bytes
    # tcpdump output format: timestamp IP src > dst: proto length N
    local raw_file="/tmp/traffic_raw_$$"

    timeout "$CAPTURE_DURATION" tcpdump -ni "$iface" -l -q 'ip and (tcp or udp) and not port 53' 2>/dev/null | \
    while read line; do
        # Extract source and destination IPs
        src=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        dst=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -1)

        # Skip if no IPs found or same IP
        [ -z "$src" ] || [ -z "$dst" ] || [ "$src" = "$dst" ] && continue

        # Skip private IPs
        case "$src" in 10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|127.*) continue ;; esac
        case "$dst" in 10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|127.*) continue ;; esac

        # Default packet size estimate
        bytes=100

        # Determine direction
        if [ "$src" = "$local_ip" ]; then
            echo "TO $dst $bytes"
        elif [ "$dst" = "$local_ip" ]; then
            echo "FROM $src $bytes"
        fi
    done > "$raw_file" || true

    # Aggregate by IP
    local from_ips="/tmp/from_ips_$$"
    local to_ips="/tmp/to_ips_$$"

    grep "^FROM" "$raw_file" 2>/dev/null | awk '{traffic[$2]+=$3} END {for(ip in traffic) print ip, traffic[ip]}' > "$from_ips" || true
    grep "^TO" "$raw_file" 2>/dev/null | awk '{traffic[$2]+=$3} END {for(ip in traffic) print ip, traffic[ip]}' > "$to_ips" || true

    # Convert to country stats
    local from_countries="/tmp/from_countries_$$"
    local to_countries="/tmp/to_countries_$$"

    > "$from_countries"
    > "$to_countries"

    # Process FROM IPs
    while read ip bytes; do
        [ -z "$ip" ] && continue
        country=$(get_country "$ip")
        echo "$country|$bytes" >> "$from_countries"
    done < "$from_ips"

    # Process TO IPs
    while read ip bytes; do
        [ -z "$ip" ] && continue
        country=$(get_country "$ip")
        echo "$country|$bytes" >> "$to_countries"
    done < "$to_ips"

    # Aggregate by country
    local from_json=$(awk -F'|' '
        {traffic[$1]+=$2; count[$1]++}
        END {
            n=0
            for(c in traffic) {
                if(n>0) printf ","
                bytes=traffic[c]
                if(bytes<1024) { val=bytes; unit="B" }
                else if(bytes<1048576) { val=bytes/1024; unit="KB" }
                else if(bytes<1073741824) { val=bytes/1048576; unit="MB" }
                else { val=bytes/1073741824; unit="GB" }
                printf "{\"country\":\"%s\",\"bytes\":%d,\"formatted\":\"%.2f %s\",\"ips\":%d}", c, traffic[c], val, unit, count[c]
                n++
            }
        }
    ' "$from_countries" 2>/dev/null | sort -t':' -k2 -nr | head -10)

    local to_json=$(awk -F'|' '
        {traffic[$1]+=$2; count[$1]++}
        END {
            n=0
            for(c in traffic) {
                if(n>0) printf ","
                bytes=traffic[c]
                if(bytes<1024) { val=bytes; unit="B" }
                else if(bytes<1048576) { val=bytes/1024; unit="KB" }
                else if(bytes<1073741824) { val=bytes/1048576; unit="MB" }
                else { val=bytes/1073741824; unit="GB" }
                printf "{\"country\":\"%s\",\"bytes\":%d,\"formatted\":\"%.2f %s\",\"ips\":%d}", c, traffic[c], val, unit, count[c]
                n++
            }
        }
    ' "$to_countries" 2>/dev/null | sort -t':' -k2 -nr | head -10)

    # Cleanup
    rm -f "$raw_file" "$from_ips" "$to_ips" "$from_countries" "$to_countries"

    # Write stats
    write_stats "running" "[${from_json}]" "[${to_json}]"

    echo "[stats] Stats updated"
}

# Main loop
main() {
    echo "[conduit-stats] Starting stats collector"
    echo "[conduit-stats] Stats file: $STATS_FILE"
    echo "[conduit-stats] Capture duration: ${CAPTURE_DURATION}s"

    # Ensure state directory exists
    mkdir -p "$(dirname "$STATS_FILE")"

    # Initial empty stats
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
    mkdir -p "$(dirname "$STATS_FILE")"
    capture_traffic
    cat "$STATS_FILE"
    exit 0
fi

main
