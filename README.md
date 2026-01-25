# MoaV

Multi-protocol censorship circumvention stack optimized for hostile network environments.

## Features

- **Multiple protocols** - Reality (VLESS), Trojan, Hysteria2, WireGuard, DNS tunnel
- **Stealth-first** - All traffic looks like normal HTTPS or DNS
- **Per-user credentials** - Create, revoke, and manage users independently
- **Easy deployment** - Docker Compose based, single command setup
- **Mobile-friendly** - QR codes and links for easy client import
- **Decoy website** - Serves innocent content to unauthenticated visitors
- **[Psiphon Conduit](https://github.com/Psiphon-Inc/conduit)** - Optional bandwidth donation to help others bypass censorship

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
┌─────────────────────────────────────────────────────────────────┐
│                           Internet                               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
     ┌──────────────┬───────────┼───────────┬──────────────┐
     │              │           │           │              │
┌────┴────┐   ┌─────┴─────┐ ┌───┴───┐ ┌─────┴─────┐  ┌─────┴─────┐
│ 443/tcp │   │ 8443/tcp  │ │443/udp│ │  53/udp   │  │  Conduit  │
│ Reality │   │  Trojan   │ │Hyster.│ │   dnstt   │  │ (donate)  │
└────┬────┘   └─────┬─────┘ └───┬───┘ └─────┬─────┘  └───────────┘
     │              │           │           │
     └──────────────┴───────────┼───────────┘
                                │
                         ┌──────┴──────┐
                         │  sing-box   │
                         │  (unified)  │
                         └──────┬──────┘
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
| WireGuard | via wstunnel | ★★★☆☆ | ★★★★★ | Full VPN, system-wide |
| DNS Tunnel | 53/udp | ★★★☆☆ | ★☆☆☆☆ | Last resort |

## User Management

```bash
# Add a new user
./scripts/user-add.sh newuser

# Revoke a user
./scripts/user-revoke.sh username

# List all users
./scripts/user-list.sh
```

User bundles are generated in `outputs/bundles/<username>/` containing:
- Config files for each protocol
- QR codes for mobile import
- README with connection instructions

## Client Apps

| Platform | Recommended Apps |
|----------|-----------------|
| iOS | Shadowrocket, Streisand, Hiddify |
| Android | v2rayNG, NekoBox, Hiddify |
| macOS | V2rayU, NekoRay |
| Windows | v2rayN, NekoRay |

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
- Public IPv4, ports 443 and 53 open
- Domain name

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
