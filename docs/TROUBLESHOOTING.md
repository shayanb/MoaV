# Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

- [Git and Update Issues](#git-and-update-issues)
  - [Update fails with "local changes would be overwritten"](#update-fails-with-local-changes-would-be-overwritten)
  - [Recovering from failed updates](#recovering-from-failed-updates)
  - [Switching branches](#switching-branches)
- [Server-Side Issues](#server-side-issues)
  - [Services won't start](#services-wont-start)
  - [Certificate issues](#certificate-issues)
  - [Admin dashboard not accessible](#admin-dashboard-not-accessible)
  - [sing-box crashes](#sing-box-crashes)
  - [WireGuard connected but no traffic](#wireguard-connected-but-no-traffic)
  - [Hysteria2 not working](#hysteria2-not-working)
  - [TrustTunnel not connecting](#trusttunnel-not-connecting)
  - [CDN VLESS+WS not working](#cdn-vlessws-not-working)
  - [DNS tunnel not working](#dns-tunnel-not-working)
- [MoaV Test/Client Issues](#moav-testclient-issues)
- [Client-Side Issues](#client-side-issues)
- [Network-Specific Issues](#network-specific-issues)
- [Highly Censored Environments](#highly-censored-environments-specific-issues)
- [Reset and Re-bootstrap](#reset-and-re-bootstrap)
- [Common Commands](#common-commands)
- [Getting Help](#getting-help)

---

## Git and Update Issues

### Update fails with "local changes would be overwritten"

When running `moav update` or the installer, you may see:

```
error: Your local changes to the following files would be overwritten by merge:
    scripts/client-test.sh
Please commit your changes or stash them before you merge.
Aborting
```

**Why this happens:**
- You edited files while testing a fix or feature
- You manually modified configuration scripts
- You tested a development branch and switched back

**Solution 1: Use the interactive prompt (recommended)**

The latest MoaV versions detect this and offer options:
```bash
moav update
# Will show:
# ⚠ Local changes detected:
#     M scripts/client-test.sh
# Options:
#   1) Stash changes (save temporarily, can restore later)
#   2) Discard changes (reset to clean state)
#   3) Abort
```

Choose option 1 to save your changes, or option 2 to discard them.

**Solution 2: Manual stash**

```bash
cd /opt/moav

# Save your changes temporarily
git stash

# Now update
moav update
# or: git pull

# Restore your changes (may cause conflicts)
git stash pop
```

**Solution 3: Discard changes**

If you don't need your local changes:
```bash
cd /opt/moav

# Discard all local modifications
git checkout -- .

# Remove untracked files
git clean -fd

# Now update
moav update
```

### Recovering from failed updates

If an update fails partway through:

```bash
cd /opt/moav

# Check current state
git status

# If there are merge conflicts
git merge --abort

# Reset to last known good state
git reset --hard HEAD

# Try updating again
moav update
```

**If you need to completely reset:**

```bash
cd /opt/moav

# Fetch latest from remote
git fetch origin

# Hard reset to remote main
git reset --hard origin/main

# Verify
git status
```

### Switching branches

**Switch to a feature/test branch:**
```bash
cd /opt/moav
git fetch origin
git checkout feature-branch-name
git pull
moav build  # Rebuild containers if needed
```

**Switch back to stable (main):**
```bash
cd /opt/moav
git checkout main
git pull
moav build
```

**If switching fails due to local changes:**
```bash
# Stash changes first
git stash
git checkout main
git pull

# Optionally restore changes
git stash pop
```

### Common scenarios

**Testing a bug fix from GitHub:**
```bash
# Save current state
cd /opt/moav
git stash

# Get the fix
git fetch origin
git checkout fix-branch-name
moav build
moav restart

# After testing, return to main
git checkout main
git stash pop  # Restore your changes if needed
```

**Accidentally edited files:**
```bash
# See what changed
git diff

# If you want to keep changes, stash them
git stash

# If you want to discard
git checkout -- filename.sh

# Or discard all changes
git checkout -- .
```

**View stashed changes:**
```bash
# List all stashes
git stash list

# Show what's in the most recent stash
git stash show -p

# Apply a specific stash
git stash apply stash@{0}

# Delete a stash
git stash drop stash@{0}
```

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

### TrustTunnel not connecting

**Check container is running:**
```bash
docker compose --profile trusttunnel ps
docker compose logs trusttunnel
```

**Common issues:**

1. **Port not open:**
   ```bash
   ufw allow 4443/tcp
   ufw allow 4443/udp
   ```

2. **Certificate issue:**
   - TrustTunnel uses the same Let's Encrypt certificate as other services
   - If cert is missing, run `moav bootstrap` again

3. **Client config error:**
   - Verify credentials match `trusttunnel.txt` in user bundle
   - Check `trusttunnel.toml` has correct domain/IP

### CDN VLESS+WS not working

**DNS lookup failure:**
If you see `lookup cdn.yourdomain.com: operation was canceled`:
1. Verify `cdn` subdomain exists in Cloudflare DNS
2. Check it's set to **Proxied** (orange cloud)
3. Wait for DNS propagation (up to 5 minutes)

**Connection refused:**
1. Verify port 2082 is open: `ufw allow 2082/tcp`
2. Check sing-box is listening: `docker compose logs sing-box | grep vless-ws`

**Cloudflare 521 "Web server is down":**

This usually means Cloudflare can't reach your origin on the correct port.

1. **Check Origin Rule exists** (most common cause):
   - Go to Cloudflare → Rules → Origin Rules
   - You need a rule that redirects `cdn.yourdomain.com` to port 2082
   - Without this, Cloudflare connects to port 80 (wrong port)
   - See [DNS.md Cloudflare section](DNS.md#cloudflare) for setup instructions

2. **Verify port 2082 is reachable:**
   ```bash
   # From another machine, test direct access to your server
   curl -s -o /dev/null -w "%{http_code}" http://YOUR_SERVER_IP:2082/ws
   # Should return 400 (sing-box responding)
   ```

3. **Check firewall:**
   ```bash
   ufw allow 2082/tcp
   ```

4. **Verify sing-box is listening:**
   ```bash
   docker compose logs sing-box | grep -i "vless-ws"
   ```

**Cloudflare 520 "Unknown error":**
1. Set SSL/TLS mode to **Flexible** in Cloudflare dashboard
2. Verify sing-box container is running
3. Check sing-box config has `vless-ws-in` inbound on port 2082

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
