# DNS Configuration Guide

This guide explains how to configure DNS records for MoaV.

## Table of Contents

- [Overview](#overview)
- [Minimum Setup (Without DNS Tunnel)](#minimum-setup-without-dns-tunnel)
- [Full Setup (With DNS Tunnel)](#full-setup-with-dns-tunnel)
- [Provider-Specific Instructions](#provider-specific-instructions)
  - [Cloudflare](#cloudflare)
  - [Namecheap](#namecheap)
  - [Google Domains / Squarespace](#google-domains--squarespace)
  - [Hetzner DNS](#hetzner-dns)
- [Dynamic DNS for Home Servers](#dynamic-dns-for-home-servers)
  - [DuckDNS (Free)](#duckdns-free)
  - [Cloudflare DDNS (Own Domain)](#cloudflare-ddns-own-domain)
- [Verification](#verification)
- [Common Issues](#common-issues)
- [Domain Acquisition Tips](#domain-acquisition-tips)

---

## Overview

MoaV uses these DNS records:

| Record Type | Name | Value | Purpose |
|-------------|------|-------|---------|
| A | `@` or `domain.com` | Server IP | Main domain for Trojan/Hysteria2 |
| A | `dns` | Server IP | For dnstt NS delegation |
| NS | `t` | `dns.domain.com` | DNS tunnel subdomain |

## Minimum Setup (Without DNS Tunnel)

If you don't need the DNS tunnel (last resort option), you only need:

```
Type: A
Name: @ (or your domain name)
Value: YOUR_SERVER_IP
TTL: 300 (or Auto)
```

## Full Setup (With DNS Tunnel)

### Step 1: Main A Record

```
Type: A
Name: @ (or your domain name)
Value: YOUR_SERVER_IP
TTL: 300
```

### Step 2: DNS Server A Record

```
Type: A
Name: dns
Value: YOUR_SERVER_IP
TTL: 300
```

This creates `dns.yourdomain.com` pointing to your server.

### Step 3: NS Delegation for Tunnel

```
Type: NS
Name: t
Value: dns.yourdomain.com
TTL: 300
```

This tells DNS resolvers that queries for `*.t.yourdomain.com` should be sent to `dns.yourdomain.com` (your server).

### Optional: IPv6 Support

If your server has IPv6, you can also add an AAAA record for the nameserver:

```
Type: AAAA
Name: dns
Value: YOUR_SERVER_IPV6
TTL: 300
```

> **More Info**: For detailed dnstt documentation, see the [official dnstt guide](https://www.bamsoftware.com/software/dnstt/).

## Provider-Specific Instructions

### Cloudflare

1. Log into Cloudflare Dashboard
2. Select your domain
3. Go to DNS → Records
4. Add records:

**Important:** Set proxy status to "DNS only" (gray cloud), NOT "Proxied" (orange cloud)

| Type | Name | Content | Proxy status |
|------|------|---------|--------------|
| A | @ | YOUR_IP | DNS only |
| A | dns | YOUR_IP | DNS only |
| NS | t | dns.yourdomain.com | - |
| A | cdn | YOUR_IP | **Proxied** (orange cloud) |

> The `cdn` record is optional — only needed if you want CDN-fronted VLESS+WS. See [CDN Setup](SETUP.md#cdn-fronted-vlesswebsocket-cloudflare) for details. All other records **must** be DNS only (gray cloud).

### Namecheap

1. Log into Namecheap
2. Domain List → Manage → Advanced DNS
3. Add records:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| A Record | @ | YOUR_IP | Automatic |
| A Record | dns | YOUR_IP | Automatic |
| NS Record | t | dns.yourdomain.com. | Automatic |

Note: NS value may need trailing dot.

### Google Domains / Squarespace

1. Go to DNS settings
2. Add custom records:

| Host name | Type | TTL | Data |
|-----------|------|-----|------|
| (blank) | A | 300 | YOUR_IP |
| dns | A | 300 | YOUR_IP |
| t | NS | 300 | dns.yourdomain.com |

### Hetzner DNS

1. Go to DNS Console
2. Select your zone
3. Add records:

```
@ IN A YOUR_IP
dns IN A YOUR_IP
t IN NS dns.yourdomain.com.
```

## Dynamic DNS for Home Servers

If you're running MoaV on a home server (like a Raspberry Pi), your ISP likely assigns a dynamic IP address that changes periodically. Dynamic DNS (DDNS) services automatically update your domain to point to your current IP.

### Before You Start

1. **Check for CGNAT**: Some ISPs use Carrier-Grade NAT which prevents incoming connections entirely. Test by comparing your router's WAN IP with `curl ifconfig.me`. If they differ, contact your ISP for a public IP.

2. **Port Forwarding**: Configure your router to forward these ports to your MoaV server:
   - 80/tcp (Let's Encrypt verification, only during setup)
   - 443/tcp (Reality, Trojan)
   - 443/udp (Hysteria2)
   - 8443/tcp (Trojan fallback)
   - 51820/udp (WireGuard)
   - 53/udp (DNS tunnel, if using)

### DuckDNS (Free)

DuckDNS is a free DDNS service that provides subdomains like `yourname.duckdns.org`. Let's Encrypt works with DuckDNS domains.

#### Step 1: Create Account

1. Go to [duckdns.org](https://www.duckdns.org/)
2. Sign in with Google, GitHub, Twitter, or Reddit
3. Create a subdomain (e.g., `myvpn` → `myvpn.duckdns.org`)
4. Copy your **token** from the dashboard

#### Step 2: Install Update Script

On your MoaV server (Raspberry Pi or home server):

```bash
# Create update script
mkdir -p /opt/duckdns
cat > /opt/duckdns/duck.sh << 'EOF'
#!/bin/bash
DOMAIN="YOUR_SUBDOMAIN"  # e.g., myvpn (without .duckdns.org)
TOKEN="YOUR_TOKEN"

curl -s "https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ip=" | logger -t duckdns
EOF

# Replace with your values
nano /opt/duckdns/duck.sh

# Make executable
chmod +x /opt/duckdns/duck.sh

# Test it
/opt/duckdns/duck.sh
```

#### Step 3: Schedule Automatic Updates

```bash
# Add to crontab (runs every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/duckdns/duck.sh") | crontab -
```

#### Step 4: Configure MoaV

In your `.env` file:
```bash
DOMAIN=yourname.duckdns.org
```

Then run bootstrap as normal.

### Cloudflare DDNS (Own Domain)

If you have your own domain on Cloudflare, you can use the Cloudflare API to update DNS records automatically.

#### Step 1: Get API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → My Profile → API Tokens
2. Create a token with **Zone:DNS:Edit** permission for your domain
3. Copy the token

#### Step 2: Get Zone ID

1. Go to your domain in Cloudflare
2. Scroll down on the Overview page
3. Copy the **Zone ID** from the right sidebar

#### Step 3: Install Update Script

```bash
mkdir -p /opt/cloudflare-ddns
cat > /opt/cloudflare-ddns/update.sh << 'EOF'
#!/bin/bash

# Configuration
CF_API_TOKEN="YOUR_API_TOKEN"
CF_ZONE_ID="YOUR_ZONE_ID"
DOMAIN="yourdomain.com"
RECORD_NAME="@"  # Use "@" for root domain or "subdomain" for subdomain

# Get current public IP
CURRENT_IP=$(curl -s https://api.ipify.org)

# Get current DNS record
RECORD_DATA=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD_DATA" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
RECORD_IP=$(echo "$RECORD_DATA" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)

# Update if IP changed
if [ "$CURRENT_IP" != "$RECORD_IP" ]; then
    echo "IP changed from $RECORD_IP to $CURRENT_IP, updating..."
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${CURRENT_IP}\",\"ttl\":300,\"proxied\":false}" | logger -t cloudflare-ddns
else
    echo "IP unchanged ($CURRENT_IP)"
fi
EOF

# Edit with your values
nano /opt/cloudflare-ddns/update.sh

chmod +x /opt/cloudflare-ddns/update.sh
```

#### Step 4: Schedule Updates

```bash
# Run every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/cloudflare-ddns/update.sh") | crontab -
```

#### Step 5: Configure MoaV

In your `.env`:
```bash
DOMAIN=yourdomain.com
```

### After DDNS Setup

1. **Wait for propagation**: After the first update, wait 5-10 minutes
2. **Verify**: `dig +short yourdomain.com` should show your home IP
3. **Run MoaV setup**: `moav` to start the interactive setup
4. **Test from outside**: Use mobile data (not home WiFi) to test connectivity

### Home Server Tips

- **Static local IP**: Assign a static IP to your MoaV server in your router's DHCP settings
- **UPS recommended**: Protect against power outages
- **Monitor uptime**: Use a free service like [UptimeRobot](https://uptimerobot.com/) to alert you if your server goes down
- **Backup regularly**: `moav export` to backup your configuration

---

## Verification

After configuring DNS, wait for propagation (usually 5-30 minutes, up to 48 hours).

### Verify A Record

```bash
dig +short yourdomain.com
# Should return: YOUR_SERVER_IP

dig +short dns.yourdomain.com
# Should return: YOUR_SERVER_IP
```

### Verify NS Delegation

```bash
dig NS t.yourdomain.com
# Should show: dns.yourdomain.com in AUTHORITY SECTION

# Test that queries reach your server
dig @YOUR_SERVER_IP test.t.yourdomain.com
# Should get a response (after dnstt is running)
```

### Online Tools

- https://dnschecker.org - Check propagation worldwide
- https://mxtoolbox.com/DNSLookup.aspx - Detailed DNS lookup

## Common Issues

### "DNS not propagated yet"

Wait longer (up to 48 hours in rare cases). Check with multiple DNS servers:

```bash
dig @8.8.8.8 yourdomain.com
dig @1.1.1.1 yourdomain.com
```

### "NS record not working"

- Ensure the A record for `dns.yourdomain.com` exists
- Some registrars require a trailing dot: `dns.yourdomain.com.`
- NS delegation can take longer to propagate

### "Certificate acquisition failed"

- Verify A record is correct: `dig yourdomain.com`
- Ensure port 80 is open (temporarily, for ACME HTTP-01)
- Check that no other service is using port 80

## Domain Acquisition Tips

For users in censored regions:

1. **Use privacy protection** - Hide your personal info in WHOIS
2. **Pay with crypto** if possible - For anonymity
3. **Choose a neutral TLD** - `.com`, `.net`, `.org` are less suspicious than country-specific TLDs
4. **Avoid "VPN" or "proxy" in the domain name** - Keep it generic
5. **Consider multiple domains** - Have backups ready if one gets blocked

### Recommended Registrars

- Namecheap - Good privacy, accepts crypto
- Porkbun - Cheap, good privacy
- Njalla - Maximum privacy (they own the domain for you)
