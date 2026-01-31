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
