# Architecture

How MoaV is wired together. For protocol-level details see [protocols.md](protocols.md); for CLI behavior see [CLI.md](CLI.md); for DNS-tunnel mechanics see [DNS.md](DNS.md).

## Container topology

Every protocol is one or more containers grouped into a docker-compose **profile**. `moav start` translates `ENABLE_*` flags in `.env` into the set of profiles to bring up (see [CLI → Profile filtering](CLI.md#moav-start)).

```
                      ┌─────────────┐
                      │   .env      │   ENABLE_* flags
                      └──────┬──────┘
                             │
                  ┌──────────▼──────────┐
                  │ derive_enabled_     │  moav.sh
                  │ profiles()          │
                  └──────────┬──────────┘
                             │
        ┌────────────┬───────┼───────┬────────────┬─────────────┐
        ▼            ▼       ▼       ▼            ▼             ▼
   ┌────────┐  ┌─────────┐ ┌────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐
   │ proxy  │  │wireguard│ │xhttp│ │dnstunnel│ │trustnl. │ │ admin    │
   │ (sing- │  │ + wstun.│ │xray │ │dns-rtr+ │ │trust    │ │ admin+   │
   │  box)  │  │         │ │     │ │4 tunnels│ │tunnel   │ │ proxy    │
   └────────┘  └─────────┘ └────┘ └─────────┘ └─────────┘ └──────────┘
   Reality,    WG-over-WS  VLESS+ dnstt/Slip/ HTTP/2 +    FastAPI +
   Trojan,                 Reality MasterDNS/ QUIC (TLS)  HTTP Basic
   Hysteria2,              +XHTTP  XDNS                   auth
   SS-2022,
   CDN VLESS+WS
```

Other profiles: `amneziawg`, `telegram` (telemt), `conduit` (Psiphon), `snowflake` (Tor), `gooserelay` (SOCKS5 over Google Apps Script), `monitoring` (Prometheus + Grafana + exporters), `setup` (bootstrap + GeoIP updater), `client` (local testing).

## DNS-router fan-out

All four DNS tunnels share **port 53** via `dns-router`, a small Go service that fans queries out by subdomain suffix. Each tunnel listens on an internal port; only `dns-router` binds the public port.

```
                         Public 53/udp
                              │
                       ┌──────▼──────┐
                       │ dns-router  │   subdomain-match routing
                       └──┬──┬──┬──┬─┘
            t.*           │  │  │  │       x.*
        ┌──────────┐ s.*  │  │  │  │  m.*  ┌──────────┐
        │  dnstt   ◄──────┘  │  │  └──────►│ masterdns│
        │  :5353   │ ┌──────►│  │          │  :5355   │
        └──────────┘ │       │  └────────► xray :5355
                ┌────▼────┐  │              (XDNS via FinalMask)
                │slipstrm │  └────────► (other tunnels can be added)
                │ :5354   │
                └─────────┘
```

Add a tunnel only by adding its NS record (`t.` / `s.` / `m.` / `x.`); see [DNS → NS Delegations](DNS.md#steps-36-ns-delegations-for-the-four-dns-tunnels). Disabling a tunnel via `ENABLE_*=false` removes its container; `dns-router` just doesn't route to it.

## Bundle generation flow

User credentials and per-protocol configs originate inside the `bootstrap` container, then get rendered into per-user bundles on the host. The split exists because container-side bundle generation can't see the host's `outputs/` mount layout.

```
   moav user add alice
            │
            ▼
   ┌─────────────────────────────────────────────────────────┐
   │ bootstrap container (sing-box-user-add.sh)              │
   │   - generates UUID + per-protocol keys                  │
   │   - writes state/users/alice/credentials.env (volume)   │
   └────────────────────┬────────────────────────────────────┘
                        │  HOST sees state/users/ via volume
                        ▼
   ┌─────────────────────────────────────────────────────────┐
   │ host: generate-single-user.sh                           │
   │   - reads credentials.env + .env                        │
   │   - writes outputs/bundles/alice/{*.txt, *.json, *.png, │
   │     subscription.txt, README.html, ...}                 │
   └─────────────────────────────────────────────────────────┘
```

Bundles split into three groups:

- **V2Ray-compatible** (Reality, Trojan, Hysteria2, SS-2022, CDN, XHTTP) — share-link `.txt`s, QR `.png`s, a single base64 `subscription.txt` importable by MahsaNG / v2rayNG / Hiddify / Streisand.
- **L3 VPNs** (WireGuard, AmneziaWG, TrustTunnel) — `.conf` / `.toml` configs + QR.
- **DNS tunnels** (dnstt, Slipstream, MasterDNS, XDNS) and **donations** (GooseRelay) — text instruction files + protocol-specific config blobs (`xdns-config.json`, `gooserelay-AppsScript.gs` + `gooserelay-client_config.json`, etc.).

`README.html` is a bilingual (EN/FA) collapsible bundle viewer with embedded QR images and one-click subscription import.

## Monitoring stack

The `monitoring` profile is opt-in. When enabled it adds Prometheus + Grafana plus a per-protocol exporter set; each exporter is in the same profile as its target service, not in `monitoring` itself, so disabling a protocol disables its metrics.

```
     ┌─────────────┐
     │  Prometheus │ ←── scrape ──┐
     └──────┬──────┘              │
            │                     │
            │ recording rules     ├─────► clash-exporter  (sing-box Clash API)
            │ (Conduit lifetime)  ├─────► singbox-exporter (log parser)
            ▼                     ├─────► xray-exporter
     ┌─────────────┐              ├─────► telemt-exporter (REST /v1/health)
     │   Grafana   │              ├─────► wireguard-exporter
     │  + dashbds  │              ├─────► amneziawg-exporter
     └─────────────┘              ├─────► snowflake-exporter (Snowflake profile)
            ▲                     ├─────► node-exporter (host)
            │                     └─────► cAdvisor (containers)
            │
        Optional: grafana-proxy → Cloudflare CDN
```

Pre-built dashboards land in `configs/monitoring/grafana/dashboards/`. The Conduit lifetime panels depend on `conduit_lifetime.rules.yml` + the offset-watcher pair — see [Monitoring → Conduit lifetime bandwidth](MONITORING.md#conduit-lifetime-bandwidth).

## See also

- [Setup Guide](SETUP.md) — step-by-step deployment walkthrough
- [DNS Configuration](DNS.md) — NS records, resolver-mode vs direct-mode XDNS, port 53
- [CLI Reference](CLI.md) — every `moav` command, including the profile filtering UX
- [Supported Protocols](protocols.md) — protocol-level cipher, port, and client-compat detail
- [Monitoring](MONITORING.md) — dashboards, Conduit lifetime, GeoIP setup
