# Supported Protocols

MoaV deploys 13 protocols, each with different stealth characteristics, speed profiles, and network requirements. This diversity ensures that when one protocol is blocked, others remain available.

## Protocol Overview

| Protocol | Port | Stealth | Speed | Domain Required |
|----------|------|---------|-------|-----------------|
| [Reality (VLESS)](#reality-vless) | 443/tcp | Very High | High | No |
| [Trojan](#trojan) | 8443/tcp | High | High | Yes |
| [Hysteria2](#hysteria2) | 443/udp | High | Very High | Yes |
| [CDN (VLESS+WS)](#cdn-vlessws) | 443 via CDN | Very High | Medium | Yes (Cloudflare) |
| [TrustTunnel](#trusttunnel) | 4443/tcp+udp | Very High | High | Yes |
| [WireGuard](#wireguard) | 51820/udp | Medium | Very High | No |
| [AmneziaWG](#amneziawg) | 51821/udp | Very High | High | No |
| [WireGuard (wstunnel)](#wireguard-wstunnel) | 8080/tcp | High | High | No |
| [Telegram MTProxy](#telegram-mtproxy) | 993/tcp | High | Medium | No |
| [dnstt](#dnstt) | 53/udp | Medium | Low | Yes |
| [Slipstream](#slipstream) | 53/udp | Medium | Low-Medium | Yes |
| [Psiphon Conduit](#psiphon-conduit) | dynamic | High | Medium | No |
| [XHTTP (VLESS+XHTTP+Reality)](#xhttp-vlessxhttpreality) | 2096/tcp | Very High | High | No |
| [Tor Snowflake](#tor-snowflake) | dynamic | High | Low | No |
| [MahsaNet](#mahsanet) | — | — | — | No |

## Protocols in Detail

### Reality (VLESS)

**Primary protocol.** VLESS with Reality makes your proxy traffic indistinguishable from a real TLS connection to a legitimate website (e.g., `dl.google.com`). The server presents a genuine TLS certificate from the target site, passing even active probing.

- **Port:** 443/tcp
- **Engine:** [sing-box](https://github.com/SagerNet/sing-box)
- **Clients:** Streisand, Hiddify, v2rayNG, v2rayN, NekoBox

### Trojan

Password-authenticated TLS proxy. Traffic looks like normal HTTPS. Uses your domain's real TLS certificate from Let's Encrypt.

- **Port:** 8443/tcp
- **Engine:** [sing-box](https://github.com/SagerNet/sing-box)
- **Clients:** Streisand, Hiddify, v2rayNG, v2rayN, Shadowrocket

### Hysteria2

QUIC-based protocol optimized for high throughput on lossy networks. Includes built-in obfuscation to bypass QUIC blocking.

- **Port:** 443/udp
- **Engine:** [sing-box](https://github.com/SagerNet/sing-box)
- **Clients:** Streisand, Hiddify, v2rayNG, v2rayN
- **Note:** Requires UDP. Blocked in some censored networks that drop all non-DNS UDP.

### CDN (VLESS+WS)

Routes VLESS traffic through Cloudflare's CDN via WebSocket. When your server's IP is blocked, traffic goes through Cloudflare instead, making it unblockable without blocking all of Cloudflare.

- **Port:** 443 (Cloudflare) → 2082 (origin)
- **Engine:** [sing-box](https://github.com/SagerNet/sing-box)
- **Clients:** Streisand, Hiddify, v2rayNG, v2rayN
- **Requires:** Cloudflare-proxied domain

### TrustTunnel

Modern VPN protocol that looks like regular HTTPS traffic. Supports both HTTP/2 (TCP) and HTTP/3 (QUIC/UDP).

- **Port:** 4443/tcp + 4443/udp
- **Engine:** [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel) (server) / [TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient) (client)
- **Clients:** TrustTunnel app (iOS, Android, macOS, Windows, Linux)

### WireGuard

Fast kernel-level VPN. Simple, audited, and widely supported. Direct UDP connection.

- **Port:** 51820/udp
- **Engine:** [sing-box](https://github.com/SagerNet/sing-box) + [wstunnel](https://github.com/erebe/wstunnel)
- **Clients:** WireGuard app (all platforms)
- **Note:** Easily fingerprinted by DPI. Use AmneziaWG or wstunnel variant in censored networks.

### AmneziaWG

Obfuscated WireGuard variant that defeats Deep Packet Inspection. Adds junk packets, changes handshake timing, and modifies header fields to avoid detection.

- **Port:** 51821/udp
- **Engine:** [amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools)
- **Clients:** AmneziaVPN (iOS, Android, macOS, Windows, Linux)

### WireGuard (wstunnel)

WireGuard tunneled through WebSocket (TCP). Works when UDP is completely blocked.

- **Port:** 8080/tcp
- **Engine:** [wstunnel](https://github.com/erebe/wstunnel) + [sing-box](https://github.com/SagerNet/sing-box)
- **Clients:** WireGuard app + wstunnel binary

### Telegram MTProxy

Telegram-specific proxy with Fake-TLS V2. Emulates real TLS connections, including certificate mimicry and timing simulation. Provides direct access to Telegram when it's blocked.

- **Port:** 993/tcp (IMAPS port for stealth)
- **Engine:** [telemt](https://github.com/telemt/telemt)
- **Clients:** Telegram app (built-in proxy settings)

### dnstt

DNS tunnel that encodes TCP traffic within DNS queries. Extremely hard to block without breaking DNS entirely. Very slow but works as a last resort when almost everything is blocked.

- **Port:** 53/udp
- **Engine:** [dnstt](https://www.bamsoftware.com/software/dnstt/)
- **Requires:** Domain with NS delegation

### Slipstream

QUIC-over-DNS tunnel. Similar to dnstt but uses QUIC for better throughput — typically 1.5-5x faster than dnstt.

- **Port:** 53/udp
- **Engine:** [slipstream](https://github.com/Mygod/slipstream-rust) (Rust) / [pre-built binaries](https://github.com/net2share/slipstream-rust-build/releases)
- **Requires:** Domain with NS delegation

### XHTTP (VLESS+XHTTP+Reality)

**Experimental.** VLESS over XHTTP transport with Reality TLS camouflage, powered by Xray-core. Uses the XHTTP (formerly splithttp) transport for multiplexed HTTP requests, making traffic look like regular web browsing. Reality handles TLS without needing a domain.

- **Port:** 2096/tcp
- **Engine:** [Xray-core](https://github.com/XTLS/Xray-core)
- **Clients:** V2rayNG, Hiddify, Streisand, V2Box, V2rayN, V2rayU, NekoBox
- **Note:** Experimental protocol, opt-in via `ENABLE_XHTTP=false` in `.env`.

### Psiphon Conduit

Bandwidth donation to the Psiphon network. Psiphon users worldwide route through your server. Not a protocol you connect to — it's a way to help others bypass censorship.

- **Engine:** [Psiphon Conduit](https://github.com/Psiphon-Inc/conduit)
- **Clients:** [Psiphon](https://psiphon.ca/) app (iOS, Android, Windows)

### Tor Snowflake

Bandwidth donation to the Tor network. Acts as a Snowflake proxy, helping Tor users in censored regions connect. Like Conduit, this is about helping others.

- **Engine:** [Snowflake](https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake)
- **Clients:** [Tor Browser](https://www.torproject.org/) with Snowflake bridge

### MahsaNet

Config donation to [MahsaServer.com](https://www.mahsaserver.com/), a decentralized VPN config sharing platform for the [Mahsa VPN](https://www.mahsaserver.com/) app. With over 2 million users in Iran, Mahsa VPN connects to donated VPN configurations from servers worldwide. Unlike Conduit and Snowflake (which donate bandwidth), MahsaNet donates your server's VPN config links — Mahsa VPN users then connect directly to your server.

- **Supported protocols:** Reality (VLESS), Hysteria2, Trojan, CDN (VLESS+WS)
- **Clients:** [Mahsa VPN](https://www.mahsaserver.com/) app (Android, iOS)
- **Setup:** Register on MahsaServer.com, get API key, then `moav donate mahsanet`
- **Dashboard:** Donate, list, and manage configs from the Admin Dashboard

## Choosing Protocols

**For censored networks (Iran, China, Russia):**

1. Start with **Reality** — highest stealth, most reliable
2. Add **CDN mode** — works when your server IP is blocked
3. Enable **AmneziaWG** — for full VPN when WireGuard is fingerprinted
4. Enable **DNS tunnels** — last resort when almost everything is blocked

**For general privacy:**

1. **WireGuard** — fastest, simplest
2. **Reality** — when WireGuard is blocked

**For helping others:**

1. **Conduit** — donate bandwidth to Psiphon users
2. **Snowflake** — donate bandwidth to Tor users
3. **MahsaNet** — donate VPN configs to Mahsa VPN users in Iran
