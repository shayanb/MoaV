#!/bin/bash
# Long-running watcher that re-banks Conduit lifetime offsets whenever the
# Conduit container (re)starts. Installed as a systemd service by
# `moav conduit-offsets install`.
#
# Why a watcher: conduit_bytes_* are gauges that reset to 0 on every Conduit
# restart. update-conduit-offsets.sh "banks" the just-ended session into the
# persistent offset so the *_lifetime totals keep climbing — but only if it runs
# promptly after each restart. Reacting to docker `start` events covers
# crash-restarts (restart: unless-stopped), host reboots, and manual restarts
# alike, and runs at the one moment the banking is exact (raw gauge ~0).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="${SCRIPT_DIR}/update-conduit-offsets.sh"
CONTAINER="${CONDUIT_CONTAINER:-moav-conduit}"

# Wait this long after a start event before banking, so Prometheus has scraped
# the post-restart reset (default scrape interval is 30s; wait a bit longer).
# Running before the scrape would read the stale pre-restart value as "current"
# and bank a no-op offset, losing the just-ended session.
SETTLE="${CONDUIT_OFFSETS_SETTLE:-45}"

log() { echo "[conduit-offsets] $*"; }

bank() {
    sleep "$SETTLE"
    if "$UPDATE"; then
        log "offsets updated"
    else
        log "update failed (will retry on next $CONTAINER start)"
    fi
}

log "watching docker '$CONTAINER' start events (settle ${SETTLE}s)"

# Bank once at startup too: covers the case where Conduit restarted while this
# watcher was down. Harmless mid-session (the offset is idempotent when no
# restart happened). Backgrounded so it doesn't delay attaching to the stream.
bank &

# React to every start. `docker events` blocks; if the stream ends (e.g. docker
# daemon restart) the loop exits and systemd (Restart=always) brings us back.
docker events --filter "container=${CONTAINER}" --filter "event=start" --format '{{.Time}}' \
| while read -r _; do
    log "$CONTAINER started — re-banking in ${SETTLE}s"
    bank
done
