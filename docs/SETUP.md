# MoaV Setup Guide

Complete setup guide for deploying MoaV on a fresh VPS.

## Prerequisites

- A VPS with:
  - Debian 12, Ubuntu 22.04, or Ubuntu 24.04
  - At least 1 vCPU, 1GB RAM, 10GB disk
  - Public IPv4 address
  - Ports 443/tcp, 443/udp, and 53/udp open

- A domain name (see [DNS.md](DNS.md) for configuration)

## Recommended VPS Providers

For users in middle east, these providers/regions typically work well:

| Provider | Region | Notes |
|----------|--------|-------|
| Hetzner | Germany (Falkenstein, Nuremberg) | Good price/performance |
| Hetzner | Finland (Helsinki) | Less blocked |
| DigitalOcean | Frankfurt | Reliable |
| DigitalOcean | Amsterdam | Alternative |
| Vultr | Frankfurt | Good alternative |

**Avoid:** US regions (high latency, more scrutinized)

## Step 1: Initial Server Setup

SSH into your fresh VPS:

```bash
ssh root@YOUR_SERVER_IP
```

Update the system and install Docker:

```bash
# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Docker Compose plugin
apt install -y docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

## Step 2: Clone MoaV

```bash
# Clone the repository
git clone https://github.com/shayanb/MoaV.git /opt/moav
cd /opt/moav
```

Or download and extract:

```bash
mkdir -p /opt/moav
cd /opt/moav
# Upload or download your MoaV files here
```

## Easy Mode: Using moav.sh

MoaV includes a management script that can be used interactively or with commands:

```bash
./moav.sh              # Interactive menu (guides you through setup)
./moav.sh install      # Install 'moav' command globally
```

After installing, you can run `moav` from anywhere:

```bash
moav                            # Interactive menu
moav help                       # Show all available commands
moav check                      # Check prerequisites
moav bootstrap                  # Run first-time setup
moav start                      # Start all services
moav start proxy admin          # Start specific profiles
moav stop                       # Stop all services
moav stop conduit               # Stop specific service
moav restart sing-box           # Restart specific service
moav status                     # Show service status
moav logs                       # View all logs
moav logs sing-box conduit      # View specific service logs
moav users                      # List users
moav user add joe               # Add user
moav user revoke joe            # Revoke user
moav build                      # Build all containers
moav uninstall                  # Remove global command
```

If you prefer manual setup, continue with the steps below.

## Step 3: Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit with your settings
nano .env
```

**Required settings to change:**

```bash
# Your domain (must be configured first - see DNS.md)
DOMAIN=your-domain.com

# Email for Let's Encrypt
ACME_EMAIL=your-email@example.com

# Admin password (change this!)
ADMIN_PASSWORD=your-secure-password-here

# Your server's public IP (optional, auto-detected)
SERVER_IP=YOUR_SERVER_IP
```

**Optional settings:**

```bash
# Reality target - a popular site to impersonate
# Good choices: www.microsoft.com, www.apple.com, dl.google.com
REALITY_TARGET=www.microsoft.com:443

# Number of initial users to create
INITIAL_USERS=5

# Enable/disable services
ENABLE_REALITY=true
ENABLE_TROJAN=true
ENABLE_HYSTERIA2=true
ENABLE_WIREGUARD=true
ENABLE_DNSTT=true
ENABLE_PSIPHON_CONDUIT=false
ENABLE_ADMIN_UI=true
```

## Step 4: Configure DNS

Before proceeding, you must configure DNS records. See [DNS.md](DNS.md) for detailed instructions.

**Minimum required:**
- `A` record: `your-domain.com` → `YOUR_SERVER_IP`

**For DNS tunnel (optional but recommended):**
- `A` record: `dns.your-domain.com` → `YOUR_SERVER_IP`
- `NS` record: `t.your-domain.com` → `dns.your-domain.com`

## Step 5: Run Bootstrap

Initialize the stack (generates keys, creates users, obtains TLS certificate):

```bash
# Run bootstrap
docker compose --profile setup run --rm bootstrap
```

This will:
1. Generate Reality keypair
2. Generate dnstt keypair
3. Obtain TLS certificate from Let's Encrypt
4. Create initial users
5. Generate user bundles in `outputs/bundles/`

**Note:** If certificate acquisition fails, ensure:
- DNS is properly configured (A record pointing to this server)
- Port 80 is temporarily open (for HTTP-01 challenge)
- Domain propagation is complete (`dig your-domain.com`)

## Step 6: Prepare for DNS Tunnel (Optional)

If you want to use the DNS tunnel (dnstt), you need to free port 53:

```bash
# Stop and disable systemd-resolved (uses port 53)
systemctl stop systemd-resolved
systemctl disable systemd-resolved

# Set up direct DNS resolution
echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
```

## Step 7: Start Services

**Easy way:**
```bash
moav start              # Start all services
moav start proxy admin  # Or specific profiles
```

**Manual way:**
```bash
# Start all services (recommended)
docker compose --profile all up -d

# Or start just the proxy services (Reality, Trojan, Hysteria2)
docker compose --profile proxy up -d

# Or combine specific profiles
docker compose --profile proxy --profile admin up -d          # Proxy + admin dashboard
docker compose --profile proxy --profile wireguard up -d      # Proxy + WireGuard VPN
docker compose --profile proxy --profile dnstt up -d          # Proxy + DNS tunnel
docker compose --profile proxy --profile conduit up -d        # Proxy + Psiphon Conduit

# Available profiles:
#   setup     - Bootstrap/initialization (run once)
#   proxy     - sing-box + decoy (main proxy services)
#   wireguard - WireGuard VPN via wstunnel
#   dnstt     - DNS tunnel (last resort)
#   admin     - Stats dashboard (accessible at https://domain:9443)
#   conduit   - Psiphon bandwidth donation (includes traffic stats by country)
#   snowflake - Tor Snowflake proxy (bandwidth donation for Tor users)
#   all       - Everything

# Note: certbot runs automatically with any profile to manage TLS certificates
```

