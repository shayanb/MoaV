# Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

- [Server-Side Issues](#server-side-issues)
  - [Services won't start](#services-wont-start)
  - [Certificate issues](#certificate-issues)
  - [Admin dashboard not accessible](#admin-dashboard-not-accessible)
  - [sing-box crashes](#sing-box-crashes)
  - [WireGuard connected but no traffic](#wireguard-connected-but-no-traffic)
  - [DNS tunnel not working](#dns-tunnel-not-working)
- [MoaV Test/Client Issues](#moav-testclient-issues)
- [Client-Side Issues](#client-side-issues)
- [Network-Specific Issues](#network-specific-issues)
- [Highly Censored Environments](#highly-censored-environments-specific-issues)
- [Reset and Re-bootstrap](#reset-and-re-bootstrap)
- [Common Commands](#common-commands)
- [Getting Help](#getting-help)

---

## Server-Side Issues

### Services won't start

**Check logs:**
```bash
docker compose logs sing-box
docker compose logs certbot
```

**Common causes:**

1. **Certificate not obtained:**
   ```bash
   # Check if cert exists
   docker compose exec sing-box ls -la /certs/live/

   # Re-run certbot
   docker compose run --rm certbot certonly --standalone \
     --non-interactive --agree-tos \
     --email YOUR_EMAIL --domains YOUR_DOMAIN
   ```

2. **Port already in use:**
   ```bash
   # Check what's using port 443
   ss -tlnp | grep 443

   # Stop conflicting service
   systemctl stop nginx  # or apache2
   ```

3. **Port 53 already in use (for dnstt):**

   This is usually caused by systemd-resolved:
   ```bash
   # Check what's using port 53
   ss -ulnp | grep 53

   # Stop and disable systemd-resolved
   systemctl stop systemd-resolved
   systemctl disable systemd-resolved

   # Set up direct DNS resolution
   echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
   ```

4. **Configuration error:**
   ```bash
   # Validate sing-box config
   docker compose exec sing-box sing-box check -c /etc/sing-box/config.json
   ```

5. **Docker network error ("network not found"):**

   This happens when Docker networks get corrupted from failed runs:
   ```bash
   # Stop all containers and remove networks
   docker compose down
   docker network prune -f

   # Start fresh
   docker compose --profile all up -d
   ```

6. **Only some images built:**

   All services require `--profile` to be specified:
   ```bash
   # Build ALL images including optional services
   docker compose --profile all build --no-cache

   # Build only proxy services
   docker compose --profile proxy build

   # Available profiles: proxy, wireguard, dnstt, admin, conduit, snowflake, all
   ```

7. **Port already in use (8443 for Trojan):**

   Change the Trojan port in your .env file:
   ```bash
   # In .env
   PORT_TROJAN=9443  # Or any available port
   ```

### Certificate issues

**Certificate not renewing:**
```bash
# Manual renewal
docker compose run --rm certbot renew

# Check certificate expiry
docker compose exec sing-box openssl x509 -enddate -noout -in /certs/live/*/fullchain.pem
```

**Certificate acquisition failed:**
- Ensure DNS A record points to this server
- Ensure port 80 is open (temporarily)
- Check rate limits: https://letsencrypt.org/docs/rate-limits/

### Admin dashboard not accessible

**Check if container is running:**
```bash
docker compose --profile admin ps
docker compose --profile admin logs admin
```

**Verify port is listening:**
```bash
# Inside container
docker exec moav-admin ss -tlnp

# On host
ss -tlnp | grep 9443
```

**Test locally first:**
```bash
curl -k https://localhost:9443/api/health
# Should return: {"status":"ok","timestamp":"..."}
```

**Open firewall:**
```bash
ufw allow 9443/tcp
# or
iptables -A INPUT -p tcp --dport 9443 -j ACCEPT
```

**Browser shows security warning (domain-less mode):**

In domain-less mode, admin uses a self-signed certificate. This is expected:
1. Click "Advanced" or "Show Details"
2. Click "Proceed to site" or "Accept the Risk"

**Access URLs:**
- With domain: `https://yourdomain.com:9443/`
- Domain-less mode: `https://YOUR_SERVER_IP:9443/`

**Admin runs on port 9443 by default** (not 8443). The internal container port is 8443, but it's mapped to 9443 externally.

### sing-box crashes

**Check the logs:**
```bash
docker compose logs -f sing-box
```

**Common fixes:**
```bash
# Rebuild container
docker compose build --no-cache sing-box
docker compose up -d sing-box

# Reset configuration
docker compose --profile setup run --rm bootstrap
```

### WireGuard handshake timeout

If you see:
```
Handshake for peer 1 (SERVER:51820) did not complete after 5 seconds, retrying
```

This means UDP packets aren't reaching the server. Common causes:

1. **UDP port 51820 blocked** - Most common in restrictive networks
   - Try WireGuard-wstunnel mode instead (tunnels over TCP/WebSocket)

2. **Server firewall:**
   ```bash
   ufw allow 51820/udp
   ```

3. **Server WireGuard not running:**
   ```bash
   docker compose --profile wireguard ps
   # Should show wireguard as "running"
   ```

### WireGuard-wstunnel not connecting

If you see errors like:
```
Cannot connect to tcp endpoint SERVER:8080 due to timeout
```

1. **Open port 8080 on server firewall:**
   ```bash
   ufw allow 8080/tcp
   ```

2. **Check wstunnel is running:**
   ```bash
   docker compose --profile wireguard ps
   # Both wireguard and wstunnel should be running
   ```

3. **Check wstunnel logs:**
   ```bash
   docker compose logs wstunnel
   ```

4. **Rebuild after update** (if you updated MoaV):
   ```bash
   docker compose --profile wireguard build wstunnel
   docker compose --profile wireguard up -d
   ```

### Hysteria2 not working

Hysteria2 uses **UDP port 443**. If it's not working but Reality/Trojan work:

1. **UDP is likely blocked** by your network - this is common in restrictive environments
2. Hysteria2 is designed for networks where TCP is throttled but UDP works
3. **Try other protocols** - Reality and Trojan use TCP and are more likely to work

**Verify server-side:**
```bash
# Check Hysteria2 is listening
docker compose logs sing-box | grep -i hysteria

# Test UDP connectivity (from another machine)
nc -vuz YOUR_SERVER_IP 443
```

### Paqet not starting

Paqet requires special system capabilities. Common issues:

1. **OpenVZ/LXC container detected:**
   ```
   OpenVZ detected - raw sockets not supported!
   ```
   **Solution:** Paqet requires KVM, Xen, or bare metal. OpenVZ/LXC don't support raw sockets.

2. **Missing libpcap:**
   ```
   error loading libpcap
   ```
   **Solution:**
   ```bash
   # Debian/Ubuntu
   apt install libpcap-dev

   # Alpine (in container)
   apk add libpcap
   ```

3. **Permission denied:**
   ```
   permission denied creating raw socket
   ```
   **Solution:** Paqet must run with root/admin privileges and the container needs:
   - `--network host`
   - `--privileged` (or `--cap-add NET_RAW --cap-add NET_ADMIN`)

4. **Gateway MAC not detected:**
   ```
   Could not detect gateway MAC address
   ```
   **Solution:** The entrypoint script auto-detects network config. If it fails:
   ```bash
   # Check gateway IP
   ip route | grep default

   # Ping gateway to populate ARP table
   ping -c 1 GATEWAY_IP

   # Get MAC
   ip neigh show GATEWAY_IP
   ```

5. **iptables rules not set:**
   Paqet needs specific iptables rules to prevent kernel RST packets:
   ```bash
   # These should be set automatically by the entrypoint
   iptables -t raw -A PREROUTING -p tcp --dport 9999 -j NOTRACK
   iptables -t raw -A OUTPUT -p tcp --sport 9999 -j NOTRACK
   iptables -t mangle -A OUTPUT -p tcp --sport 9999 --tcp-flags RST RST -j DROP
   ```

### Paqet iptables rules not persisting

The iptables rules set by paqet's entrypoint are lost on reboot. To persist them:

**Debian/Ubuntu:**
```bash
# Save rules
iptables-save > /etc/iptables/rules.v4

# Install iptables-persistent
apt install iptables-persistent
```

**Alpine:**
```bash
# Save rules
/etc/init.d/iptables save

# Enable at boot
rc-update add iptables
```

Or add the rules to your server's startup script.

### WireGuard connected but no traffic

**Check if peer is loaded:**
```bash
docker compose exec wireguard wg show
```

Look for your peer's public key. It should show:
- `latest handshake: X seconds ago`
- `transfer: X received, X sent`

If there's no handshake, check for **key mismatch**:

```bash
# What the client config expects (server public key)
cat configs/wireguard/server.pub

# What's actually running
docker compose exec wireguard wg show wg0 public-key
```

**If keys don't match**, run the sync script:
```bash
# Automatically sync keys from running WireGuard
./scripts/wg-sync-keys.sh

# Or manually fix:
docker compose exec wireguard wg show wg0 public-key > configs/wireguard/server.pub

# Regenerate user with correct key
./scripts/wg-user-add.sh newuser
```

**Check NAT/masquerade:**
```bash
docker compose exec wireguard iptables -t nat -L -n | grep MASQUERADE
```

**Check IP forwarding:**
```bash
docker compose exec wireguard cat /proc/sys/net/ipv4/ip_forward
# Should return 1
```

**Check firewall allows WireGuard port:**
```bash
ufw allow 51820/udp
```

**Update MoaV if issue persists:**

Older versions had missing iptables rules for return traffic. Update and rebuild:
```bash
cd /opt/moav
moav update
docker compose --profile wireguard build --no-cache wireguard
moav restart wireguard
```

### DNS tunnel not working

**Check dnstt logs for domain issues:**
```bash
docker compose logs dnstt
```

If you see `NXDOMAIN: not authoritative for example.com`, the domain wasn't set correctly during bootstrap:

```bash
# Check the config file
cat configs/dnstt/server.conf
# Should show: DNSTT_DOMAIN=t.yourdomain.com (not example.com)

# If wrong, update it
sed -i 's/example.com/yourdomain.com/g' configs/dnstt/server.conf

# Rebuild and restart dnstt
docker compose build dnstt
docker compose --profile dnstt up -d dnstt
```

**Verify NS delegation:**
```bash
dig NS t.yourdomain.com
# Should return dns.yourdomain.com (or your server)
```

**Test dnstt server:**
```bash
docker compose logs dnstt
# Should show "listening on :5353" and your correct domain
```

**Check firewall:**
```bash
# Ensure UDP 53 is open
ufw allow 53/udp
# or
iptables -A INPUT -p udp --dport 53 -j ACCEPT
```

---

## MoaV Test/Client Issues

### `moav test` fails to build

**Docker build errors:**
```bash
# Rebuild with no cache
moav client build --no-cache

# Or manually:
docker build --no-cache -t moav-client -f Dockerfile.client .
```

**Network issues during build:**
- Pre-built binaries are downloaded from GitHub/GitLab
- If downloads fail, the build falls back to compiling from source (slower)
- Check your server has internet access

### `moav test` shows all protocols as "skip"

**User bundle not found:**
```bash
# Check if bundle exists
ls -la outputs/bundles/user1/

# Regenerate user bundle
moav user add user1
```

**Bundle path issue:**
```bash
# Verify the bundle contains config files
ls outputs/bundles/user1/
# Should contain: reality.txt, trojan.txt, hysteria2.yaml, etc.
```

### `moav test` shows "sing-box failed to start"

**Configuration format issue:**
- sing-box 1.12+ requires `route.final` instead of deprecated special outbounds
- Check sing-box version: `docker run --rm moav-client sing-box version`

**Debug with verbose output:**
```bash
# Run test container interactively
docker run --rm -it \
  -v "$(pwd)/outputs/bundles/user1:/config:ro" \
  moav-client /bin/bash

# Inside container, manually test
VERBOSE=true CONFIG_DIR=/config /app/client-test.sh
```

### `moav client connect` can't establish connection

**Check server is running:**
```bash
moav status
# Ensure sing-box and other services show as "running"
```

**Try different protocols:**
```bash
moav client connect user1 --protocol hysteria2
moav client connect user1 --protocol trojan
```

**Check firewall on server:**
```bash
# Server-side
ufw status
ss -tlnp  # TCP ports
ss -ulnp  # UDP ports
```

### Client proxy ports already in use

**Change ports in .env:**
```bash
# In .env
CLIENT_SOCKS_PORT=10800
CLIENT_HTTP_PORT=18080
```

**Or stop conflicting service:**
```bash
# Check what's using port 1080
ss -tlnp | grep 1080
```

### WireGuard test shows "endpoint not reachable"

This is expected if:
- UDP port 51820 is blocked by firewall
- Server WireGuard container is not running

**Check WireGuard is running:**
```bash
docker compose --profile wireguard ps
```

**Check UDP is not blocked:**
```bash
# From client machine
nc -vuz YOUR_SERVER_IP 51820
```

### Tor/Snowflake fallback not working

**Tor is standalone and doesn't require your server:**
```bash
# Test Snowflake independently
docker run --rm moav-client snowflake-client --help
```

**If binaries are missing:**
- Some optional binaries may fail to download during build
- Check build logs for "not available (optional)" messages

**For Psiphon:**
- Psiphon is not available via MoaV client
- Use the [official Psiphon apps](https://psiphon.ca/en/download.html) instead

---

## Client-Side Issues

### Can't connect at all

1. **Verify server is reachable:**
   ```bash
   ping YOUR_SERVER_IP
   curl -I https://yourdomain.com
   ```

2. **Check if IP is blocked:**
   - Try from a different network (mobile data)
   - Use online tools to check if IP is accessible from Iran

3. **Try different protocols:**
   Reality → Hysteria2 → Trojan → WireGuard → DNS tunnel

### TLS handshake timeout

**Causes:**
- Server certificate issue
- Deep packet inspection blocking
- Server overloaded

**Solutions:**
1. Try Reality protocol (doesn't use your cert)
2. Try Hysteria2 (uses UDP)
3. Check server certificate is valid

### Slow connection

**Hysteria2 often helps** - it's optimized for lossy networks.

**For sing-box clients:**
- Enable multiplexing
- Try different congestion control

**Check server resources:**
```bash
docker stats
htop
```

### Frequent disconnections

1. **Enable keep-alive:**
   - In client app, look for "persistent connection" or "keep-alive"

2. **Check server uptime:**
   ```bash
   docker compose ps
   uptime
   ```

3. **Check for IP blocks:**
   - ISP may be actively disrupting connections
   - Try rotating to a new server IP

### "Invalid config" errors

1. Ensure you're using the correct link for your app
2. Check for extra spaces or newlines in the link
3. Try importing the JSON file instead of the link

---

## Network-Specific Issues

### Works on WiFi but not mobile data

Mobile carriers may have different filtering:
- Try Hysteria2 (UDP-based)
- Try DNS tunnel
- Some carriers block all VPN signatures

### Works on mobile data but not WiFi

Home ISPs often have stricter filtering:
- Try Reality protocol
- Try different Reality target sites
- Try port 80 or other ports (if configured)

### Very slow despite connection working

1. **Check if throttled:**
   - Speed test without VPN
   - Speed test with VPN
   - If VPN is significantly slower, you're being throttled

2. **Try Hysteria2:**
   - Uses UDP which is sometimes less throttled
   - Has built-in congestion control

3. **Try different times:**
   - Filtering may be heavier during peak hours

---

## highly censored environments-Specific Issues

### All protocols blocked

When ISP blocks everything:

1. **DNS Tunnel** - Often still works as it's hard to block all DNS
2. **Different Reality targets** - Try:
   - `www.apple.com`
   - `dl.google.com`
   - `www.samsung.com`
   - `update.microsoft.com`

3. **Get a new server** - Your IP may be specifically blocked

### Protocol detected and blocked

Signs your protocol is detected:
- Works for a few minutes then dies
- Works initially then stops
- Specific protocol fails but others work

**Solutions:**
1. Switch protocols immediately
2. Change Reality target domain
3. Update to latest sing-box version (better anti-detection)

### Total internet shutdown

During major events, Govs sometimes shuts internet entirely:

1. DNS tunnel might still work (if any DNS works)
2. Satellite internet (Starlink) if available
3. Wait for restoration

---

## Reset and Re-bootstrap

### Full reset (start fresh)

If things are broken beyond repair, reset everything:

```bash
# Stop all containers
docker compose --profile all down

# Remove the bootstrap flag and all generated state
docker run --rm -v moav_moav_state:/state alpine rm -rf /state/.bootstrapped /state/keys /state/users

# Optionally remove generated configs (will be regenerated)
rm -rf configs/sing-box/config.json configs/wireguard/wg0.conf configs/dnstt/server.conf

# Remove Docker volumes entirely (complete reset)
docker volume rm moav_moav_state moav_moav_certs moav_moav_logs

# Re-run bootstrap
docker compose --profile setup run --rm bootstrap

# Start services
docker compose --profile all up -d
```

### Partial reset (keep certificates)

To re-bootstrap while keeping your SSL certificates:

```bash
# Stop services
docker compose --profile all down

# Remove only the bootstrap flag
docker run --rm -v moav_moav_state:/state alpine rm /state/.bootstrapped

# Re-run bootstrap
docker compose --profile setup run --rm bootstrap

# Start services
docker compose --profile all up -d
```

### Reset only WireGuard

```bash
# Remove WireGuard config
rm configs/wireguard/wg0.conf configs/wireguard/server.pub

# Remove WireGuard keys from state
docker run --rm -v moav_moav_state:/state alpine rm -f /state/keys/wg-server.key /state/keys/wg-server.pub

# Remove bootstrap flag and re-run
docker run --rm -v moav_moav_state:/state alpine rm /state/.bootstrapped
docker compose --profile setup run --rm bootstrap

# Restart WireGuard
docker compose --profile wireguard up -d wireguard
```

### Reset only dnstt

```bash
# Remove dnstt config and keys
rm configs/dnstt/server.conf configs/dnstt/server.pub
docker run --rm -v moav_moav_state:/state alpine rm -f /state/keys/dnstt-*

# Remove bootstrap flag and re-run
docker run --rm -v moav_moav_state:/state alpine rm /state/.bootstrapped
docker compose --profile setup run --rm bootstrap

# Restart dnstt
docker compose --profile dnstt up -d dnstt
```

---

## Common Commands

### View logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs sing-box
docker compose logs -f sing-box  # Follow

# Last 100 lines
docker compose logs --tail=100 sing-box
```

### Restart services

```bash
# Restart all (specify the profile you're using)
docker compose --profile all restart

# Restart specific service
docker compose --profile proxy restart sing-box

# Full rebuild
docker compose --profile all down
docker compose --profile all up -d --build
```

### Check resource usage

```bash
docker stats
```

### Test connectivity

```bash
# Test from server
curl -I https://google.com

# Test TLS
openssl s_client -connect yourdomain.com:443

# Test specific protocol
# (run from a client that works)
```

### Reload configuration

```bash
# sing-box hot reload
docker compose exec sing-box sing-box reload

# Or restart container
docker compose restart sing-box
```

---

## Getting Help

If issues persist:

1. **Collect logs:**
   ```bash
   docker compose logs > logs.txt
   ```

2. **Check configuration:**
   ```bash
   docker compose exec sing-box sing-box check -c /etc/sing-box/config.json
   ```

3. **Verify network:**
   ```bash
   curl -I https://yourdomain.com
   dig yourdomain.com
   ```

4. **Document:**
   - What protocol you're trying
   - What client app and version
   - Error messages
   - When it started failing
