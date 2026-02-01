# One-Click VPS Deployment

Deploy MoaV on your favorite VPS provider in minutes. Each provider offers a slightly different process, but they all support cloud-init for automatic setup.

## How It Works

1. **Click the button** for your preferred provider below
2. **Create a VPS** with the recommended specs (1 vCPU, 1GB RAM minimum)
3. **Paste the cloud-init script** in the "User Data" or "Cloud-Init" field
4. **SSH into your server** after it boots (usually 2-3 minutes)
5. **Run `moav`** to complete the interactive setup

## Cloud-Init Script

Copy this script and paste it into your VPS provider's "User Data" or "Cloud-Init" field when creating the server:

```bash
#!/bin/bash
curl -fsSL https://moav.sh/cloud-init.sh | bash
```

Or use the full URL directly:
```
https://moav.sh/cloud-init.sh
```

---

## Hetzner

Hetzner offers excellent value with servers starting at €3.79/month in European data centers.

### Steps

1. Go to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Click **"Add Server"**
3. Choose:
   - **Location**: Choose closest to your users
   - **Image**: Ubuntu 22.04
   - **Type**: CX22 (2 vCPU, 4GB RAM) recommended, or CX11 (1 vCPU, 2GB) minimum
   - **Networking**: Enable IPv4 and IPv6
4. Expand **"Cloud config"** section
5. Paste the cloud-init script:
   ```bash
   #!/bin/bash
   curl -fsSL https://moav.sh/cloud-init.sh | bash
   ```
6. Add your SSH key
7. Click **"Create & Buy now"**
8. Wait 2-3 minutes, then SSH in: `ssh root@YOUR_IP`
9. You'll be greeted with the MoaV setup wizard

### Recommended Specs
- **Minimum**: CX11 (1 vCPU, 2GB RAM) - €3.79/month
- **Recommended**: CX22 (2 vCPU, 4GB RAM) - €5.39/month

---

## Linode

Linode (now Akamai) offers reliable servers with good global coverage.

### Steps

1. Go to [Linode Cloud Manager](https://cloud.linode.com/)
2. Click **"Create Linode"**
3. Choose:
   - **Image**: Ubuntu 22.04 LTS
   - **Region**: Choose closest to your users
   - **Linode Plan**: Shared CPU - Nanode 1GB ($5/mo) or Linode 2GB ($12/mo)
4. Scroll to **"Add User Data"** (under "Add-ons")
5. Check the box and paste:
   ```bash
   #!/bin/bash
   curl -fsSL https://moav.sh/cloud-init.sh | bash
   ```
6. Set your root password and add SSH key
7. Click **"Create Linode"**
8. Wait 2-3 minutes, then SSH in: `ssh root@YOUR_IP`
9. You'll be greeted with the MoaV setup wizard

### Recommended Specs
- **Minimum**: Nanode 1GB (1 vCPU, 1GB RAM) - $5/month
- **Recommended**: Linode 2GB (1 vCPU, 2GB RAM) - $12/month

---

## Vultr

Vultr offers competitive pricing with many global locations.

### Steps

1. Go to [Vultr Dashboard](https://my.vultr.com/)
2. Click **"Deploy +"** → **"Deploy New Server"**
3. Choose:
   - **Choose Server**: Cloud Compute - Shared CPU
   - **Server Location**: Choose closest to your users
   - **Server Image**: Ubuntu 22.04 LTS x64
   - **Server Size**: 25 GB SSD ($5/mo) minimum
4. Expand **"Add User Data"** (under Additional Features)
5. Paste the cloud-init script:
   ```bash
   #!/bin/bash
   curl -fsSL https://moav.sh/cloud-init.sh | bash
   ```
6. Add your SSH key
7. Click **"Deploy Now"**
8. Wait 2-3 minutes, then SSH in: `ssh root@YOUR_IP`
9. You'll be greeted with the MoaV setup wizard

### Recommended Specs
- **Minimum**: 25 GB SSD (1 vCPU, 1GB RAM) - $5/month
- **Recommended**: 55 GB SSD (1 vCPU, 2GB RAM) - $10/month

---

## DigitalOcean

DigitalOcean is popular and beginner-friendly with excellent documentation.

### Steps

1. Go to [DigitalOcean Dashboard](https://cloud.digitalocean.com/)
2. Click **"Create"** → **"Droplets"**
3. Choose:
   - **Region**: Choose closest to your users
   - **Image**: Ubuntu 22.04 (LTS) x64
   - **Size**: Basic → Regular → $6/mo (1GB RAM) or $12/mo (2GB RAM)
   - **Authentication**: SSH Key (recommended)
4. Expand **"Advanced Options"**
5. Check **"Add User Data"** and paste:
   ```bash
   #!/bin/bash
   curl -fsSL https://moav.sh/cloud-init.sh | bash
   ```
6. Click **"Create Droplet"**
7. Wait 2-3 minutes, then SSH in: `ssh root@YOUR_IP`
8. You'll be greeted with the MoaV setup wizard

### Recommended Specs
- **Minimum**: Basic (1 vCPU, 1GB RAM) - $6/month
- **Recommended**: Basic (1 vCPU, 2GB RAM) - $12/month

---

## After Deployment

Once you SSH into your server, you'll see the MoaV welcome screen:

```
███╗   ███╗ ██████╗  █████╗ ██╗   ██╗
████╗ ████║██╔═══██╗██╔══██╗██║   ██║
██╔████╔██║██║   ██║███████║██║   ██║
██║╚██╔╝██║██║   ██║██╔══██║╚██╗ ██╔╝
██║ ╚═╝ ██║╚██████╔╝██║  ██║ ╚████╔╝
╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝  ╚═══╝

  Welcome to your MoaV Server!
```

The setup wizard will guide you through:
1. Entering your domain name
2. Providing email for TLS certificates
3. Setting admin dashboard password
4. Selecting which protocols to enable
5. Creating initial users

### Prerequisites Before Setup

Before running the setup, make sure:

1. **Domain configured**: Your domain's DNS A record points to your server's IP
2. **Ports open**: Most VPS providers have all ports open by default, but verify:
   - 443/tcp (Reality, Hysteria2)
   - 8443/tcp (Trojan)
   - 51820/udp (WireGuard)
   - 80/tcp (Let's Encrypt verification)

---

## Troubleshooting

### Cloud-init didn't run

Check the log:
```bash
cat /var/log/moav-cloud-init.log
```

If MoaV wasn't installed, run manually:
```bash
curl -fsSL moav.sh/install.sh | bash
```

### Docker not running

```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### DNS not propagated yet

Wait a few minutes and verify:
```bash
dig +short yourdomain.com
```

Should return your server's IP address.

---

## Alternative: Manual Installation

If you prefer not to use cloud-init, you can always SSH into any fresh Ubuntu server and run:

```bash
curl -fsSL moav.sh/install.sh | bash
```

See [SETUP.md](SETUP.md) for detailed manual installation instructions.
