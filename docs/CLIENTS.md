# Client Setup Guide

This guide explains how to connect to MoaV from various devices.

## Quick Reference

| Protocol | iOS | Android | macOS | Windows |
|----------|-----|---------|-------|---------|
| Reality (VLESS) | Shadowrocket, Streisand | v2rayNG, NekoBox | V2rayU, NekoRay | v2rayN, NekoRay |
| Trojan | Shadowrocket | v2rayNG | V2rayU | v2rayN |
| Hysteria2 | Shadowrocket | v2rayNG, Hiddify | Hysteria2 CLI | Hysteria2 CLI |
| WireGuard | WireGuard | WireGuard | WireGuard | WireGuard |

## Protocol Priority

Try these in order. If one doesn't work, try the next:

1. **Reality (VLESS)** - Primary, most reliable (port 443)
2. **Hysteria2** - Fast alternative, uses UDP (port 443)
3. **Trojan** - Backup, uses your domain (port 8443)
4. **WireGuard** - Full VPN mode
5. **DNS Tunnel** - Last resort, very slow (port 53)

---

## iOS Setup

### Shadowrocket (Recommended, $2.99)

The best all-in-one client for iOS.

**Download:** App Store (requires non-IR Apple ID)

**Import via QR Code:**
1. Open Shadowrocket
2. Tap the scanner icon (top-left)
3. Scan the QR code from your bundle (`reality-qr.png`)
4. Tap "Add" to save

**Import via Link:**
1. Copy the link from `reality.txt`
2. Open Shadowrocket
3. It auto-detects and asks to add - tap "Add"

**Import via Config File:**
1. AirDrop or share `reality-singbox.json` to your phone
2. Open with Shadowrocket
3. Import and save

**Connect:**
1. Toggle the switch ON
2. Allow VPN configuration when prompted
3. You're connected!

### Streisand (Free)

Good free alternative.

**Download:** App Store

**Setup:**
1. Open Streisand
2. Tap "+" to add server
3. Choose "Import from clipboard"
4. Paste the link from `reality.txt`

### Hiddify (Free, Iran-focused)

Specifically designed for Iran.

**Download:** App Store or https://hiddify.com

**Setup:**
1. Open Hiddify
2. Tap "Add Profile"
3. Paste or scan your Reality link

---

## Android Setup

### v2rayNG (Recommended, Free)

**Download:**
- Google Play: "v2rayNG"
- GitHub: https://github.com/2dust/v2rayNG/releases

**Import via QR Code:**
1. Open v2rayNG
2. Tap "+" button
3. Select "Import config from QRcode"
4. Scan `reality-qr.png`

**Import via Link:**
1. Copy link from `reality.txt`
2. Open v2rayNG
3. Tap "+" → "Import config from clipboard"

**Connect:**
1. Tap the server to select it
2. Tap the "V" button at bottom to connect
3. Allow VPN permission

### NekoBox (Free, sing-box based)

More advanced, uses sing-box core.

**Download:** GitHub: https://github.com/MatsuriDayo/NekoBoxForAndroid/releases

**Setup:**
1. Open NekoBox
2. Tap "+" → "Import from clipboard"
3. Paste your Reality link
4. Or import `reality-singbox.json` directly

### Hiddify (Free)

**Download:** https://hiddify.com or GitHub

**Setup:**
1. Open Hiddify
2. Add profile via link or QR code

---

## macOS Setup

### V2rayU (Free)

**Download:** https://github.com/yanue/V2rayU/releases

**Setup:**
1. Install and open V2rayU
2. Click menu bar icon → "Import"
3. Paste your Reality link
4. Click "Turn v2ray-core On"

### NekoRay (Free)

Cross-platform GUI client.

**Download:** https://github.com/MatsuriDayo/nekoray/releases

**Setup:**
1. Install and open NekoRay
2. Server → Add profile from clipboard
3. Paste your Reality link

### Command Line (sing-box)

For advanced users:

```bash
# Install sing-box
brew install sing-box

# Run with config
sing-box run -c reality-singbox.json
```

---

## Windows Setup

### v2rayN (Free)

**Download:** https://github.com/2dust/v2rayN/releases

**Setup:**
1. Extract and run v2rayN.exe
2. Click "Server" → "Add [VLESS]"
3. Or paste link: "Server" → "Import from clipboard"
4. Click "System Proxy" → "Set Global Proxy"

### NekoRay (Free)

Same as macOS version.

**Download:** https://github.com/MatsuriDayo/nekoray/releases

---

## WireGuard Setup

Works on all platforms with the official WireGuard app.

### iOS / Android

1. Install "WireGuard" from App Store / Play Store
2. Tap "+" → "Create from QR code"
3. Scan `wireguard-qr.png`
4. Name it (e.g., "MoaV WG")
5. Toggle ON to connect

### macOS / Windows

1. Install WireGuard from https://wireguard.com/install/
2. Click "Import tunnel(s) from file"
3. Select `wireguard.conf`
4. Click "Activate"

---

## Hysteria2 Setup

### Using Shadowrocket / v2rayNG

Both support Hysteria2 links. Import `hysteria2.txt` the same way as Reality.

### Using Hysteria2 CLI

For desktop:

```bash
# Download from https://github.com/apernet/hysteria/releases

# Run with config
./hysteria -c hysteria2.yaml
```

This creates a local proxy on:
- SOCKS5: `127.0.0.1:1080`
- HTTP: `127.0.0.1:8080`

Configure your browser/apps to use this proxy.

---

## DNS Tunnel Setup (Last Resort)

Use this only when all other methods are blocked. It's slow but often works.

See `dnstt-instructions.txt` in your bundle for detailed steps.

**Summary:**
1. Download dnstt-client from https://www.bamsoftware.com/software/dnstt/
2. Run: `dnstt-client -doh https://1.1.1.1/dns-query -pubkey YOUR_KEY t.yourdomain.com 127.0.0.1:1080`
3. Configure apps to use SOCKS5 proxy `127.0.0.1:1080`

---

## Troubleshooting

### "Connection failed" or "Timeout"

1. Check your internet connection
2. Try a different protocol (Reality → Hysteria2 → Trojan)
3. Try a different DNS (1.1.1.1 or 8.8.8.8)
4. Restart the app

### "TLS handshake failed"

- Your ISP might be blocking the connection
- Try Hysteria2 (uses UDP instead of TCP)
- Try DNS tunnel as last resort

### "Certificate error"

- Check that your device's date/time is correct
- Try Reality protocol (doesn't use your domain's cert)

### Very slow connection

- Try Hysteria2 (optimized for lossy networks)
- Check if your ISP is throttling
- DNS tunnel is inherently slow - only for emergencies

### Nothing works

- The server IP might be blocked
- Contact admin for a new server/config
- Try using a different network (mobile data vs WiFi)

---

## Tips for Iran

1. **Keep multiple configs** - Have Reality, Hysteria2, and DNS tunnel ready
2. **Download client apps in advance** - Store APKs offline
3. **Use mobile data** as backup - Sometimes less filtered than home internet
4. **Avoid peak hours** - Filtering can be heavier during protests/events
5. **Update configs quickly** - If server is blocked, switch to backup