**Open required firewall ports:**
```bash
# For proxy services
ufw allow 443/tcp    # Reality + Trojan fallback
ufw allow 443/udp    # Hysteria2
ufw allow 53/udp     # DNS tunnel (if using dnstt)

# For admin dashboard
ufw allow 9443/tcp   # Admin (or your PORT_ADMIN value)
```

## Step 8: Verify

Check that services are running:

```bash
docker compose ps
```

All services should show "Up" or "Up (healthy)".

**Note:** Normal browsers visiting `https://your-domain.com` will get an empty response or connection error. This is expected! Port 443 runs the Reality protocol which impersonates microsoft.com - only clients with the correct config can connect.

To verify the server is working:
```bash
# Check sing-box is healthy
docker compose logs sing-box | tail -20

# Test from a client device with the Reality config
# If it connects and you can browse, it's working!
```

The Trojan fallback (port 8443) serves the decoy "Under Construction" page for invalid auth attempts.

## Step 9: Distribute User Bundles

User bundles are in `outputs/bundles/`:

```bash
ls outputs/bundles/
# user01/ user02/ user03/ user04/ user05/
```

Each bundle contains:
- `README.md` - User instructions
- `reality.txt` - Reality protocol link (primary)
- `reality-qr.png` - QR code for mobile import
- `trojan.txt` - Trojan link (backup)
- `hysteria2.yaml` - Hysteria2 config
- `wireguard.conf` - WireGuard config
- `dnstt-instructions.txt` - DNS tunnel instructions

**Distribute these securely** (encrypted message, in-person, etc.)

## Managing Users

**Easy way:**
```bash
moav users              # List all users
moav user add newuser   # Add a user
moav user revoke user   # Revoke a user
```

**Manual scripts:**

### Add a new user to all services

```bash
./scripts/user-add.sh newusername
```

This adds the user to sing-box (Reality, Trojan, Hysteria2) and WireGuard, generates all config files, QR codes, and displays the WireGuard QR in the terminal.

### Add to specific services only

```bash
# Add only to sing-box (Reality, Trojan, Hysteria2)
./scripts/singbox-user-add.sh newusername

# Add only to WireGuard
./scripts/wg-user-add.sh newusername
```

### Revoke a user

```bash
# Revoke from all services
./scripts/user-revoke.sh username

# Revoke from specific services
./scripts/singbox-user-revoke.sh username
./scripts/wg-user-revoke.sh username

# Keep the bundle folder when revoking
./scripts/user-revoke.sh username --keep-bundle
```

### List all users

```bash
./scripts/user-list.sh
```

## Bandwidth Donation Services

MoaV includes two optional bandwidth donation services that help users in censored regions:

### Psiphon Conduit

Donates bandwidth to the Psiphon network to help users bypass censorship.

```bash
# Start Conduit
docker compose --profile conduit up -d

# View live traffic stats by country
./scripts/conduit-stats.sh

# Get Ryve deep link for mobile import
./scripts/conduit-info.sh
```

Configure in `.env`:
```bash
CONDUIT_BANDWIDTH=200    # Mbps limit
CONDUIT_MAX_CLIENTS=100  # Max concurrent clients
```

### Tor Snowflake

Donates bandwidth to the Tor network as a Snowflake proxy, helping Tor users bypass censorship.

```bash
# Start Snowflake
docker compose --profile snowflake up -d

# View logs
docker compose logs -f snowflake
```

Configure in `.env`:
```bash
SNOWFLAKE_BANDWIDTH=50   # Mbps limit
SNOWFLAKE_CAPACITY=20    # Max concurrent clients
```

**Note:** Both services can run simultaneously without conflicts.

## Conduit Stats (Traffic by Country)

If you're running Psiphon Conduit to donate bandwidth, you can view live traffic statistics:

### Terminal Viewer

```bash
# Live terminal stats showing traffic by country
./scripts/conduit-stats.sh
```

This shows:
- Traffic FROM (peers connecting to you) - by country
- Traffic TO (data sent to peers) - by country
- Real-time updates every 15 seconds

### Admin Dashboard

The admin dashboard (https://your-domain:9443) also shows conduit traffic breakdown by country when conduit is running.

### Get Ryve Deep Link

To import your conduit into the Ryve app:

```bash
./scripts/conduit-info.sh
# Or with custom name:
./scripts/conduit-info.sh "My Conduit Name"
```

## Re-bootstrapping

If you need to regenerate all keys and configs (e.g., after changing domain):

```bash
# Remove the bootstrap flag
docker run --rm -v moav_moav_state:/state alpine rm /state/.bootstrapped

# Rebuild all images (if code changed)
docker compose --profile all build --no-cache

# Re-run bootstrap
docker compose --profile setup run --rm bootstrap

# Restart services
docker compose --profile all down
docker compose --profile all up -d
```

## Updating

```bash
cd /opt/moav
git pull

# Build all images (--profile all includes all services)
docker compose --profile all build --no-cache

docker compose --profile all down
docker compose --profile all up -d
```

**Note:** Use `--profile all` to build/run everything, or specify individual profiles like `--profile proxy --profile admin`.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Security Notes

See [OPSEC.md](OPSEC.md)
