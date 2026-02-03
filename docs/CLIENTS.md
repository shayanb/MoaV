# Client Setup Guide

This guide explains how to connect to MoaV from various devices.

## Table of Contents

- [Quick Reference](#quick-reference)
  - [Protocol Support](#protocol-support-by-port)
  - [Client Apps](#client-apps)

- [Protocol Priority](#protocol-priority)
- [MoaV Client Container (Linux/Docker)](#moav-client-container-linuxdocker)
- [iOS Setup](#ios-setup)
- [Android Setup](#android-setup)
- [macOS Setup](#macos-setup)
- [Windows Setup](#windows-setup)
- [WireGuard Setup](#wireguard-setup)
- [Hysteria2 Setup](#hysteria2-setup)
- [DNS Tunnel Setup (Last Resort)](#dns-tunnel-setup-last-resort)
- [Paqet Setup (Last Resort)](#paqet-setup-last-resort)
- [Psiphon Setup](#psiphon-setup)
- [About Psiphon Conduit (Server Feature)](#about-psiphon-conduit-server-feature)
- [About Tor Snowflake (Server Feature)](#about-tor-snowflake-server-feature)
- [Troubleshooting](#troubleshooting)
- [Tips for Highly Censored Environments](#tips-for-highly-censored-environments)

---

## Quick Reference

### Protocol Support by Port

| Protocol | Port | Description |
|----------|------|-------------|
| [Reality (VLESS)](https://github.com/XTLS/REALITY) | 443/tcp | TLS camouflage, virtually undetectable |
| [Trojan](https://trojan-gfw.github.io/trojan/) | 8443/tcp | HTTPS mimicry, battle-tested |
| [Hysteria2](https://v2.hysteria.network/) | 443/udp | QUIC-based, fast on lossy networks |
| [WireGuard](https://www.wireguard.com/) (Direct) | 51820/udp | Full VPN mode, simple setup |
| [WireGuard](https://www.wireguard.com/) + [wstunnel](https://github.com/erebe/wstunnel) | 8080/tcp | VPN wrapped in WebSocket |
| [DNS Tunnel](https://www.bamsoftware.com/software/dnstt/) | 53/udp | Last resort, slow but hard to block |
| [Paqet](https://github.com/hanselime/paqet) | 9999/tcp | Raw packet proxy, bypasses OS firewall |
| [Psiphon](https://psiphon.ca/) | Various | Standalone app, uses Psiphon network |
| [Tor](https://www.torproject.org/) (Snowflake) | Various | Uses Tor network |

### Client Apps

#### iOS

| App | Protocols | Link |
|-----|-----------|------|
| [Shadowrocket](https://apps.apple.com/us/app/shadowrocket/id932747118) | VLESS, VMess, Trojan, Hysteria2, WireGuard | [App Store ($2.99)](https://apps.apple.com/us/app/shadowrocket/id932747118) |
| [Streisand](https://apps.apple.com/us/app/streisand/id6450534064) | VLESS/Reality, VMess, Trojan, Hysteria2, WireGuard | [App Store (Free)](https://apps.apple.com/us/app/streisand/id6450534064) |
| [Hiddify](https://apps.apple.com/us/app/hiddify-proxy-vpn/id6596777532) | VLESS, VMess, Hysteria2, Trojan, Reality, SSH | [App Store (Free)](https://apps.apple.com/us/app/hiddify-proxy-vpn/id6596777532) |
| [V2Box](https://apps.apple.com/ca/app/v2box-v2ray-client/id6446814690) | VLESS, VMess, Trojan, Hysteria2, Reality | [App Store](https://apps.apple.com/ca/app/v2box-v2ray-client/id6446814690) |
| [sing-box](https://apps.apple.com/us/app/sing-box-vt/id6673731168) | VLESS, VMess, Trojan, Hysteria2, WireGuard | [App Store (Free)](https://apps.apple.com/us/app/sing-box-vt/id6673731168) |
| [Loon](https://apps.apple.com/us/app/loon/id1373567447) | VLESS/Reality, Hysteria2, Trojan, WireGuard | [App Store](https://apps.apple.com/us/app/loon/id1373567447) |
| [Pharos Pro](https://apps.apple.com/us/app/pharos-pro/id1456610173) | VLESS, Hysteria2, Trojan, TUIC | [App Store ($2.99)](https://apps.apple.com/us/app/pharos-pro/id1456610173) |
| [Onion Browser](https://apps.apple.com/us/app/onion-browser/id519296448) | Tor | [App Store (Free)](https://apps.apple.com/us/app/onion-browser/id519296448) |
| [Psiphon](https://apps.apple.com/us/app/psiphon-vpn-freedom-online/id1276263909) | Psiphon | [App Store (Free)](https://apps.apple.com/us/app/psiphon-vpn-freedom-online/id1276263909) |
| [WireGuard](https://apps.apple.com/us/app/wireguard/id1441195209) | WireGuard | [App Store (Free)](https://apps.apple.com/us/app/wireguard/id1441195209) |

#### Android

| App | Protocols | Link |
|-----|-----------|------|
| [v2rayNG](https://github.com/2dust/v2rayNG) | VLESS, VMess, Trojan, Shadowsocks | [GitHub](https://github.com/2dust/v2rayNG/releases) |
| [Hiddify](https://hiddify.com/) | VLESS, VMess, Hysteria2, Trojan, Reality, SSH | [GitHub](https://github.com/hiddify/hiddify-app/releases) |
| [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) | VLESS, VMess, Trojan, Hysteria2 (sing-box) | [GitHub](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases) |
| [V2Box](https://play.google.com/store/apps/details?id=dev.hexasoftware.v2box) | VLESS, VMess, Trojan, Hysteria2, Reality | [Play Store](https://play.google.com/store/apps/details?id=dev.hexasoftware.v2box) |
| [sing-box](https://github.com/SagerNet/sing-box) | VLESS, VMess, Trojan, Hysteria2, WireGuard | [F-Droid](https://f-droid.org/packages/io.nekohasekai.sfa/) / [GitHub](https://github.com/SagerNet/sing-box/releases) |
| [HTTP Injector](https://play.google.com/store/apps/details?id=com.evozi.injector) | VLESS, Hysteria, DNS Tunnel, WireGuard, SSH | [Play Store](https://play.google.com/store/apps/details?id=com.evozi.injector) |
| [Clash Meta](https://github.com/MetaCubeX/ClashMetaForAndroid) | VLESS, VMess, Hysteria2, Trojan | [GitHub](https://github.com/MetaCubeX/ClashMetaForAndroid/releases) |
| [Tor Browser](https://www.torproject.org/download/) | Tor | [Play Store](https://play.google.com/store/apps/details?id=org.torproject.torbrowser) / [Official](https://www.torproject.org/download/) |
| [Psiphon](https://psiphon.ca/) | Psiphon | [Play Store](https://play.google.com/store/apps/details?id=com.psiphon3) / [APK](https://psiphon.ca/en/download.html) |
| [WireGuard](https://www.wireguard.com/) | WireGuard | [Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android) |

#### Windows

| App | Protocols | Link |
|-----|-----------|------|
| [v2rayN](https://github.com/2dust/v2rayN) | VLESS, VMess, Trojan, Hysteria2, TUIC | [GitHub](https://github.com/2dust/v2rayN/releases) |
| [Hiddify](https://hiddify.com/) | VLESS, VMess, Hysteria2, Trojan, Reality | [GitHub](https://github.com/hiddify/hiddify-app/releases) |
| [NekoRay](https://github.com/MatsuriDayo/nekoray) | VLESS, VMess, Trojan, Hysteria2 (sing-box) | [GitHub](https://github.com/MatsuriDayo/nekoray/releases) ¹ |
| [Mihomo Party](https://github.com/mihomo-party-org/mihomo-party) | VLESS, VMess, Hysteria2, Trojan | [GitHub](https://github.com/mihomo-party-org/mihomo-party/releases) |
| [Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev) | VLESS, VMess, Hysteria2, Trojan | [GitHub](https://github.com/clash-verge-rev/clash-verge-rev/releases) |
| [Tor Browser](https://www.torproject.org/download/) | Tor | [Official](https://www.torproject.org/download/) |
| [Psiphon](https://psiphon.ca/) | Psiphon | [Official](https://psiphon.ca/en/download.html) |
| [WireGuard](https://www.wireguard.com/) | WireGuard | [Official](https://www.wireguard.com/install/) |

#### macOS

| App | Protocols | Link |
|-----|-----------|------|
| [Streisand](https://apps.apple.com/us/app/streisand/id6450534064) | VLESS/Reality, VMess, Trojan, Hysteria2, WireGuard | [App Store (Free)](https://apps.apple.com/us/app/streisand/id6450534064) |
| [v2rayN](https://github.com/2dust/v2rayN) | VLESS, VMess, Trojan, Hysteria2 | [GitHub](https://github.com/2dust/v2rayN/releases) |
| [Hiddify](https://hiddify.com/) | VLESS, VMess, Hysteria2, Trojan, Reality | [GitHub](https://github.com/hiddify/hiddify-app/releases) |
| [NekoRay](https://github.com/MatsuriDayo/nekoray) | VLESS, VMess, Trojan, Hysteria2 (sing-box) | [GitHub](https://github.com/MatsuriDayo/nekoray/releases) ¹ |
| [Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev) | VLESS, VMess, Hysteria2, Trojan | [GitHub](https://github.com/clash-verge-rev/clash-verge-rev/releases) |
| [sing-box](https://sing-box.sagernet.org/) | VLESS, VMess, Trojan, Hysteria2, WireGuard | [Homebrew](https://formulae.brew.sh/formula/sing-box) / [GitHub](https://github.com/SagerNet/sing-box) |
| [Tor Browser](https://www.torproject.org/download/) | Tor | [Official](https://www.torproject.org/download/) |
| [Psiphon](https://psiphon.ca/) | Psiphon | [App Store (Apple Silicon)](https://apps.apple.com/us/app/psiphon/id1276263909) |
| [WireGuard](https://www.wireguard.com/) | WireGuard | [App Store](https://apps.apple.com/us/app/wireguard/id1451685025) |

#### Linux

| App | Protocols | Link |
|-----|-----------|------|
| [Hiddify](https://hiddify.com/) | VLESS, VMess, Hysteria2, Trojan, Reality | [GitHub](https://github.com/hiddify/hiddify-app/releases) |
| [v2rayN](https://github.com/2dust/v2rayN) | VLESS, VMess, Trojan, Hysteria2 | [GitHub](https://github.com/2dust/v2rayN/releases) |
| [sing-box](https://sing-box.sagernet.org/) | VLESS, VMess, Trojan, Hysteria2, WireGuard, DNS | [GitHub](https://github.com/SagerNet/sing-box) |
| [Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev) | VLESS, VMess, Hysteria2, Trojan | [GitHub](https://github.com/clash-verge-rev/clash-verge-rev/releases) |
| [Mihomo Party](https://github.com/mihomo-party-org/mihomo-party) | VLESS, VMess, Hysteria2, Trojan | [GitHub](https://github.com/mihomo-party-org/mihomo-party/releases) |
| [Tor Browser](https://www.torproject.org/download/) | Tor | [Official](https://www.torproject.org/download/) |
| [WireGuard](https://www.wireguard.com/) | WireGuard | [Official](https://www.wireguard.com/install/) |
| **MoaV Client** | All MoaV protocols | Built-in (Docker) |

¹ NekoRay: Repository notes it is no longer actively maintained. Consider alternatives like Hiddify or Clash Verge.

**Notes:**
- Psiphon is not available via MoaV client - use [official Psiphon apps](https://psiphon.ca/download.html)
- iOS has no official Tor Browser; use [Onion Browser](https://apps.apple.com/us/app/onion-browser/id519296448) instead (Tor Project recommended)
- Psiphon for Linux is not officially available

## Protocol Priority

Try these in order. If one doesn't work, try the next:

1. **Reality (VLESS)** - Primary, most reliable (port 443/tcp)
2. **Hysteria2** - Fast alternative, uses QUIC/UDP (port 443/udp)
3. **Trojan** - Backup, uses your domain's TLS cert (port 8443/tcp)
4. **WireGuard (Direct)** - Full VPN mode, simple setup (port 51820/udp)
5. **WireGuard (wstunnel)** - VPN wrapped in WebSocket, for restrictive networks (port 8080/tcp)
6. **Tor (Snowflake)** - Uses Tor network (no server needed)
7. **DNS Tunnel** - Last resort, very slow but hard to block (port 53/udp)
8. **Paqet** - Raw packet proxy, bypasses OS firewall (port 9999/tcp, requires root)
9. **Psiphon** - Standalone app only, uses Psiphon network (not via MoaV client)

---

## MoaV Client Container (Linux/Docker)

MoaV includes a built-in multi-protocol client container. This is useful for:
- Testing server connectivity from another machine
- Running MoaV as a client on Linux servers/desktops
- Automated testing in CI/CD pipelines
- Connecting through your MoaV server from a Docker environment

### Testing Connectivity

Test all protocols for a user to verify server is working:

```bash
# Test all protocols for user1
moav test user1

# Output results as JSON (for scripts/automation)
moav test user1 --json
```

The test checks: Reality, Trojan, Hysteria2, WireGuard (config validation), dnstt, and Paqet.

**Sample output:**
```
═══════════════════════════════════════════════════════════════
  MoaV Connection Test Results
═══════════════════════════════════════════════════════════════

  Config: /bundles/user1
  Time:   Wed Jan 28 10:30:00 UTC 2026

───────────────────────────────────────────────────────────────
  ✓ reality      Connected via VLESS/Reality
  ✓ trojan       Connected via Trojan
  ✓ hysteria2    Connected via Hysteria2
  ✓ wireguard    Config valid, endpoint reachable
  ○ dnstt        No dnstt config found in bundle

═══════════════════════════════════════════════════════════════
```

### Client Mode (Connect Through Server)

Run MoaV as a local proxy client:

```bash
# Auto-detect best working protocol
moav client connect user1

# Force a specific protocol
moav client connect user1 --protocol reality
moav client connect user1 --protocol hysteria2
moav client connect user1 --protocol trojan
moav client connect user1 --protocol wireguard
moav client connect user1 --protocol dnstt
moav client connect user1 --protocol tor
```

**Local proxy endpoints:**
- SOCKS5: `127.0.0.1:1080`
- HTTP: `127.0.0.1:8080`

Configure these ports in `.env`:
```bash
CLIENT_SOCKS_PORT=1080
CLIENT_HTTP_PORT=8080
```

**Protocol fallback order (auto mode):**
1. Reality (VLESS) - Most reliable
2. Hysteria2 - Fast, UDP-based
3. Trojan - TLS-based backup
4. WireGuard - Full VPN
5. Tor (Snowflake) - Uses Tor network (no server needed)
6. dnstt - Last resort, slow but hard to block

> **Note:** Psiphon is not available via MoaV client. Use the [official Psiphon apps](https://psiphon.ca/en/download.html) instead.

### Building the Client Image

The client image is built automatically when running `moav test` or `moav client`. To build manually:

```bash
moav client build
```

### Technical Details

The client container includes:
- **sing-box** - Handles Reality, Trojan, Hysteria2
- **wireguard-go** - Userspace WireGuard implementation
- **wstunnel** - WebSocket tunnel for WireGuard
- **dnstt-client** - DNS tunnel client
- **paqet** - Raw packet proxy (requires privileged mode)
- **snowflake-client** - Tor Snowflake pluggable transport
- **tor** - Tor daemon

**Container capabilities:**
- Runs without privileged mode for most protocols
- WireGuard requires `--cap-add NET_ADMIN` for full functionality
- Uses Alpine Linux for minimal image size

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

## Paqet Setup (Last Resort)

Paqet is a raw packet-level proxy that bypasses the OS TCP/IP stack using pcap. Use this when:
- Other protocols are actively blocked
- Deep packet inspection is defeating standard protocols
- You need to operate below the firewall layer

**Requirements:**
- Root/administrator privileges
- libpcap installed
- NOT OpenVZ/LXC container (requires KVM, Xen, or bare metal)

### Installation

**Linux:**
```bash
# Install libpcap
sudo apt install libpcap-dev  # Debian/Ubuntu
sudo dnf install libpcap-devel  # Fedora/RHEL

# Download paqet
# From: https://github.com/hanselime/paqet/releases
# Or build from source:
go install github.com/hanselime/paqet/cmd/paqet@latest
```

**macOS:**
```bash
# libpcap is pre-installed
# Download paqet binary or build from source
```

**Windows:**
1. Install [Npcap](https://npcap.com) (required for raw packet access)
2. Download paqet.exe from releases

### Configuration

Your bundle contains `paqet-client.yaml` and `paqet-instructions.txt`.

**You must fill in YOUR network details:**

1. Find your network interface:
   ```bash
   # Linux
   ip a
   # macOS
   ifconfig
   # Windows
   Get-NetAdapter
   ```

2. Find your local IP:
   ```bash
   # Linux
   ip -4 addr show eth0 | grep inet
   # macOS
   ifconfig en0 | grep inet
   ```

3. Find your gateway/router MAC:
   ```bash
   # Find gateway IP
   ip route | grep default  # Linux
   netstat -rn | grep default  # macOS

   # Get MAC for gateway IP
   arp -n GATEWAY_IP
   ```

4. Edit `paqet-client.yaml`:
   ```yaml
   network:
     interface: "eth0"           # Your interface
     ipv4:
       addr: "192.168.1.100:0"   # Your local IP
       router_mac: "aa:bb:cc:dd:ee:ff"  # Your gateway MAC
   ```

### Running

```bash
# Linux/macOS (requires root)
sudo paqet run -c paqet-client.yaml

# Windows (run as Administrator)
paqet.exe run -c paqet-client.yaml
```

This creates a SOCKS5 proxy at `127.0.0.1:1080`.

### Troubleshooting

- **"permission denied"** - Run as root/admin
- **"no route to host"** - Check gateway MAC address
- **"pcap error"** - Install libpcap, verify interface name
- **OpenVZ/LXC error** - Paqet requires KVM or bare metal (raw sockets not supported in containers)

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

## About Tor Snowflake (Server Feature)

**Note:** Snowflake is NOT a client connection method. It's a server-side feature.

If enabled on your MoaV server, Snowflake acts as a proxy for the [Tor network](https://www.torproject.org/), helping users in censored regions connect to Tor. Snowflake is part of Tor's pluggable transports system.

**For server operators:**
- Enable with the `snowflake` profile: `docker compose --profile snowflake up -d`
- Configure limits in `.env`:
  - `SNOWFLAKE_BANDWIDTH=50` - Mbps limit (default: 50)
  - `SNOWFLAKE_CAPACITY=20` - Max concurrent clients (default: 20)
- This is optional and purely for helping others

**For clients:**
- You don't connect via Snowflake directly
- If you need Tor, download the Tor Browser from https://www.torproject.org/
- Tor Browser will automatically use Snowflake bridges when needed

**Can I run both Conduit and Snowflake?**
Yes! Both services can run simultaneously without conflicts. They donate bandwidth to different networks (Psiphon and Tor respectively).

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

## Tips for Highly Censored Environments

1. **Keep multiple configs** - Have Reality, Hysteria2, WireGuard, and DNS tunnel ready
2. **Download client apps in advance** - Store APKs, wstunnel binaries, and Psiphon offline
3. **Use mobile data** as backup - Sometimes less filtered than home internet
4. **Avoid peak hours** - Filtering can be heavier during protests/events
5. **Update configs quickly** - If server is blocked, switch to backup
6. **Try wstunnel if UDP is blocked** - Some ISPs block UDP; wstunnel wraps WireGuard in TCP/WebSocket
7. **Reality is often best** - Mimics legitimate HTTPS traffic to common sites
8. **Keep Psiphon as backup** - No server needed, works independently of your MoaV setup
