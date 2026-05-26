#!/bin/bash
# Run this after every Conduit restart to update the lifetime byte offsets.
# Recovers the pre-restart running total from Prometheus, rewrites the rules
# file, and reloads Prometheus so the *_lifetime totals keep climbing.
#
# Usage: ./scripts/update-conduit-offsets.sh
#
# Reaching Prometheus: by default this talks to the running `prometheus`
# container via `docker compose exec` (always reachable at its own :9091, no
# host port publishing required — MoaV exposes Prometheus internally, not on the
# host). To point at Prometheus some other way, set PROM_URL to a host-reachable
# base URL, e.g. PROM_URL=http://localhost:9091 (only works if you've published
# the port under `ports:`), or an external Prometheus.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULES_FILE="${PROJECT_DIR}/configs/monitoring/conduit_lifetime.rules.yml"
PROM_URL="${PROM_URL:-}"   # empty = go through the prometheus container

# Fetch a PromQL query, printing the raw JSON response on stdout.
prom_get() {
    local q
    q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1")
    if [[ -n "$PROM_URL" ]]; then
        curl -sf "${PROM_URL}/api/v1/query?query=${q}"
    else
        ( cd "$PROJECT_DIR" && docker compose exec -T prometheus \
            wget -qO- "http://localhost:9091/api/v1/query?query=${q}" )
    fi
}

# Preflight: confirm Prometheus is reachable before touching anything, so we
# fail with a clear message instead of a JSON-decode traceback on empty input.
if ! prom_get "vector(1)" >/dev/null 2>&1; then
    echo "ERROR: cannot reach Prometheus." >&2
    if [[ -n "$PROM_URL" ]]; then
        echo "  PROM_URL=$PROM_URL is not responding." >&2
    else
        echo "  The 'prometheus' container isn't running (or 'docker compose exec' failed)." >&2
        echo "  Start monitoring with: moav start monitoring" >&2
        echo "  ...or set PROM_URL to a reachable Prometheus address." >&2
    fi
    exit 1
fi

# Print the integer value of a single-series query (0 if empty / unparseable).
query() {
    prom_get "$1" | python3 -c "import json,sys
try:
    r = json.load(sys.stdin)['data']['result']
    print(int(float(r[0]['value'][1])) if r else 0)
except Exception:
    print(0)"
}

echo "Querying Prometheus for lifetime offsets..."

# Recover the pre-restart running total, then subtract the current (post-restart)
# session so the new offset = everything accumulated *before* this session.
#
# Query the *_lifetime recording rule, not the raw conduit_bytes_* gauge: the raw
# gauge's max is only the single largest session, so basing the offset on it
# would discard every other prior session and undercount across multiple
# restarts. The lifetime metric already carries the cumulative total, so its peak
# is the true high-water mark. On the very first run the recording rule hasn't
# been evaluated yet (no lifetime series → query returns 0), so fall back to the
# raw gauge for that one bootstrap case.
#
# Window is 15d to match Prometheus' --storage.tsdb.retention.time=15d; samples
# older than retention aren't queryable anyway. Run this soon after a restart.
DL=$(query "max_over_time(conduit_bytes_downloaded_lifetime[15d])")
[[ "$DL" -eq 0 ]] && DL=$(query "max_over_time(conduit_bytes_downloaded[15d])")
UL=$(query "max_over_time(conduit_bytes_uploaded_lifetime[15d])")
[[ "$UL" -eq 0 ]] && UL=$(query "max_over_time(conduit_bytes_uploaded[15d])")
CURRENT_DL=$(query "conduit_bytes_downloaded")
CURRENT_UL=$(query "conduit_bytes_uploaded")

DL_OFFSET=$((DL - CURRENT_DL))
UL_OFFSET=$((UL - CURRENT_UL))

# Never let a transient/empty read push the running total backwards.
[[ "$DL_OFFSET" -lt 0 ]] && DL_OFFSET=0
[[ "$UL_OFFSET" -lt 0 ]] && UL_OFFSET=0
DATE=$(date "+%Y-%m-%d")
DL_GB=$(python3 -c "print(f'{$DL_OFFSET/1e9:.1f}')")
UL_GB=$(python3 -c "print(f'{$UL_OFFSET/1e9:.1f}')")

echo "Download offset: $DL_OFFSET bytes ($DL_GB GB)"
echo "Upload offset:   $UL_OFFSET bytes ($UL_GB GB)"

cat > "$RULES_FILE" << EOF
groups:
  - name: conduit_lifetime
    rules:
      # Lifetime bandwidth totals that survive Conduit process restarts.
      # OFFSET values = bytes accumulated in all previous runs.
      # Run scripts/update-conduit-offsets.sh after each Conduit restart.
      #
      # Last updated: $DATE
      # Download offset: $DL_OFFSET bytes ($DL_GB GB)
      # Upload offset:   $UL_OFFSET bytes ($UL_GB GB)

      - record: conduit_bytes_downloaded_lifetime
        expr: conduit_bytes_downloaded + $DL_OFFSET

      - record: conduit_bytes_uploaded_lifetime
        expr: conduit_bytes_uploaded + $UL_OFFSET
EOF

# Reload via SIGHUP — Prometheus re-reads its config and rule files on HUP. This
# is tool-independent (no dependency on the lifecycle API or a POST-capable
# client in the container) and works whether or not 9091 is host-published.
if ( cd "$PROJECT_DIR" && docker compose kill -s SIGHUP prometheus ) >/dev/null 2>&1; then
    echo "✓ Prometheus reloaded (SIGHUP)"
else
    echo "⚠ Could not signal Prometheus — reload manually:"
    echo "    docker compose kill -s SIGHUP prometheus"
fi
echo "✓ Offsets updated in $RULES_FILE"
