# Operational Security Guide

Security recommendations for running and using MoaV safely.

## For Server Operators

### Server Security

1. **Keep system updated:**
   ```bash
   apt update && apt upgrade -y
   # Enable automatic security updates
   apt install unattended-upgrades
   dpkg-reconfigure unattended-upgrades
   ```

2. **Use SSH keys, disable password auth:**
   ```bash
   # In /etc/ssh/sshd_config:
   PasswordAuthentication no
   PermitRootLogin prohibit-password
   ```

3. **Enable firewall:**
   ```bash
   ufw allow 22/tcp    # SSH
   ufw allow 443/tcp   # HTTPS/Trojan/Reality
   ufw allow 443/udp   # Hysteria2
   ufw allow 53/udp    # DNS tunnel
   ufw enable
   ```

4. **Change SSH port** (optional):
   ```bash
   # In /etc/ssh/sshd_config:
   Port 2222  # or another port
   ```

### Domain Security

1. **Use WHOIS privacy** - Hide your personal information
2. **Use a neutral registrar** - Avoid country-specific registrars
3. **Keep registration info generic** - Don't use real name if possible
4. **Pay anonymously** - Use crypto if available

### Credential Management

1. **Never share master credentials** - Each user gets unique creds
2. **Revoke compromised users immediately:**
   ```bash
   ./scripts/user-revoke.sh compromised_user
   ```
3. **Rotate server keys periodically** - Re-bootstrap if concerned
4. **Keep backups of state:**
   ```bash
   tar czf moav-backup-$(date +%Y%m%d).tar.gz \
     configs/ outputs/ .env
   ```

### Monitoring

1. **Watch for unusual patterns:**
   - Sudden traffic spikes
   - Connections from unexpected IPs
   - Failed authentication attempts

2. **Check logs regularly:**
   ```bash
   docker compose logs --tail=100 sing-box | grep -i error
   ```

3. **Set up alerts** (optional):
   - Use Uptime Kuma or similar for monitoring
   - Alert on service down or high resource usage

### If Server is Blocked

1. **Don't panic** - Have a backup plan ready
2. **Try different protocols first** - Reality target change, Hysteria2
3. **If IP is blocked:**
   - Get a new VPS with fresh IP
   - Or use floating IP if provider supports
4. **Migrate:**
   ```bash
   # On old server
   tar czf moav-state.tar.gz configs/ outputs/ -v moav_state/_data/

   # On new server
   # Set up fresh, then restore user data
   ```

---

## For Users

### Device Security

1. **Use a separate profile/user** for circumvention apps on shared devices
2. **Don't screenshot QR codes** - Or delete immediately after import
3. **Delete bundle files** after importing to your apps
4. **Use device encryption** - Enable full disk encryption
5. **Set strong device PIN/password**

### Connection Security

1. **Verify you're connected:**
   - Check your IP: https://whatismyip.com
   - Should show server IP, not your real IP

2. **Use HTTPS everywhere** even over tunnel:
   - The tunnel encrypts transport, HTTPS encrypts content
   - Protects against compromised tunnel endpoints

3. **Don't trust public WiFi** even with VPN:
   - Your device can still be attacked locally
   - Tunnel doesn't protect against local network attacks

### App Security

1. **Keep apps updated** - Updates often fix detection bypasses
2. **Download from official sources:**
   - iOS: App Store
   - Android: GitHub releases or F-Droid
   - Avoid random APK sites

3. **Backup your configs:**
   - Export configs from apps
   - Store securely (encrypted)

### Behavior Security

1. **Don't share your credentials** - Each person should have their own
2. **Don't share screenshots** showing server addresses or QR codes
3. **Don't mention specific servers** in public forums
4. **Use secure messaging** to receive configs (Signal, encrypted email)

### If You Suspect Compromise

1. **Stop using that config immediately**
2. **Contact admin** for new credentials
3. **Check your device** for malware
4. **Change passwords** for any accounts accessed over that connection

---

## Distribution Security

### Sharing Bundles Safely

**DO:**
- Use end-to-end encrypted messaging (Signal, Telegram secret chat)
- Share in person when possible
- Use encrypted file sharing (OnionShare, Keybase)
- Delete messages after recipient confirms receipt

**DON'T:**
- Email unencrypted configs
- Post links in public channels
- Share via unencrypted cloud storage
- Send screenshots of QR codes to groups

### Recommended Distribution Methods

1. **In Person:**
   - Safest method
   - Scan QR code directly from your screen

2. **Signal:**
   - Send configs as files
   - Enable disappearing messages
   - Verify recipient's safety number

3. **Telegram (Secret Chat only):**
   - NOT regular chats
   - Use self-destruct timer

4. **Encrypted Email:**
   - PGP/GPG encrypted
   - Or use ProtonMail-to-ProtonMail

---

## Legal Considerations

**Disclaimer:** This is not legal advice.

### Know Your Jurisdiction

- Laws vary by country
- Running circumvention tools may be illegal in some places
- Using them may also carry risks
- Assess your personal risk level

### Plausible Deniability

The decoy website helps:
- Server looks like a normal HTTPS site
- No obvious "VPN" or "proxy" indicators
- Valid TLS certificate
- Generic content

### Data Retention

MoaV is configured for minimal logging:
- No URLs logged
- No request content
- Basic connection stats only (for admin)

To disable all logging:
```bash
# In .env
LOG_LEVEL=error
```

---

## Emergency Procedures

### If You Think You're Monitored

1. Stop using current credentials
2. Contact admin through alternate channel
3. Get fresh credentials
4. Consider using a different device
5. Assess whether to continue using service

### If Server is Raided/Seized

User data exposure is limited:
- Passwords are stored hashed
- No content is logged
- IP addresses are in memory only

But assume:
- Server IP is known
- User identifiers (not real names) are known
- Active connections at time of seizure are known

### If User is Compromised

As admin:
1. Revoke user immediately: `./scripts/user-revoke.sh username`
2. Monitor for unusual activity
3. Consider rotating server if credentials were extracted
4. Do NOT contact compromised user through normal channels

---

## Checklist

### Server Operator

- [ ] SSH keys only, no password auth
- [ ] Firewall configured
- [ ] System auto-updates enabled
- [ ] Unique user credentials for everyone
- [ ] Backup plan if blocked (new IP ready)
- [ ] Secure distribution channel established

### User

- [ ] Device encrypted
- [ ] App from official source
- [ ] Config imported securely
- [ ] Bundle files deleted after import
- [ ] Knows which protocol to try if one fails
- [ ] Knows how to contact admin securely
