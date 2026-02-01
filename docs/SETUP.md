# MoaV Setup Guide

Complete setup guide for deploying MoaV on a VPS or home server.

## Table of Contents

- [Use Cases](#use-cases)
- [Prerequisites](#prerequisites)
- [Quick Install (Recommended)](#quick-install-recommended)
  - [Manual Installation](#manual-installation)
    - [Using moav.sh](#using-moavsh)
    - [Step 3: Configure Environment](#step-3-configure-environment)
    - [Step 4: Configure DNS](#step-4-configure-dns)
    - [Step 5: Run Bootstrap](#step-5-run-bootstrap)
    - [Step 6: Prepare for DNS Tunnel (Optional)](#step-6-prepare-for-dns-tunnel-optional)
    - [Step 7: Start Services](#step-7-start-services)
    - [Step 8: Verify](#step-8-verify)
  - [Distribute User Bundles](#step-9-distribute-user-bundles)
  
- [Managing Users](#managing-users)
- [Bandwidth Donation Services](#bandwidth-donation-services)
  - [Conduit Stats (Traffic by Country)](#conduit-stats-traffic-by-country)
- [Re-bootstrapping](#re-bootstrapping)
- [Updating](#updating)
- [Server Migration](#server-migration)
- [IPv6 Support](#ipv6-support)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)

---

## Use Cases

MoaV can be deployed in several configurations:

### VPS in a Free Country
The most common setup - deploy on a VPS in a country with unrestricted internet to help users bypass censorship.

**Benefits:**
- Dedicated public IP with all ports open
- High bandwidth and reliability
- Easy DNS setup with your domain
- Can serve multiple users remotely

### Home VPN Server
Run MoaV on a Raspberry Pi or home server to create a personal VPN for yourself and family.

**Benefits:**
- No monthly VPS costs
- Full control over your hardware
- Share with trusted family and friends
- Great for travelers needing access to home network
- Can donate bandwidth via Conduit/Snowflake to help others

**Considerations:**
- Requires port forwarding on your router
- Dynamic IP needs DDNS setup (see [DNS.md](DNS.md#dynamic-dns-for-home-servers))
- Some ISPs use CGNAT which blocks incoming connections
- Lower upload bandwidth than VPS

**Hardware:** Raspberry Pi 4 (2GB+ RAM) or any ARM64/x64 Linux system works great.

### Hybrid Setup
Run a home server for personal use AND a VPS for distributing to users in censored regions.

---

## Prerequisites

- A VPS or home server with:
  - Debian 12, Ubuntu 22.04, or Ubuntu 24.04 (also works on Raspberry Pi OS)
  - **Architecture:** x64 (AMD64) or ARM64 (Raspberry Pi 4, Apple Silicon, etc.)
  - At least 1 vCPU, 1GB RAM, 10GB disk
  - Public IPv4 address (or dynamic IP with DDNS for home servers)
  - Public IPv6 address (optional, see [IPv6 Support](#ipv6-support))
  - Ports 443/tcp, 443/udp, and 53/udp open (port forwarding required for home servers)

- A domain name (see [DNS.md](DNS.md) for configuration)
  - **VPS:** Point domain to your server's static IP
  - **Home server:** Use DDNS service (see [Dynamic DNS for Home Servers](DNS.md#dynamic-dns-for-home-servers))


## Quick Install (Recommended)

The fastest way to get started is the one-liner installer. SSH into your VPS and run:

```bash
curl -fsSL moav.sh/install.sh | bash
```

This will:
1. **Check prerequisites** - Detect your OS and check for Docker, git, qrencode
2. **Install missing packages** - Prompt to install Docker, git, qrencode if missing
3. **Clone MoaV** - Download to `/opt/moav`
4. **Launch setup** - Offer to run the interactive setup wizard

The installer supports:
- **Debian/Ubuntu** - Uses `apt` and official Docker install script
- **RHEL/Fedora/CentOS** - Uses `dnf`/`yum` and official Docker install script
- **Alpine** - Uses `apk`

After installation, configure your environment and run the setup:

```bash
cd /opt/moav
cp .env.example .env
nano .env                    # Set DOMAIN, ACME_EMAIL, ADMIN_PASSWORD
./moav.sh                    # Run interactive setup
```

**Skip to [Step 3: Configure Environment](#step-3-configure-environment)** if you used the quick installer.

---

## Manual Installation

If you prefer manual installation or the quick installer doesn't work for your environment, follow these steps.

### Step 1: Initial Server Setup

SSH into your fresh VPS:

```bash
ssh root@YOUR_SERVER_IP
```

Update the system and install Docker:

```bash
# Update system
apt update && apt upgrade -y

# Install Docker (includes Docker Compose plugin)
curl -fsSL https://get.docker.com | sh

# Add your user to docker group (optional, avoids needing sudo)
usermod -aG docker $USER

# Install qrencode for QR code generation
apt install -y qrencode

# Verify installation
docker --version
docker compose version
```

### Step 2: Clone MoaV

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

## Using moav.sh

After installation (quick or manual), MoaV provides an interactive management script:

```bash
cd /opt/moav
./moav.sh              # Interactive menu (guides you through setup)
./moav.sh install      # Install 'moav' command globally
```

Once installed globally, run `moav` from anywhere:

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
moav user package joe           # Create distributable zip
moav build                      # Build all containers
moav export                     # Export full backup
moav import backup.tar.gz      # Import from backup
moav migrate-ip 1.2.3.4        # Update to new IP
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

# Your server's public IPv6 (optional, auto-detected if available)
# Set to "disabled" to explicitly disable IPv6 support
SERVER_IPV6=
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

## Server Migration

MoaV includes built-in tools for exporting your entire configuration and migrating to a new server.

### Export Configuration

Create a full backup of your MoaV installation:

```bash
# Export to timestamped file
moav export

# Or specify a filename
moav export mybackup.tar.gz
```

The backup includes:
- `.env` file (configuration)
- All cryptographic keys (Reality, WireGuard, dnstt)
- User credentials and configs
- Generated user bundles

**Security Note:** The backup contains private keys. Transfer securely and delete after import.

### Import Configuration

On a new server, after installing MoaV:

```bash
# Copy backup to new server
scp moav-backup-*.tar.gz user@new-server:/opt/moav/

# On new server
cd /opt/moav
moav import moav-backup-*.tar.gz
```

### Migrate IP Address

When moving to a new server with a different IP:

```bash
# Update SERVER_IP and regenerate all user configs
moav migrate-ip NEW_IP_ADDRESS

# Example
moav migrate-ip 203.0.113.50
```

This automatically:
1. Updates `SERVER_IP` in `.env`
2. Updates all user bundle configs (Reality, Trojan, Hysteria2, WireGuard)
3. Regenerates QR codes (if qrencode is installed)

### Full Migration Workflow

```bash
# === ON OLD SERVER ===
cd /opt/moav
moav export
# Creates: moav-backup-YYYYMMDD_HHMMSS.tar.gz

# Transfer to new server
scp moav-backup-*.tar.gz root@NEW_SERVER:/opt/moav/

# === ON NEW SERVER ===
# 1. Install MoaV first (Step 1-2 from this guide)
cd /opt/moav

# 2. Import configuration
moav import moav-backup-*.tar.gz

# 3. Update to new IP (if IP changed)
moav migrate-ip $(curl -s https://api.ipify.org)

# 4. Update DNS records to point to new server IP
# (See DNS.md)

# 5. Start services
moav start

# 6. Distribute updated configs to users
moav user package user1
moav user package user2
# ... or regenerate all:
for user in outputs/bundles/*/; do
    username=$(basename "$user")
    [[ "$username" != *-configs ]] && moav user package "$username"
done
```

### Interactive Migration Menu

You can also use the interactive menu:

```bash
moav
# Select: 8) Export/Import (migration)
```

This provides guided options for:
- Export configuration backup
- Import configuration backup
- Migrate to new IP address

## IPv6 Support

MoaV supports IPv6 for all protocols. When enabled, user bundles will include both IPv4 and IPv6 connection options.

### How It Works

- **Auto-detection**: If `SERVER_IPV6` is empty in `.env`, MoaV automatically detects your server's public IPv6
- **Dual-stack configs**: Users receive both IPv4 and IPv6 links/configs in their bundles
- **Optional**: IPv6 is completely optional - everything works with IPv4 only

### Enabling IPv6

1. **Enable on your VPS**: Most providers (DigitalOcean, Hetzner, etc.) require enabling IPv6 in the control panel
2. **Verify connectivity**:
   ```bash
   curl -6 -s https://api6.ipify.org
   # Should return your public IPv6 address (e.g., 2400:xxxx:xxxx::xxxx)
   ```
3. **Regenerate user bundles** (if you enabled IPv6 after initial setup):
   ```bash
   moav regenerate-users
   ```

### Disabling IPv6

To explicitly disable IPv6 even if your server has it:

```bash
# In .env
SERVER_IPV6=disabled
```

### Is IPv6 Important for Censorship Bypass?

**Short answer: No, it's a "nice to have" but not critical.**

**When IPv6 might help:**
- Some censors focus blocking efforts on IPv4 and have weaker IPv6 filtering
- Provides a fallback if IPv4 gets specifically targeted

**Why it's usually not critical:**
- Most heavily censored countries (Iran, China, Russia) have low IPv6 adoption among end users
- Many mobile networks and home ISPs in these regions don't support IPv6
- Sophisticated censors that can block Reality/Trojan will likely block both IP versions
- The **protocol matters more** than the IP version - Reality's camouflage defeats detection, not IPv4 vs IPv6

**Recommendation:** Don't worry about IPv6 unless you have users specifically reporting that IPv4 is blocked but IPv6 works (which is rare).

### Checking IPv6 Status

```bash
# Check if server has public IPv6
ip -6 addr show scope global

# Test IPv6 connectivity
curl -6 -s https://api6.ipify.org

# Check what's configured in MoaV
grep SERVER_IPV6 /opt/moav/.env
```

**Note:** Link-local addresses (`fe80::`) don't count - you need a global IPv6 address for internet connectivity.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Security Notes

See [OPSEC.md](OPSEC.md)
