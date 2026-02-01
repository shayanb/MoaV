# Changelog

All notable changes to MoaV will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- One-click VPS deployment buttons for Hetzner, Linode, Vultr, DigitalOcean
- Cloud-init script for automated VPS provisioning
- First-login welcome prompt for cloud-deployed servers
- Home VPN server documentation (Raspberry Pi, ARM64 support)
- Dynamic DNS (DDNS) guide for home servers (DuckDNS, Cloudflare)
- VPS deployment guide (docs/DEPLOY.md)
- Bootstrap confirmation prompt before running

### Changed
- WireGuard entrypoint bypasses wg-quick to avoid Docker 29 compatibility issues
- WireGuard peer IP assignment now based on peer count (fixes demouser getting server IP)

### Fixed
- WireGuard "Permission denied" error on Docker 29 with Alpine
- WireGuard config parsing stripping trailing "=" from base64 keys

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

[Unreleased]: https://github.com/shayanb/MoaV/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/shayanb/MoaV/compare/v1.0.2...v1.1.1
[1.0.2]: https://github.com/shayanb/MoaV/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shayanb/MoaV/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shayanb/MoaV/releases/tag/v1.0.0
