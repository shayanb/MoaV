# Client Setup Guide

This guide explains how to connect to MoaV from various devices.

## Quick Reference

| Protocol | iOS | Android | macOS | Windows | Port |
|----------|-----|---------|-------|---------|------|
| Reality (VLESS) | Shadowrocket, Streisand | v2rayNG, NekoBox | V2rayU, NekoRay | v2rayN, NekoRay | 443/tcp |
| Trojan | Shadowrocket | v2rayNG | V2rayU | v2rayN | 8443/tcp |
| Hysteria2 | Shadowrocket | v2rayNG, Hiddify | Hysteria2 CLI | Hysteria2 CLI | 443/udp |
| WireGuard (Direct) | WireGuard | WireGuard | WireGuard | WireGuard | 51820/udp |
| WireGuard (wstunnel) | WireGuard + wstunnel | WireGuard + wstunnel | WireGuard + wstunnel | WireGuard + wstunnel | 8080/tcp |
| DNS Tunnel | dnstt-client | dnstt-client | dnstt-client | dnstt-client | 53/udp |
| Psiphon | Psiphon | Psiphon | Psiphon | Psiphon | Various |

## Protocol Priority

Try these in order. If one doesn't work, try the next:

1. **Reality (VLESS)** - Primary, most reliable (port 443/tcp)
2. **Hysteria2** - Fast alternative, uses QUIC/UDP (port 443/udp)
3. **Trojan** - Backup, uses your domain's TLS cert (port 8443/tcp)
4. **WireGuard (Direct)** - Full VPN mode, simple setup (port 51820/udp)
5. **WireGuard (wstunnel)** - VPN wrapped in WebSocket, for restrictive networks (port 8080/tcp)
6. **Psiphon** - Standalone app, no server needed, uses Psiphon network
7. **DNS Tunnel** - Last resort, very slow but hard to block (port 53/udp)

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

MoaV provides two WireGuard connection methods:

- **Direct Mode** (`wireguard.conf`) - Simple, fast, uses UDP port 51820
- **wstunnel Mode** (`wireguard-wstunnel.conf`) - Wrapped in WebSocket, uses TCP port 8080, for networks that block UDP

### Direct Mode (Recommended)

Use this when UDP traffic is allowed. Simple and fast.

**Your config file:** `wireguard.conf`

#### iOS / Android

1. Install "WireGuard" from App Store / Play Store
2. Tap "+" → "Create from QR code"
3. Scan `wireguard-qr.png`
4. Name it (e.g., "MoaV WG")
5. Toggle ON to connect

#### macOS / Windows / Linux

1. Install WireGuard from https://wireguard.com/install/
2. Click "Import tunnel(s) from file"
3. Select `wireguard.conf`
4. Click "Activate"

### wstunnel Mode (For Restrictive Networks)

Use this when UDP is blocked or heavily throttled. Wraps WireGuard in a WebSocket tunnel.

**Your config file:** `wireguard-wstunnel.conf`

#### Requirements

You need both WireGuard and wstunnel client:
- WireGuard: https://wireguard.com/install/
- wstunnel: https://github.com/erebe/wstunnel/releases

#### macOS / Linux Setup

```bash
# 1. Download wstunnel from GitHub releases
# https://github.com/erebe/wstunnel/releases

# 2. Start wstunnel client (connect to server's port 8080)
wstunnel client -L udp://127.0.0.1:51820:127.0.0.1:51820 ws://YOUR_SERVER_IP:8080

# 3. In another terminal, import WireGuard config
# The config points to 127.0.0.1:51820 (local wstunnel)
sudo wg-quick up ./wireguard-wstunnel.conf
```

#### Windows Setup

1. Download wstunnel.exe from GitHub releases
2. Open PowerShell/CMD and run:
   ```
   wstunnel.exe client -L udp://127.0.0.1:51820:127.0.0.1:51820 ws://YOUR_SERVER_IP:8080
   ```
3. Keep this running
4. Import `wireguard-wstunnel.conf` in WireGuard app
5. Activate the tunnel

#### iOS / Android (Advanced)

wstunnel on mobile requires additional apps or rooted devices. For most users, try other protocols (Reality, Hysteria2) instead if direct WireGuard is blocked.

**Note:** Replace `YOUR_SERVER_IP` with your actual server IP address.

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

## Psiphon Setup

Psiphon is a standalone circumvention tool that doesn't require your own server. It connects to the Psiphon network - a large, distributed system designed for censorship circumvention.

**When to use Psiphon:**
- You don't have access to a MoaV server
- Your MoaV server is blocked
- You need a quick, no-setup solution

### iOS

1. Download "Psiphon" from App Store (requires non-IR Apple ID)
2. Open the app
3. Tap "Start" to connect
4. The app automatically finds working servers

### Android

1. Download from:
   - Google Play: "Psiphon"
   - Direct APK: https://psiphon.ca/en/download.html
2. Open the app
3. Tap "Start" to connect

### Windows

1. Download from https://psiphon.ca/en/download.html
2. Run the executable (no installation needed)
3. Click "Connect"
4. Configure browser to use the local proxy shown in the app

### macOS

1. Download from https://psiphon.ca/en/download.html
2. Open the app
3. Click "Connect"
4. Configure system or browser proxy settings

**Note:** Psiphon uses various protocols internally (SSH, OSSH, etc.) and automatically switches between them to find working connections.

---

## About Psiphon Conduit (Server Feature)

**Note:** Conduit is NOT a client connection method. It's a server-side feature.

If enabled on your MoaV server, Conduit donates a portion of your server's bandwidth to the [Psiphon network](https://psiphon.ca/), helping others in censored regions bypass restrictions. Psiphon is a well-established circumvention tool used by millions.

**For server operators:**
- Enable with the `conduit` profile: `docker compose --profile conduit up -d`
- Configure bandwidth limits via `CONDUIT_BANDWIDTH` in `.env`
- This is optional and purely for helping others

**For clients:**
- You don't connect via Conduit
- Use the other protocols (Reality, Hysteria2, Trojan, WireGuard) to connect to your MoaV server
- If you need Psiphon directly, download their app from https://psiphon.ca/

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

1. **Keep multiple configs** - Have Reality, Hysteria2, WireGuard, and DNS tunnel ready
2. **Download client apps in advance** - Store APKs, wstunnel binaries, and Psiphon offline
3. **Use mobile data** as backup - Sometimes less filtered than home internet
4. **Avoid peak hours** - Filtering can be heavier during protests/events
5. **Update configs quickly** - If server is blocked, switch to backup
6. **Try wstunnel if UDP is blocked** - Some ISPs block UDP; wstunnel wraps WireGuard in TCP/WebSocket
7. **Reality is often best** - Mimics legitimate HTTPS traffic to common sites
8. **Keep Psiphon as backup** - No server needed, works independently of your MoaV setup
