#!/bin/bash
set -euo pipefail

# =============================================================================
# Renew TLS certificates
# Run via cron: 0 3 * * * /opt/moav/scripts/cert-renew.sh
# =============================================================================

cd "$(dirname "$0")/.."

source scripts/lib/common.sh

log_info "Checking certificate renewal..."

# Run certbot renewal
docker compose run --rm certbot renew --quiet

# Reload sing-box to pick up new certs
if docker compose ps sing-box --status running >/dev/null 2>&1; then
    log_info "Reloading sing-box..."
    docker compose exec sing-box sing-box reload 2>/dev/null || \
        docker compose restart sing-box
fi

log_info "Certificate renewal check complete"
