# Changelog

All notable changes to MoaV will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed
- WireGuard entrypoint bypasses wg-quick to avoid Docker 29 compatibility issues
- WireGuard peer IP assignment now based on peer count (fixes demouser getting server IP)
- Service selection "ALL" now respects ENABLE_* settings (only starts enabled services)
- `moav stop` now uses `docker compose stop` instead of `down` (preserves container state)
- Certbot exits gracefully when no domain configured (domain-less mode)

### Fixed
- WireGuard "Permission denied" error on Docker 29 with Alpine
- WireGuard config parsing stripping trailing "=" from base64 keys
- WireGuard QR code showing "Invalid QR Code" in app due to non-hex IPv6 address (`fd00:moav:wg::` → `fd00:cafe:beef::`)
- WireGuard-wstunnel QR code not being generated in wg-user-add.sh (missing in README.html)
- Conduit status showing "never" even when running ([#7](https://github.com/shayanb/MoaV/issues/7))
- Reality URL `&` characters replaced with placeholder in README.html ([#8](https://github.com/shayanb/MoaV/issues/8))
- Architecture mismatch in Dockerfile.client - now uses TARGETARCH for multi-arch support ([#4](https://github.com/shayanb/MoaV/issues/4))
- Bootstrap failing in domain-less mode (missing ENABLE_* exports, conditional config generation)
- generate-user.sh unconditionally sourcing reality.env (now conditional on ENABLE_REALITY)

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

[Unreleased]: https://github.com/shayanb/MoaV/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/shayanb/MoaV/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/shayanb/MoaV/compare/v1.0.2...v1.1.1
[1.0.2]: https://github.com/shayanb/MoaV/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shayanb/MoaV/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shayanb/MoaV/releases/tag/v1.0.0
