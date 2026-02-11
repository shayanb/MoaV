# MoaV Monitoring Stack

Real-time observability for your MoaV deployment with Grafana dashboards.

<!-- TODO: Screenshot of Grafana dashboard overview showing multiple panels -->

## Overview

The monitoring profile provides:
- **Prometheus** - Time-series database for metrics storage (15-day retention)
- **Grafana** - Beautiful dashboards for visualization
- **Node Exporter** - System metrics (CPU, RAM, disk, network)
- **cAdvisor** - Container metrics per service
- **Clash Exporter** - sing-box proxy metrics via Clash API
- **WireGuard Exporter** - VPN peer and traffic metrics
- **Snowflake Exporter** - Tor donation metrics (people served, bandwidth donated)

## Quick Start

```bash
# Start with monitoring profile
moav start monitoring proxy admin

# Or add to existing deployment
moav start monitoring
```

## Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | `https://your-server:9444` | admin / ADMIN_PASSWORD |

Login with username `admin` and the password you set in your `.env` file (`ADMIN_PASSWORD`).

## Pre-built Dashboards

### MoaV - System

<!-- TODO: Screenshot of System dashboard showing CPU/Memory gauges and graphs -->

System-level metrics from Node Exporter:
- CPU usage (gauge + time series)
- Memory usage (gauge + time series)
- Disk usage
- Network I/O (receive/transmit)
- System load (1m, 5m, 15m)
- Uptime

### MoaV - Containers

<!-- TODO: Screenshot of Containers dashboard showing per-container resource usage -->

Per-container metrics from cAdvisor:
- Running container count
- Total memory and CPU usage
- Memory usage by container (stacked)
- CPU usage by container (stacked)
- Network download/upload by container
- Distribution pie charts
- Summary table with all metrics

### MoaV - sing-box

<!-- TODO: Screenshot of sing-box dashboard showing connections and traffic -->

Proxy metrics via Clash Exporter:
- Active connections
- Total upload/download traffic
- Memory usage
- Connections over time
- Traffic rate (upload/download)
- Connections by inbound type (pie chart)

### MoaV - WireGuard

<!-- TODO: Screenshot of WireGuard dashboard showing peer metrics -->

VPN metrics from WireGuard Exporter:
- Total peers
- Last handshake time
- Total received/sent bytes
- Traffic rate per peer
- Peer details table (name, public key, allowed IPs, traffic, last handshake)

### MoaV - Snowflake

<!-- TODO: Screenshot of Snowflake dashboard showing donation metrics -->

Tor donation metrics from Snowflake Exporter:
- People served (total connections helped)
- Total download bandwidth donated
- Total upload bandwidth donated
- Total bandwidth donated
- Connections over time
- Bandwidth over time

## Configuration

### Port Configuration

```bash
# .env
PORT_GRAFANA=9444    # External Grafana port (default: 9444)
```

### Retention

Prometheus retains data for **15 days** by default. To change this, modify the `--storage.tsdb.retention.time` flag in `docker-compose.yml`:

```yaml
prometheus:
  command:
    - '--storage.tsdb.retention.time=30d'  # 30 days
```

### Enabling/Disabling

```bash
# .env
ENABLE_MONITORING=true   # Set to false to disable
```

## Resource Usage

> **Warning**: The monitoring stack nearly doubles MoaV's resource requirements. While MoaV alone runs on 1 vCPU / 1GB RAM, adding monitoring requires at least **2 vCPU / 2GB RAM** for stable operation.

Approximate additional resources when monitoring is enabled:

| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| Prometheus | 0.1-0.3 cores | 200-500 MB | ~50 MB/day |
| Grafana | 0.1-0.2 cores | 100-200 MB | ~50 MB |
| Node Exporter | <0.1 cores | ~20 MB | - |
| cAdvisor | 0.1-0.3 cores | 50-150 MB | - |
| Clash Exporter | <0.1 cores | ~30 MB | - |
| WireGuard Exporter | <0.1 cores | ~10 MB | - |
| Snowflake Exporter | <0.1 cores | ~10 MB | - |
| **Total** | **~0.5-1 cores** | **~400-900 MB** | **~1 GB/15 days** |

### Minimum Requirements

| Configuration | vCPU | RAM | Notes |
|---------------|------|-----|-------|
| MoaV only | 1 | 1 GB | Bare minimum |
| MoaV + Monitoring | 2 | 2 GB | Recommended (for stats & monitoring) |
| MoaV + Monitoring + All Profiles | 2 | 4 GB | Production recommended |

**If you have only 1GB RAM**, do not enable monitoring - it could cause hangs and crashes.

## Security

- **Prometheus** is internal only (no external port exposed)
- **Grafana** requires authentication via `ADMIN_PASSWORD`
- All exporters expose metrics only to the internal Docker network

## What's Not Included

The following services do not currently expose metrics:

| Service | Reason |
|---------|--------|
| **TrustTunnel** | No metrics API available |
| **dnstt** | No metrics API available |
| **Conduit GeoIP** | Country-level stats remain in admin dashboard |

Container-level metrics (CPU, memory, network) are still available for these services via cAdvisor.

## Troubleshooting

For monitoring-related issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#monitoring-issues).

Common issues covered:
- System hangs after starting monitoring (RAM issues)
- Grafana shows "No Data"
- High memory usage from cAdvisor
- Snowflake metrics showing zeros
- WireGuard exporter not starting

## CLI Commands

```bash
# Start monitoring only
moav start monitoring

# Start with other profiles
moav start monitoring proxy admin

# View monitoring logs
moav logs prometheus
moav logs grafana

# Stop monitoring
moav stop prometheus grafana node-exporter cadvisor clash-exporter
```

## Customization

### Adding Custom Dashboards

Place JSON dashboard files in:
```
configs/monitoring/grafana/provisioning/dashboards/
```

Grafana automatically loads new dashboards within 30 seconds.

### Custom Prometheus Scrape Targets

Edit `configs/monitoring/prometheus.yml` to add new targets:
```yaml
scrape_configs:
  - job_name: 'my-custom-exporter'
    static_configs:
      - targets: ['my-service:9999']
```

Then reload Prometheus:
```bash
docker exec moav-prometheus wget -qO- --post-data='' http://localhost:9091/-/reload
```

## Architecture

```
                    ┌─────────────┐
                    │   Grafana   │ :9444 (external)
                    │ (dashboards)│
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  Prometheus │ :9091 (internal)
                    │ (time-series│
                    │   storage)  │
                    └──────┬──────┘
       ┌───────────────────┼───────────────────┐
       │         │         │         │         │
┌──────▼──────┐ ┌▼────────┐ ┌▼────────┐ ┌▼────────┐ ┌▼────────┐
│ node-export │ │cAdvisor │ │  clash  │ │   wg    │ │snowflake│
│  (system)   │ │(contain)│ │(singbox)│ │(vpn)    │ │ (tor)   │
└─────────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
```
