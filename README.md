# MoaV

Multi-protocol censorship circumvention stack optimized for hostile network environments.

## Features

- **Multiple protocols** - Reality (VLESS), Trojan, Hysteria2, WireGuard (direct & wstunnel), DNS tunnel
- **Stealth-first** - All traffic looks like normal HTTPS, WebSocket, or DNS
- **Per-user credentials** - Create, revoke, and manage users independently
- **Easy deployment** - Docker Compose based, single command setup
- **Mobile-friendly** - QR codes and links for easy client import
- **Decoy website** - Serves innocent content to unauthenticated visitors
- **[Psiphon Conduit](https://github.com/Psiphon-Inc/conduit)** - Optional bandwidth donation to help others bypass censorship
- **[Tor Snowflake](https://snowflake.torproject.org/)** - Optional bandwidth donation to help Tor users bypass censorship

## Quick Start

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/MoaV.git
cd MoaV

# Configure
cp .env.example .env
nano .env  # Set DOMAIN, ACME_EMAIL, ADMIN_PASSWORD

# Run interactive setup
./moav.sh
```

On first run, `moav.sh` will:
- Check prerequisites (Docker, Docker Compose)
- Offer to install globally (`moav` command)
- Guide you through bootstrap (keys, TLS cert, users)
- Show the main menu

**After installation, use `moav` from anywhere:**

```bash
moav                      # Interactive menu
moav help                 # Show all commands
moav start                # Start all services
moav stop                 # Stop all services
moav logs                 # View logs
moav user add joe         # Add user
```

**Manual docker commands** (alternative):

```bash
docker compose --profile all build                 # Build all images
docker compose --profile setup run --rm bootstrap  # Initialize
docker compose --profile all up -d                 # Start all services
```

See [docs/SETUP.md](docs/SETUP.md) for complete setup instructions.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                Restricted Internet                               │
└──────────────────────────────────────────┬───────────────────────────────────────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
              ▼                            ▼                            ▼
      ┌───────────────┐            ┌───────────────┐            ┌───────────────┐
      │  Your Clients │            │ Psiphon Users │            │   Tor Users   │
      │   (private)   │            │  (worldwide)  │            │  (worldwide)  │
      └───────┬───────┘            └───────┬───────┘            └───────┬───────┘
              │                            │                            │
     ┌────────┼────────┐                   │                            │
     │        │        │                   │                            │
     ▼        ▼        ▼                   ▼                            ▼
┌─────────┐┌─────────┐┌─────────┐   ┌───────────────┐            ┌───────────────┐
│ Reality ││WireGuard││  DNS    │   │               │            │               │
│ 443/tcp ││51820/udp││ 53/udp  │   │    Conduit    │            │   Snowflake   │
│ Trojan  ││wstunnel │├─────────┤   │   (donate)    │            │   (donate)    │
│8443/tcp ││8080/tcp ││  dnstt  │   │   bandwidth   │            │   bandwidth   │
│Hysteria2│└────┬────┘└────┬────┘   └───────┬───────┘            └───────┬───────┘
│ 443/udp │     │          │                │                            │
├─────────┤     │          │                │                            │
│ sing-box├─────┘          │                │                            │
└────┬────┘                │                │                            │
     │                     │                │                            │
     └─────────────────────┼────────────────┼────────────────────────────┘
                           │                │
                           ▼                ▼
                    ┌─────────────────────────────┐
                    │        Open Internet        │
                    └─────────────────────────────┘
```

## Protocols

| Protocol | Port | Stealth | Speed | Use Case |
|----------|------|---------|-------|----------|
| Reality (VLESS) | 443/tcp | ★★★★★ | ★★★★☆ | Primary, most reliable |
| Hysteria2 | 443/udp | ★★★★☆ | ★★★★★ | Fast, works when TCP throttled |
| Trojan | 8443/tcp | ★★★★☆ | ★★★★☆ | Backup, uses your domain |
| WireGuard (Direct) | 51820/udp | ★★★☆☆ | ★★★★★ | Full VPN, simple setup |
| WireGuard (wstunnel) | 8080/tcp | ★★★★☆ | ★★★★☆ | VPN when UDP is blocked |
| DNS Tunnel | 53/udp | ★★★☆☆ | ★☆☆☆☆ | Last resort, hard to block |
| Psiphon | - | ★★★★☆ | ★★★☆☆ | Standalone, no server needed |
| Tor (Snowflake) | - | ★★★★☆ | ★★☆☆☆ | Standalone, uses Tor network |

## User Management

```bash
# Using moav (recommended)
moav user list            # List all users (or: moav users)
moav user add joe         # Add user to all services
moav user revoke joe      # Revoke user from all services
```

**Manual scripts** (for advanced use):

```bash
# Add to specific services only
./scripts/singbox-user-add.sh joe     # Reality, Trojan, Hysteria2
./scripts/wg-user-add.sh joe          # WireGuard only

# Revoke from specific services only
./scripts/singbox-user-revoke.sh joe
./scripts/wg-user-revoke.sh joe
```

User bundles are generated in `outputs/bundles/<username>/` containing:
- Config files for each protocol
- QR codes for mobile import
- README with connection instructions

## Service Management

```bash
moav status               # Show all service status
moav start                # Start all services
moav start proxy admin    # Start specific profiles
moav stop                 # Stop all services
moav stop conduit         # Stop specific service
moav restart sing-box     # Restart specific service
moav logs                 # View all logs (follow mode)
moav logs conduit         # View specific service logs
moav build                # Build/rebuild all containers
```

**Profiles:** `proxy`, `wireguard`, `dnstt`, `admin`, `conduit`, `snowflake`, `all`

**Service aliases:** `conduit`→psiphon-conduit, `singbox`→sing-box, `wg`→wireguard, `dns`→dnstt

## Conduit Management

If running Psiphon Conduit to donate bandwidth:

```bash
moav logs conduit             # View conduit logs
./scripts/conduit-stats.sh    # View live traffic stats by country
./scripts/conduit-info.sh     # Get Ryve deep link for mobile import
```

## Client Apps

| Platform | Recommended Apps |
|----------|------------------|
| iOS | Shadowrocket, Hiddify, WireGuard, Psiphon |
| Android | v2rayNG, Hiddify, WireGuard, Psiphon |
| macOS | NekoRay, WireGuard, Psiphon |
| Windows | v2rayN, NekoRay, WireGuard, Psiphon |

See [docs/CLIENTS.md](docs/CLIENTS.md) for setup instructions.

## Documentation

- [Setup Guide](docs/SETUP.md) - Complete installation instructions
- [DNS Configuration](docs/DNS.md) - DNS records setup
- [Client Setup](docs/CLIENTS.md) - How to connect from devices
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [OpSec Guide](docs/OPSEC.md) - Security best practices

## Requirements

**Server:**
- Debian 12, Ubuntu 22.04/24.04
- 1 vCPU, 1GB RAM minimum
- Public IPv4
- Domain name

**Ports (open as needed):**
- 80/tcp - Certbot (TLS certificate issuance)
- 443/tcp - Reality (VLESS)
- 443/udp - Hysteria2
- 8443/tcp - Trojan
- 51820/udp - WireGuard (direct)
- 8080/tcp - wstunnel (WireGuard over WebSocket)
- 53/udp - DNS tunnel

**Recommended VPS:**
- Hetzner (Germany/Finland)
- DigitalOcean (Frankfurt/Amsterdam)

## Project Structure

```
MoaV/
├── moav.sh                 # CLI management tool (install with: ./moav.sh install)
├── docker-compose.yml      # Main compose file
├── .env.example            # Environment template
├── Dockerfile.*            # Container definitions
├── configs/                # Service configurations
│   ├── sing-box/
│   ├── wireguard/
│   └── dnstt/
├── scripts/                # Management scripts
│   ├── bootstrap.sh
│   ├── user-add.sh
│   ├── user-revoke.sh
│   └── lib/
├── outputs/                # Generated configs (gitignored)
│   └── bundles/
├── web/                    # Decoy website
├── admin/                  # Stats dashboard
└── docs/                   # Documentation
```

## Security

- All protocols require authentication
- Decoy website for unauthenticated traffic
- Per-user credentials with instant revocation
- Minimal logging (no URLs, no content)
- TLS 1.3 everywhere

See [docs/OPSEC.md](docs/OPSEC.md) for security guidelines.

## License

MIT

## Disclaimer

This project provides **general-purpose open-source networking software** only.

It is not a service, not a platform, and not an operated network.

The authors and contributors:
- Do not operate infrastructure
- Do not provide access
- Do not distribute credentials
- Do not manage users
- Do not coordinate deployments

All usage, deployment, and operation are the sole responsibility of third parties.

This software is provided **“AS IS”**, without warranty of any kind.  
The authors and contributors accept **no liability** for any use or misuse of this software.

Users are responsible for complying with all applicable laws and regulations.