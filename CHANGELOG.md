# Changelog

All notable changes to MoaV will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Local Image Building** - Build container images locally for regions with blocked registries
  - `moav build --local` - builds commonly blocked images (cAdvisor, clash-exporter)
  - `moav build --local SERVICE` - builds specific image (prometheus, grafana, etc.)
  - `moav build --local all` - builds ALL external images locally
  - Automatically updates .env to use local images
  - Available images: cadvisor, clash-exporter, prometheus, grafana, node-exporter, nginx, certbot
  - Supports users in Iran, Russia, etc. where gcr.io/ghcr.io/Docker Hub are blocked
- **Configurable Container Images** - All external images now configurable via .env
  - `IMAGE_PROMETHEUS`, `IMAGE_GRAFANA`, `IMAGE_NODE_EXPORTER`, `IMAGE_CADVISOR`, etc.
  - Allows use of mirror registries when default registries are blocked

### Changed
- **Dockerfile Organization** - All Dockerfiles moved to `dockerfiles/` directory
  - Cleaner root directory structure
  - All docker compose commands work unchanged

### Fixed
- **Uninstall --wipe** - Now removes external Docker images (prometheus, grafana, cadvisor, etc.)
  - Previously only removed `moav-*` prefixed images
  - Now shows both built and pulled images before removal

## [1.3.3] - 2026-02-13

