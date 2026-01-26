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

    echo "[stats] Capturing on $iface (local: $local_ip) for ${CAPTURE_DURATION}s..."

    # Temp files
    raw_file="/tmp/traffic_raw_$$"
    from_file="/tmp/traffic_from_$$"
    to_file="/tmp/traffic_to_$$"

    # Capture traffic with tcpdump
    # Output: IP src.port > dst.port: ...
    timeout "$CAPTURE_DURATION" tcpdump -ni "$iface" -l -q 'ip and (tcp or udp) and not port 53' 2>/dev/null > "$raw_file" || true

    # Check if we got any data
    if [ ! -s "$raw_file" ]; then
        echo "[stats] No traffic captured"
        write_stats "running" "[]" "[]"
        rm -f "$raw_file"
        return 0
    fi

    # Parse tcpdump output and extract IPs
    > "$from_file"
    > "$to_file"

    # Process each line
    while IFS= read -r line; do
        # Extract IPs using grep
        ips=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -2)
        src=$(echo "$ips" | head -1)
        dst=$(echo "$ips" | tail -1)

        # Skip if no valid IPs
        [ -z "$src" ] || [ -z "$dst" ] && continue
        [ "$src" = "$dst" ] && continue

        # Skip private IPs (check both src and dst)
        case "$src" in
            10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|127.*|0.*) continue ;;
        esac
        case "$dst" in
            10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|127.*|0.*) continue ;;
        esac

        # Determine direction based on local IP
        if [ "$src" = "$local_ip" ]; then
            echo "$dst" >> "$to_file"
        elif [ "$dst" = "$local_ip" ]; then
            echo "$src" >> "$from_file"
        fi
    done < "$raw_file"

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
    rm -f "$raw_file" "$from_file" "$to_file" "$from_ips" "$to_ips" "$from_countries" "$to_countries"

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
