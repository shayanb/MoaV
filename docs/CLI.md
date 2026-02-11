# MoaV CLI Reference

Complete reference for the `moav` command-line interface.

## Table of Contents

- [Installation](#installation)
- [Quick Reference](#quick-reference)
- [Commands](#commands)
  - [General](#general)
  - [Setup & Configuration](#setup--configuration)
  - [Service Management](#service-management)
  - [User Management](#user-management)
  - [Testing & Client](#testing--client)
  - [Migration](#migration)
- [Profiles](#profiles)
- [Service Names & Aliases](#service-names--aliases)
- [Environment Variables](#environment-variables)
- [Examples](#examples)

---

## Installation

```bash
# Install moav command globally (run from /opt/moav)
./moav.sh install

# Or using the script directly
./moav.sh [command]

# Uninstall global command
moav uninstall
```

After installation, `moav` is available from any directory.

---

## Quick Reference

```bash
moav                      # Interactive menu
moav help                 # Show help
moav start                # Start all services
moav stop                 # Stop all services
moav status               # Show service status
moav logs                 # View logs (follow mode)
moav user add NAME        # Add new user
moav user add --batch 5   # Batch create 5 users
moav user revoke NAME     # Revoke user
moav test USERNAME        # Test connectivity
```

---

## Commands

### General

#### `moav` (no command)
Launch the interactive menu for guided setup and management.

```bash
moav
```

#### `moav help`
Display help message with all available commands.

```bash
moav help
moav --help
moav -h
```

#### `moav version`
Show MoaV version.

```bash
moav version
moav --version
```

#### `moav install`
Install `moav` command globally to `/usr/local/bin`.

```bash
./moav.sh install
```

#### `moav uninstall`
Remove MoaV containers and global command.

```bash
moav uninstall           # Remove containers, keep data (.env, keys, bundles)
moav uninstall --wipe    # Remove EVERYTHING (fresh install ready)
```

**Without `--wipe` (default):**
- Stops and removes all Docker containers
- Removes the global `moav` command
- Preserves: `.env`, keys, certificates, user bundles, Docker volumes

**With `--wipe`:**
- Removes all Docker containers AND volumes
- Removes `.env` and all generated configs
- Removes all keys and certificates
- Removes all user bundles
- Removes the global `moav` command

After `--wipe`, run `cp .env.example .env` and `./moav.sh` for a fresh setup.

---

### Setup & Configuration

#### `moav check`
Run prerequisites check (Docker, dependencies, ports).

```bash
moav check
```

#### `moav bootstrap`
Run first-time setup. Generates keys, obtains TLS certificates, creates initial users.

```bash
moav bootstrap
```

This command:
1. Checks prerequisites
2. Prompts for domain, email, admin password (if not in .env)
3. Generates Reality and dnstt keypairs
4. Obtains Let's Encrypt certificate
5. Creates initial users
6. Generates user bundles

#### `moav domainless`
Enable domain-less mode for servers without a domain.

```bash
moav domainless
```

Available services in domain-less mode:
- WireGuard (direct + wstunnel)
- Admin dashboard (self-signed certificate)
- Conduit (Psiphon bandwidth donation)
- Snowflake (Tor bandwidth donation)

#### `moav profiles`
Interactively change default services for `moav start`.

```bash
moav profiles
```

Saves selection to `DEFAULT_PROFILES` in `.env`.

#### `moav update`
Update MoaV from git repository.

```bash
moav update              # Update from current branch
moav update -b dev       # Switch to dev branch and update
moav update -b main      # Switch back to main branch
```

**Options:**
- `-b BRANCH` - Switch to specified branch before updating

If local changes are detected, you'll be prompted to stash or discard them.

#### `moav setup-dns`
Free port 53 for dnstt by disabling systemd-resolved.

```bash
moav setup-dns
```

This command:
1. Stops systemd-resolved
2. Disables it from starting on boot
3. Configures /etc/resolv.conf with public DNS servers

---

### Service Management

#### `moav start`
Start services.

```bash
moav start                    # Start DEFAULT_PROFILES from .env
moav start all                # Start all services
moav start proxy              # Start proxy profile only
moav start proxy admin        # Start multiple profiles
moav start proxy wireguard admin  # Start three profiles
```

**Arguments:**
- No arguments: Uses `DEFAULT_PROFILES` from `.env`
- Profile names: Start specific profiles (space-separated)

#### `moav stop`
Stop services.

```bash
moav stop                     # Stop all running services
moav stop sing-box            # Stop specific service
moav stop conduit snowflake   # Stop multiple services
moav stop -r                  # Stop and remove containers
moav stop sing-box -r         # Stop specific service and remove container
```

**Options:**
- `-r` - Remove containers after stopping (not just stop)

#### `moav restart`
Restart services.

```bash
moav restart                  # Restart all running services
moav restart sing-box         # Restart specific service
moav restart sing-box admin   # Restart multiple services
```

#### `moav status`
Show status of all services.

```bash
moav status
```

Displays:
- Container status (running/stopped)
- Health status
- Port mappings
- Uptime

#### `moav logs`
View service logs.

```bash
moav logs                     # All logs, follow mode (Ctrl+C to exit)
moav logs sing-box            # Specific service logs
moav logs sing-box conduit    # Multiple services
moav logs -n                  # Last 100 lines, no follow
moav logs sing-box -n         # Specific service, no follow
moav logs -f conduit          # Explicit follow mode
```

**Options:**
- `-n`, `--no-follow` - Show last 100 lines without following
- `-f`, `--follow` - Follow mode (default)

#### `moav build`
Build Docker images.

```bash
moav build                    # Build all images
moav build sing-box           # Build specific image
moav build conduit snowflake  # Build multiple images
```

---

### User Management

#### `moav users`
List all users.

```bash
moav users
moav user list    # Same as above
```

#### `moav user add`
Add one or more users to all services.

```bash
# Single user
moav user add john            # Add user 'john'
moav user add john --package  # Add user and create zip bundle
moav user add john -p         # Short form

# Multiple users
moav user add alice bob charlie           # Add three users
moav user add alice bob charlie -p        # Add three users with zip packages

# Batch mode (auto-numbered)
moav user add --batch 5                   # Create user01, user02, ..., user05
moav user add --batch 10 --prefix team    # Create team01, team02, ..., team10
moav user add --batch 5 --prefix dev -p   # Create dev01..dev05 with packages
```

**Options:**
- `--package`, `-p` - Create distributable zip file with HTML guide
- `--batch N`, `-b N` - Create N users with auto-generated names
- `--prefix NAME` - Prefix for batch usernames (default: "user")

**Batch mode features:**
- Smart numbering: if user01-user03 exist, `--batch 2` creates user04, user05
- Services reload once at the end (not after each user)
- Shows progress for each user and summary at the end

Creates bundle in `outputs/bundles/USERNAME/` containing:
- Config files for all protocols
- QR codes for mobile import
- README.html with instructions

#### `moav user revoke`
Revoke a user from all services.

```bash
moav user revoke john         # Revoke user 'john'
```

Removes user from:
- sing-box config (Reality, Trojan, Hysteria2, CDN)
- WireGuard config
- TrustTunnel credentials
- Deletes user bundle

#### `moav user package`
Create distributable zip for an existing user.

```bash
moav user package john        # Creates outputs/bundles/john.zip
```

---

### Testing & Client

#### `moav test`
Test connectivity for a user across all protocols.

```bash
moav test john                # Test all protocols
moav test john --json         # Output results as JSON
moav test john -v             # Verbose output for debugging
moav test john --verbose      # Same as above
```

**Options:**
- `--json` - Output results in JSON format
- `-v`, `--verbose` - Show detailed debug output

Tests: Reality, Trojan, Hysteria2, TrustTunnel, WireGuard, dnstt

**Sample output:**
```
═══════════════════════════════════════════════════════════════
  MoaV Connection Test Results
═══════════════════════════════════════════════════════════════

  Config: /bundles/john
  Time:   Wed Jan 28 10:30:00 UTC 2026

───────────────────────────────────────────────────────────────
  ✓ reality      Connected via VLESS/Reality
  ✓ trojan       Connected via Trojan
  ✓ hysteria2    Connected via Hysteria2
  ✓ wireguard    Config valid, endpoint reachable
  ○ dnstt        No dnstt config found in bundle

═══════════════════════════════════════════════════════════════
```

#### `moav client`
Client mode commands.

```bash
moav client                   # Show client help
moav client build             # Build client Docker image
moav client test john         # Same as 'moav test john'
moav client connect john      # Connect as user (exposes proxy)
```

#### `moav client connect`
Connect through your MoaV server and expose local proxy.

```bash
moav client connect john                    # Auto-detect best protocol
moav client connect john --protocol reality # Use specific protocol
moav client connect john -p hysteria2       # Short form
```

**Options:**
- `--protocol`, `-p` - Specify protocol (default: auto)

**Protocols:** `auto`, `reality`, `trojan`, `hysteria2`, `wireguard`, `tor`, `dnstt`

**Proxy endpoints (configurable in .env):**
- SOCKS5: `localhost:10800` (CLIENT_SOCKS_PORT)
- HTTP: `localhost:18080` (CLIENT_HTTP_PORT)

#### `moav client build`
Build the client Docker image.

```bash
moav client build
```

---

### Migration

#### `moav export`
Export full configuration backup.

```bash
moav export                   # Creates moav-backup-TIMESTAMP.tar.gz
moav export mybackup.tar.gz   # Custom filename
```

**Backup includes:**
- `.env` configuration
- All cryptographic keys (Reality, WireGuard, dnstt)
- User credentials
- Generated user bundles
- TLS certificates

**Security:** Backup contains private keys. Transfer securely and delete after import.

#### `moav import`
Import configuration from backup.

```bash
moav import moav-backup-20240128.tar.gz
moav import /path/to/backup.tar.gz
```

Restores:
- `.env` file
- Keys and certificates
- User credentials
- User bundles

#### `moav migrate-ip`
Update SERVER_IP and regenerate all user configs.

```bash
moav migrate-ip 203.0.113.50              # Set new IP
moav migrate-ip $(curl -s api.ipify.org)  # Auto-detect current IP
```

This command:
1. Updates `SERVER_IP` in `.env`
2. Regenerates all user bundle configs
3. Updates QR codes (if qrencode installed)

#### `moav regenerate-users`
Regenerate all user bundles with current .env settings.

```bash
moav regenerate-users
```

Use this after:
- Changing domain
- Enabling/disabling protocols
- Adding CDN_DOMAIN
- Changing any configuration that affects client configs

---

## Profiles

Profiles group related services together.

| Profile | Services Included |
|---------|-------------------|
| `proxy` | sing-box, decoy, certbot |
| `wireguard` | wireguard, wstunnel |
| `dnstt` | dnstt |
| `trusttunnel` | trusttunnel |
| `admin` | admin |
| `conduit` | psiphon-conduit |
| `snowflake` | snowflake |
| `client` | client (for testing) |
| `all` | All of the above |

**Usage:**
```bash
moav start proxy admin        # Start proxy and admin profiles
moav start all                # Start everything
```

---

## Service Names & Aliases

| Service | Aliases |
|---------|---------|
| sing-box | `proxy`, `singbox`, `reality` |
| wireguard | `wg` |
| dnstt | `dns` |
| psiphon-conduit | `conduit` |

**Usage:**
```bash
moav logs singbox             # Same as 'moav logs sing-box'
moav restart wg               # Same as 'moav restart wireguard'
moav stop conduit             # Same as 'moav stop psiphon-conduit'
```

---

## Environment Variables

Key variables in `.env` that affect CLI behavior:

| Variable | Description | Default |
|----------|-------------|---------|
| `DEFAULT_PROFILES` | Profiles started by `moav start` | `proxy admin` |
| `CLIENT_SOCKS_PORT` | SOCKS5 port for client mode | `10800` |
| `CLIENT_HTTP_PORT` | HTTP port for client mode | `18080` |
| `INITIAL_USERS` | Users created during bootstrap | `5` |

---

## Examples

### Complete Setup Flow

```bash
# 1. Install MoaV
curl -fsSL moav.sh/install.sh | bash

# 2. Configure environment
cd /opt/moav
cp .env.example .env
nano .env    # Set DOMAIN, ACME_EMAIL, ADMIN_PASSWORD

# 3. Run bootstrap
moav bootstrap

# 4. Start services
moav start

# 5. Add a user
moav user add john --package

# 6. Download bundle
# Visit https://your-server:9443 or use SCP
```

### Daily Operations

```bash
# Check status
moav status

# View logs
moav logs sing-box

# Add new user
moav user add alice

# Add multiple users at once
moav user add alice bob charlie

# Batch create users (auto-numbered)
moav user add --batch 10 --prefix team --package

# Test user connectivity
moav test alice

# Update MoaV
moav update
```

### Server Migration

```bash
# On old server
moav export

# Copy backup to new server
scp moav-backup-*.tar.gz root@new-server:/opt/moav/

# On new server
cd /opt/moav
moav import moav-backup-*.tar.gz
moav migrate-ip $(curl -s api.ipify.org)
moav start
```

### Testing Development Branch

```bash
# Switch to dev branch
moav update -b dev

# Test changes
moav restart

# Return to stable
moav update -b main
```

### Domain-less Quick Setup

```bash
# For servers without a domain
moav domainless
moav start wireguard admin conduit
moav user add john
```
