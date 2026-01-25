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

For users in Iran, these providers/regions typically work well:

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
git clone https://github.com/YOUR_USERNAME/MoaV.git /opt/moav
cd /opt/moav
```

Or download and extract:

```bash
mkdir -p /opt/moav
cd /opt/moav
# Upload or download your MoaV files here
```

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

## Step 6: Start Services

```bash
# Start main services
docker compose up -d

# If you want WireGuard
docker compose --profile wireguard up -d

# If you want DNS tunnel
docker compose --profile dnstt up -d

# If you want admin dashboard
docker compose --profile admin up -d

# Start everything
docker compose --profile wireguard --profile dnstt --profile admin up -d
```

## Step 7: Verify

Check that services are running:

```bash
docker compose ps
```

Test TLS connection:

```bash
curl -I https://your-domain.com
```

You should see the "Under Construction" page.

## Step 8: Distribute User Bundles

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

### Add a new user

```bash
./scripts/user-add.sh newusername
```

### Revoke a user

```bash
./scripts/user-revoke.sh username
```

### List all users

```bash
./scripts/user-list.sh
```

## Updating

```bash
cd /opt/moav
git pull
docker compose pull
docker compose up -d --build
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Security Notes

See [OPSEC.md](OPSEC.md)
