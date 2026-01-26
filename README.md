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

# Build all images
docker compose --profile all build

# Initialize (generates keys, users, obtains TLS cert)
docker compose --profile setup run --rm bootstrap

# Start all services
docker compose --profile all up -d

# Or start just the proxy services (Reality, Trojan, Hysteria2)
docker compose --profile proxy up -d
```

See [docs/SETUP.md](docs/SETUP.md) for complete setup instructions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                    Internet                                       │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
  ┌──────────┬──────────┬───────────────┼───────────────┬──────────┬──────────────┐
  │          │          │               │               │          │              │
┌─┴──┐  ┌────┴────┐ ┌───┴───┐ ┌────┐ ┌──┴──┐ ┌────┐ ┌───┴───┐ ┌────┴────┐ ┌───────┴───────┐
│443 │  │  8443   │ │  443  │ │5182│ │8080 │ │ 53 │ │Conduit│ │Snowflake│ │   Your VPN    │
│tcp │  │   tcp   │ │  udp  │ │udp │ │ tcp │ │udp │ │Psiphon│ │   Tor   │ │   Clients     │
│Real│  │ Trojan  │ │Hyster.│ │ WG │ │wstun│ │dnst│ │donate │ │ donate  │ │               │
└─┬──┘  └────┬────┘ └───┬───┘ └──┬─┘ └──┬──┘ └─┬──┘ └───────┘ └─────────┘ └───────────────┘
  │          │          │        │      │      │
  └──────────┴──────────┼────────┴──────┘      │
                        │                      │
                 ┌──────┴──────┐        ┌──────┴──────┐
                 │  sing-box   │        │    dnstt    │
                 └──────┬──────┘        └──────┬──────┘
                        │                      │
                        └──────────┬───────────┘
                                   │
                            ┌──────┴──────┐
                            │   Direct    │
                            │   Egress    │
                            └─────────────┘
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

## User Management

```bash
# Add a user to ALL services
./scripts/user-add.sh newuser

# Add to specific services only
./scripts/singbox-user-add.sh newuser  # Reality, Trojan, Hysteria2
./scripts/wg-user-add.sh newuser       # WireGuard only

# Revoke a user from ALL services
./scripts/user-revoke.sh username

# Revoke from specific services only
./scripts/singbox-user-revoke.sh username
./scripts/wg-user-revoke.sh username

# List all users
./scripts/user-list.sh
```

User bundles are generated in `outputs/bundles/<username>/` containing:
- Config files for each protocol
- QR codes for mobile import
- README with connection instructions

## Conduit Management

If running Psiphon Conduit to donate bandwidth:

```bash
# View live traffic stats by country
./scripts/conduit-stats.sh

# Get Ryve deep link for mobile import
./scripts/conduit-info.sh
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

This software is provided for legitimate use cases such as protecting privacy and accessing information. Users are responsible for ensuring their use complies with applicable laws.
