#!/bin/bash
set -euo pipefail

# =============================================================================
# Conduit Stats - Live traffic viewer by country
# =============================================================================

cd "$(dirname "$0")/.."

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# Check if container is running
if ! docker compose ps psiphon-conduit --status running &>/dev/null; then
    echo -e "${YELLOW}ERROR: Conduit container is not running${NC}"
    echo "Start with: docker compose --profile conduit up -d psiphon-conduit"
    exit 1
fi

# Function to display stats
display_stats() {
    local stats_json="$1"

    # Parse timestamp
    local timestamp=$(echo "$stats_json" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f2 | cut -d'+' -f1 | cut -d'.' -f1 2>/dev/null || echo "N/A")

    # Clear screen
    clear

    # Header
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${WHITE}LIVE PEER TRAFFIC BY COUNTRY${NC}                       ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Last Update: ${timestamp}                                    ${GREEN}[LIVE]${NC} ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Traffic FROM (incoming)
    echo -e "${GREEN} ⬇ TRAFFIC FROM ${DIM}(peers connecting to you)${NC}"
    echo ""
    printf "${WHITE}%-35s %15s %10s${NC}\n" "Country" "Total" "IPs"
    echo ""

    # Extract and display traffic_from
    local from_data=$(echo "$stats_json" | sed -n 's/.*"traffic_from":\[\([^]]*\)\].*/\1/p')
    if [ -n "$from_data" ] && [ "$from_data" != "" ]; then
        echo "$from_data" | tr '},{' '\n' | grep -E '"country"|"formatted"|"ips"' | \
        paste - - - 2>/dev/null | while read line; do
            local country=$(echo "$line" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
            local formatted=$(echo "$line" | grep -o '"formatted":"[^"]*"' | cut -d'"' -f4)
            local ips=$(echo "$line" | grep -o '"ips":[0-9]*' | cut -d':' -f2)
            if [ -n "$country" ]; then
                printf "%-35s %15s %10s\n" "$country" "${formatted:-0 B}" "${ips:-0}"
            fi
        done
    else
        echo -e "${DIM}No incoming traffic captured yet${NC}"
    fi

    echo ""
    echo ""

    # Traffic TO (outgoing)
    echo -e "${YELLOW} ⬆ TRAFFIC TO ${DIM}(data sent to peers)${NC}"
    echo ""
    printf "${WHITE}%-35s %15s %10s${NC}\n" "Country" "Total" "IPs"
    echo ""

    # Extract and display traffic_to
    local to_data=$(echo "$stats_json" | sed -n 's/.*"traffic_to":\[\([^]]*\)\].*/\1/p')
    if [ -n "$to_data" ] && [ "$to_data" != "" ]; then
        echo "$to_data" | tr '},{' '\n' | grep -E '"country"|"formatted"|"ips"' | \
        paste - - - 2>/dev/null | while read line; do
            local country=$(echo "$line" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
            local formatted=$(echo "$line" | grep -o '"formatted":"[^"]*"' | cut -d'"' -f4)
            local ips=$(echo "$line" | grep -o '"ips":[0-9]*' | cut -d':' -f2)
            if [ -n "$country" ]; then
                printf "%-35s %15s %10s\n" "$country" "${formatted:-0 B}" "${ips:-0}"
            fi
        done
    else
        echo -e "${DIM}No outgoing traffic captured yet${NC}"
    fi

    echo ""
    echo -e "${DIM}Capturing traffic... Press Ctrl+C to exit${NC}"
}

# Main
echo "Starting Conduit stats viewer..."
echo "Collecting initial data (takes ~15 seconds)..."

# Main loop
while true; do
    # Collect stats by running the collector once
    stats=$(docker compose exec -T psiphon-conduit conduit-stats --once 2>/dev/null || echo '{"timestamp":"error","traffic_from":[],"traffic_to":[]}')

    # Display
    display_stats "$stats"

    # Countdown
    for i in $(seq 15 -1 1); do
        printf "\r${DIM}Next update in %2ds...${NC}" "$i"
        sleep 1
    done
done