### Added
- **Grafana CDN Proxy** - Access Grafana through Cloudflare CDN for faster loading
  - New `grafana-proxy` nginx service on port 2083 (Cloudflare-supported HTTPS port)
  - Configure with `GRAFANA_SUBDOMAIN` in .env (e.g., `grafana.yourdomain.com:2083`)
  - Dynamic SSL certificate detection (Let's Encrypt or self-signed fallback)
- **Grafana MoaV Branding** - Custom logo, favicon, and app title
  - Replaces default Grafana branding with MoaV logo/favicon
  - Dynamic app title: "MoaV - {DOMAIN}" or "MoaV - {SERVER_IP}" for PWA home screen
  - Note: Uses file replacement since GF_BRANDING_* is Grafana Enterprise-only
- **Dashboard Auto-Starring** - All MoaV dashboards automatically starred on Grafana startup
- **Conduit Peak Clients** - New stat panel showing maximum concurrent clients in time range

### Changed
- **Subdomain Configuration** - Cleaner .env format for CDN settings
  - `GRAFANA_ROOT_URL` → `GRAFANA_SUBDOMAIN` (just subdomain, URL constructed automatically)
  - `CDN_DOMAIN` → `CDN_SUBDOMAIN` (just subdomain, URL constructed automatically)
- **Monitoring Default** - `ENABLE_MONITORING` no longer set in .env.example
  - Users are now prompted when selecting "all" services
  - Prevents accidental monitoring on low-RAM servers
- **Service URLs in output** - `moav start` now shows Grafana CDN URL and VLESS+WS CDN URL when configured

### Fixed
- **Domainless Mode** - Fixed bootstrap failing when running without a domain
  - Now properly disables all TLS protocols including TrustTunnel
  - Handles missing ENABLE_* vars in .env (adds them if not present)
- **CLASH_API_SECRET Flow** - Fixed monitoring setup during bootstrap
  - Secret is now properly copied from state volume to .env
  - `ensure_clash_api_secret()` runs before starting services after bootstrap
- **Entrypoint Permissions** - Added missing executable bit to entrypoint scripts
  - Fixes "modified files" warning during `moav update`
- **sing-box User Connections Table** - Fixed column display
  - Shows: User, Connections, Active (in correct order)
  - Hides metadata fields: __name__, instance, job
- **Snowflake Bandwidth Clarification** - Added tooltips explaining why container metrics (cAdvisor) show higher values than Snowflake dashboard (WebSocket/TLS overhead, broker connections)

## [1.3.1] - 2026-02-11

### Added
- **Conduit Exporter** - Custom Prometheus exporter for Psiphon Conduit metrics
  - Parses `[STATS]` lines from conduit logs
  - Exposes: connected/connecting clients, upload/download totals, uptime
  - New Grafana dashboard: MoaV - Conduit
- **Sing-box User Exporter** - Custom Prometheus exporter for user tracking
  - Parses sing-box logs for `[username]` connection patterns
  - Tracks active users (5-minute window), total users, per-user connections
  - Protocol breakdown (Reality, Trojan, Hysteria2, etc.)
  - Updated sing-box dashboard with user metrics table and protocol pie chart

### Changed
- **Monitoring intervals reduced** - Less CPU overhead
  - cAdvisor housekeeping: 10s → 30s
  - Prometheus scrape interval: 15s → 30s
- **Snowflake dashboard fixed** - Deduplicated metrics using `max()` aggregation
- **Container dashboard improved** - Network traffic now excludes monitoring containers
  - Filters out: prometheus, grafana, cadvisor, node-exporter, all exporters
  - Shows only actual proxy/service traffic
- Snowflake/WireGuard exporters now only run with `monitoring` profile (not standalone)
- Removed `docker compose ps` output after start commands (cleaner output)

### Fixed
- Conduit exporter no longer has cross-profile `depends_on` issue
- Fixed duplicate metrics in Snowflake Grafana dashboard (3x values shown)
- **Snowflake exporter replaced** - Custom optimized version instead of third-party
  - Fixes high CPU usage (20-90%) from inefficient log parsing
  - Uses file position tracking instead of constant re-reading
  - Adaptive sleep intervals (1s when active, 5s when idle)
- **Snowflake dashboard labels fixed** - Now shows user perspective:
  - "Users Downloaded" = bandwidth users received (was confusingly labeled "Upload")
  - "Users Uploaded" = bandwidth users sent (was confusingly labeled "Download")

## [1.3.0] - 2026-02-10

### Added
- **Monitoring Stack** - Optional Grafana + Prometheus observability (`monitoring` profile)
  - Grafana dashboards on port 9444 (configurable via `PORT_GRAFANA`)
  - Prometheus with 15-day retention (internal only, port 9091)
  - Node Exporter for system metrics (CPU, RAM, disk, network)
  - cAdvisor for container metrics (per-container CPU, memory, network)
  - Clash Exporter for sing-box proxy metrics (connections, traffic)
  - WireGuard Exporter for VPN peer statistics (peers, handshakes, traffic)
  - Snowflake Exporter for Tor donation metrics (people served, bandwidth donated)
  - Pre-built dashboards: System, Containers, sing-box, WireGuard, Snowflake
  - Uses existing `ADMIN_PASSWORD` for Grafana authentication
  - `moav start monitoring` or combine with other profiles
- `PORT_GRAFANA` environment variable (default: 9444)
- `ENABLE_MONITORING` toggle in .env
- **Batch user creation** - Create multiple users at once:
  - `moav user add alice bob charlie` - Add multiple named users
  - `moav user add --batch 5` - Create user01, user02, ..., user05
  - `moav user add --batch 10 --prefix team` - Create team01..team10
  - Smart numbering: skips existing users (if user01-03 exist, creates user04, user05)
  - Services reload once at the end (not after each user) for efficiency
  - `--package` flag works with batch mode

### Changed
- Admin dashboard simplified (connection/memory metrics moved to Grafana):
  - Removed Active Connections card
  - Removed Memory Usage card
  - Removed Active Connections table
  - Added Grafana link button in header
  - Kept: Conduit stats, User bundles, Service status, Total upload/download

### Fixed
- **`moav user revoke` menu crash** - User list script was crashing when listing WireGuard peers after a user was revoked
  - Fixed grep pattern to only extract usernames from [Peer] blocks
  - Added proper error handling for missing peer IPs

### Documentation
- Added `docs/MONITORING.md` with complete monitoring stack guide
- Documented: TrustTunnel and dnstt do not have metrics APIs (container metrics still available via cAdvisor)
- Added "Apply .env changes" section to TROUBLESHOOTING.md explaining that containers must be recreated (not just restarted) to pick up `.env` changes

### Added
- **Batch user creation** - Create multiple users at once:
  - `moav user add alice bob charlie` - Add multiple named users
  - `moav user add --batch 5` - Create user01, user02, ..., user05
  - `moav user add --batch 10 --prefix team` - Create team01..team10
  - Smart numbering: skips existing users (if user01-03 exist, creates user04, user05)
  - Services reload once at the end (not after each user) for efficiency
  - `--package` flag works with batch mode

### Fixed
- **`moav user revoke` menu crash** - User list script was crashing when listing WireGuard peers after a user was revoked
  - Fixed grep pattern to only extract usernames from [Peer] blocks
  - Added proper error handling for missing peer IPs

### Documentation
- Added "Apply .env changes" section to TROUBLESHOOTING.md explaining that containers must be recreated (not just restarted) to pick up `.env` changes

## [1.2.5] - 2026-02-07

### Added
- **`moav uninstall` command** - Clean uninstallation with two modes:
  - `moav uninstall` - Remove containers, keep data (.env, keys, bundles)
  - `moav uninstall --wipe` - Complete removal including all configs, keys, and user data
  - Optional Docker images cleanup prompt during --wipe
  - Verbose output showing each file/directory being removed
- **Component version update checking** - `moav update` now compares versions:
  - Compares .env with .env.example after git pull
  - Shows available updates for sing-box, wstunnel, conduit, snowflake, trusttunnel
  - Prompts to update versions in .env
  - Shows rebuild command: `moav build <services> --no-cache`
- **Unified service selection menu** - Beautiful table-based menu for start/stop/restart
  - Consistent UI across all service operations
  - "ALL" option highlighted as "(Recommended)" in green
  - Shows v2ray app compatibility for proxy protocols
- `moav build --no-cache` flag for forcing container rebuilds
- Logs menu "Last 100 lines + follow" option (shows tail then continues following)
- Cloudflare Origin Rule documentation for CDN mode (required for port 2082 routing)

### Changed
- Service selection menu improvements:
  - Proxy description: "Reality, Trojan, Hysteria2 (v2ray apps)"
  - TrustTunnel description: "TrustTunnel VPN (HTTP/2 + QUIC)"
  - Donation services: "Donate bandwidth via Psiphon/Tor"
  - Cancel option dimmed to de-emphasize
- Start/stop/restart now use unified menu instead of separate implementations
- dnstt auto-dependency (adding proxy) only applies to start, not stop/restart operations

### Fixed
- **WireGuard key generation permissions warning** - Now uses `umask 077` to create private keys with secure permissions (owner-only read)
- **Bootstrap missing python3** - Added python3 to Dockerfile.bootstrap for placeholder replacement
- Stop/restart stopping extra services - Auto-adding proxy for dnstt now only happens during start

### Documentation
- Complete CLI.md reference with all moav commands and options
- SETUP.md: Added "Uninstalling MoaV" section, expanded "Breaking Changes" guidance
- TROUBLESHOOTING.md: Added "Breaking changes after update" section with solutions
- DNS.md: Added Cloudflare Origin Rule setup for CDN mode (fixes 521 errors)
- Updated uninstall documentation across all relevant docs

## [1.2.4] - 2026-02-06

### Added
- **TrustTunnel VPN protocol integration** - Modern VPN protocol from AdGuard using HTTP/2 and HTTP/3 (QUIC)
  - New `trusttunnel` Docker service and profile
  - TrustTunnel endpoint on port 4443 (TCP+UDP)
  - Full TOML config generation for CLI client
  - TrustTunnel section in client guide (HTML) with all app fields
  - Admin dashboard: TrustTunnel service status and "TT" protocol tag for users
- TrustTunnel CLI client (`trusttunnel_client`) in client container for testing
- `moav start trusttunnel` and service menu option
- User bundles now include `trusttunnel.toml`, `trusttunnel.txt`, and `trusttunnel.json`

### Changed
- Client test gracefully falls back to endpoint reachability check when TUN device unavailable
- TrustTunnel app store links updated to correct URLs

### Fixed
- **README.html placeholder replacement broken** - Multiple issues fixed:
  - `local` variable used outside function causing script exit with `set -e`
  - sed `&` character interpreted as "matched pattern" in replacement strings
  - awk escape sequence warnings (`\&` treated as plain `&`)
  - Multiline WireGuard configs breaking sed commands
  - Now uses Python-based replacement for reliable handling of special characters and multiline content
- TrustTunnel CLI client requires `--config` flag (was missing)
- TrustTunnel credentials format: `[[client]]` not `[[credentials]]`, `[[main_hosts]]` not `[[hosts]]`

## [1.2.3] - 2026-02-06

### Added
- **CDN-fronted VLESS+WebSocket inbound** - New protocol for Cloudflare CDN-proxied connections
  - sing-box `vless-ws-in` inbound on port 2082 (plain HTTP, Cloudflare terminates TLS)
  - Uses same user UUIDs as Reality (no extra credentials)
  - Client links generated when `CDN_DOMAIN` is set in `.env`
- `CDN_DOMAIN` config option - Set to your Cloudflare-proxied subdomain (e.g., `cdn.yourdomain.com`)
- `CDN_WS_PATH` config option - WebSocket path (default: `/ws`)
- `PORT_CDN` config option - CDN inbound port (default: `2082`, a Cloudflare-allowed HTTP port)
- User bundles now include `cdn-vless-ws.txt`, `cdn-vless-ws-singbox.json`, and QR code when CDN is configured
- Documentation: "Adding a Domain After Domainless Setup" guide in SETUP.md
- Documentation: Full CDN setup guide with Cloudflare configuration steps

### Changed
- `moav status` now displays CDN domain when configured
- User add message now mentions CDN VLESS+WS
- DNS.md Cloudflare section now includes optional `cdn` A record (Proxied)

### Fixed
- **`moav client connect` failing while `moav test` works** - Connect mode was missing IPv6 URI parsing, causing "invalid address" errors when IPv6 configs were present
  - `extract_host()` and `extract_port()` now handle IPv6 URIs (`@[addr]:port` format)
  - Config file discovery now prefers IPv4 configs (`reality.txt`) before falling back to globs (`reality*.txt`)
  - WireGuard endpoint parsing now handles IPv6 addresses
  - Added field validation with debug logging for all protocols
  - Added port numeric validation for Reality and Trojan (was only in test mode)

## [1.2.2] - 2026-02-04

### Breaking Changes
- **Fresh setup required**: This version includes protocol changes (Hysteria2 obfuscation, Reality target) that require regenerating both server configuration and all user configs. Existing users must receive new config files.

### Added
- **Hysteria2 Salamander obfuscation** - Disguises QUIC traffic as random UDP to bypass Iranian/Chinese censorship
- `HYSTERIA2_OBFS_PASSWORD` config option (auto-generated if empty)
- `moav config rebuild` - Regenerates server config and all users with new credentials
- Update available notification in CLI header and admin dashboard
- Admin dashboard: User bundles table now shows creation date, sorted newest first
- Internet accessibility check (exit IP verification) for all protocol tests
- Component version management via `.env` file

### Changed
- Default Reality target changed from `www.microsoft.com` to `dl.google.com` (less fingerprinted in censored regions)
- DNS fallback servers: removed Cloudflare DoH (failing), added Google UDP and Quad9 UDP
- `moav config rebuild` simplified - cleanly regenerates everything instead of complex state preservation
- Admin dashboard UI improvements

### Fixed
- **Critical: dnstt traffic not routing** - sing-box mixed inbound was localhost-only
- **Critical: Client container architecture mismatch** - Fixed arm64/amd64 binary downloads
- Admin dashboard crash on load (`connection_stats` undefined)
- `moav logs` Ctrl+C now returns to menu instead of exiting
- `moav logs proxy` and `moav logs reality` aliases for sing-box
- `moav regenerate-users` now passes Hysteria2 obfuscation password
- `moav test` various fixes for dnstt and validation
- `moav update` conflicts from generated files

### Security
- Hysteria2 obfuscation helps bypass QUIC fingerprinting and blocking in Iran/China

## [1.2.0] - 2026-02-03

### Added
- `moav update -b BRANCH` - switch git branches during update (e.g., `moav update -b dev`)
- Profile aliases for `moav start`: `sing-box`, `singbox`, `reality`, `trojan`, `hysteria` → `proxy`
- Service aliases for restart/stop/logs: `proxy`, `reality` → `sing-box`
- Branch display in header and status when not on `main` branch
- `moav test` verbose flag (`-v` or `--verbose`) for debugging connection issues
- Multiple fallback DNS servers in sing-box config (Google, Cloudflare, Quad9 UDP)

### Changed
- `moav update` now shows help with `--help` flag
- `moav test` now prefers IPv4 configs over IPv6 (tests `reality.txt` before `reality-ipv6.txt`)
- `moav test` treats IPv6 network failures as warnings instead of errors (IPv6 may not be available in container)
- Improved gitignore for generated WireGuard and dnstt files

### Fixed
- `moav update -b BRANCH` arguments not being passed correctly
- Double header display when running `moav` interactive menu
- Script permissions (755) for all shell scripts in repository
- Generated files (server.pub, wg_confs/, coredns/) no longer trigger update conflicts
- **WireGuard-wstunnel not forwarding traffic** - wstunnel was trying to forward to localhost instead of wireguard container (changed `127.0.0.1:51820` to `moav-wireguard:51820`)
- `moav test` now correctly parses IPv6 addresses in URIs (e.g., `[2400:6180::1]:443`)
- `moav test` now validates parsed URI fields before generating config
- `moav test` now shows actual sing-box error messages instead of generic "failed to start"
- `moav test` now validates generated JSON config before running sing-box

## [1.1.2] - 2026-02-02

### Added
- One-click VPS deployment buttons for Hetzner, Linode, Vultr, DigitalOcean
- Cloud-init script for automated VPS provisioning
- First-login welcome prompt for cloud-deployed servers
- Home VPN server documentation (Raspberry Pi, ARM64 support)
- Dynamic DNS (DDNS) guide for home servers (DuckDNS, Cloudflare)
- VPS deployment guide (docs/DEPLOY.md)
- Bootstrap confirmation prompt before running
- Domain-less mode support (WireGuard, Conduit, Snowflake without TLS)
- First-run loading indicator ("First run - checking prerequisites...")
- Disabled service indicators in status display (`*` suffix with legend)
- Disabled service indicators in service selection menu (`(disabled)` text)
- Install script `-b BRANCH` flag for testing feature branches
- Admin dashboard: User Bundles section with download functionality
- `moav update` now shows current branch and warns if not on main/master
- Admin dashboard URL shown in menu, status, and after starting services
- Admin dashboard now works in domain-less mode using self-signed certificates
- Certbot status explanation in `moav status` (clarifies "Exited (0)" is expected)
- Admin URL now shows server public IP instead of localhost
- Bootstrap now auto-detects and saves SERVER_IP to .env if not set

### Changed
- Improved sing-box performance: disabled `sniff_override_destination`, disabled multiplex padding, enabled TCP Fast Open, use local DNS by default
- WireGuard entrypoint bypasses wg-quick to avoid Docker 29 compatibility issues
- WireGuard peer IP assignment now based on peer count (fixes demouser getting server IP)
- Service selection "ALL" now respects ENABLE_* settings (only starts enabled services)
- `moav stop` now uses `docker compose stop` instead of `down` (preserves container state)
- Certbot exits gracefully when no domain configured (domain-less mode)

### Fixed
- Admin dashboard using self-signed cert instead of Let's Encrypt (now waits for certbot)
- Admin dashboard "sing-box API timeout" error (memory endpoint is streaming, now reads first line only)
- WireGuard traffic not flowing (missing iptables FORWARD rule for return traffic)
- WireGuard "Permission denied" error on Docker 29 with Alpine
- WireGuard config parsing stripping trailing "=" from base64 keys
- WireGuard QR code showing "Invalid QR Code" in app due to non-hex IPv6 address (`fd00:moav:wg::` → `fd00:cafe:beef::`)
- WireGuard-wstunnel QR code not being generated in wg-user-add.sh (missing in README.html)
- Conduit status showing "never" even when running ([#7](https://github.com/shayanb/MoaV/issues/7))
- Reality URL `&` characters replaced with placeholder in README.html ([#8](https://github.com/shayanb/MoaV/issues/8))
- Architecture mismatch in Dockerfile.client - now uses TARGETARCH for multi-arch support ([#4](https://github.com/shayanb/MoaV/issues/4))
- Bootstrap failing in domain-less mode (missing ENABLE_* exports, conditional config generation)
- generate-user.sh unconditionally sourcing reality.env (now conditional on ENABLE_REALITY)
- generate-user.sh peer count calculation failing when grep returns no matches

## [1.1.1] - 2025-01-31

### Added
- Website link badge in README
- GitHub issue templates (bug reports, feature requests)
- "Your Protocol?" CTA card in Multi-Protocol Arsenal section
- Server Management demo on website

### Changed
- Status table column widths to accommodate longer service names

## [1.0.2] - 2025-01-31

### Added
- Ctrl+C handler with friendly goodbye message
- README.html generation in user bundles using client-guide-template
- Demo user notice (bilingual EN/FA) for bootstrap demouser
- Server Management demo on website
- Support for comma separator in multi-option selection (e.g., `1,2,4`)

### Changed
- Bootstrap now creates "demouser" when INITIAL_USERS=1 (instead of user01)
- User management menu now loops back after listing users
- Package command now places zip files in `outputs/bundles/` consistently
- Status table widened to accommodate longer service names (psiphon-conduit)
- Removed README.md from user bundles (HTML-only now)

### Fixed
- Export and regenerate-users now correctly find users from bundles directory
- Demo notice placeholders properly removed from non-demo user HTML
- Awk escape sequence warnings in HTML generation
- Package user menu option creating zip in wrong directory

## [1.0.1] - 2025-01-30

### Fixed
- Minor bug fixes and improvements

## [1.0.0] - 2025-01-28

### Added
- Initial release of MoaV multi-protocol circumvention stack
- **Protocols:**
  - Reality (VLESS) - Primary protocol with TLS camouflage
  - Trojan - TLS-based fallback on port 8443
  - Hysteria2 - QUIC/UDP-based for fast connections
  - WireGuard - Full VPN mode (direct and wstunnel-wrapped)
  - DNS Tunnel (dnstt) - Last resort for restrictive networks
  - Tor/Snowflake - Standalone fallback via Tor network
- **Server features:**
  - Docker Compose-based deployment
  - Multi-user management with per-user credentials
  - Automatic TLS certificate management via Caddy
  - Decoy website for traffic camouflage
  - Admin dashboard for monitoring
  - Psiphon Conduit for bandwidth donation
  - Snowflake proxy for Tor network contribution
- **Client features:**
  - Built-in client container for Linux/Docker
  - Test mode for connectivity verification
  - Connect mode with local SOCKS5/HTTP proxy
  - Auto protocol fallback
- **CLI tool (moav.sh):**
  - Interactive menu and command-line interface
  - User management (add/list/revoke)
  - Service management (start/stop/restart/logs)
  - Global installation support
- **Documentation:**
  - Setup guide with prerequisites
  - Client configuration guides for all platforms
  - Troubleshooting guide
  - Farsi (Persian) README

### Security
- Per-user UUID and password generation
- Reality protocol with XTLS Vision flow
- uTLS fingerprint spoofing (Chrome)
- Automatic short ID generation for Reality

[Unreleased]: https://github.com/shayanb/MoaV/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/shayanb/MoaV/compare/v1.2.5...v1.3.0
[1.2.5]: https://github.com/shayanb/MoaV/compare/v1.2.4...v1.2.5
[1.2.4]: https://github.com/shayanb/MoaV/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/shayanb/MoaV/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/shayanb/MoaV/compare/v1.2.0...v1.2.2
[1.2.0]: https://github.com/shayanb/MoaV/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/shayanb/MoaV/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/shayanb/MoaV/compare/v1.0.2...v1.1.1
[1.0.2]: https://github.com/shayanb/MoaV/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shayanb/MoaV/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shayanb/MoaV/releases/tag/v1.0.0
