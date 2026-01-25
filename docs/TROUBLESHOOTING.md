# Troubleshooting Guide

Common issues and their solutions.

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

3. **Configuration error:**
   ```bash
   # Validate sing-box config
   docker compose exec sing-box sing-box check -c /etc/sing-box/config.json
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

### DNS tunnel not working

**Verify NS delegation:**
```bash
dig NS t.yourdomain.com
# Should return dns.yourdomain.com
```

**Test dnstt server:**
```bash
docker compose logs dnstt
# Should show "listening on :5353"
```

**Check firewall:**
```bash
# Ensure UDP 53 is open
ufw allow 53/udp
# or
iptables -A INPUT -p udp --dport 53 -j ACCEPT
```

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

## Iran-Specific Issues

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

During major events, Iran sometimes shuts internet entirely:

1. DNS tunnel might still work (if any DNS works)
2. Satellite internet (Starlink) if available
3. Wait for restoration

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
# Restart all
docker compose restart

# Restart specific
docker compose restart sing-box

# Full rebuild
docker compose down
docker compose up -d --build
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
