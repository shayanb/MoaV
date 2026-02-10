# MoaV Monitoring Stack

Real-time observability for your MoaV deployment with Grafana dashboards.

## Overview

The monitoring profile provides:
- **Prometheus** - Time-series database for metrics storage (15-day retention)
- **Grafana** - Beautiful dashboards for visualization
- **Node Exporter** - System metrics (CPU, RAM, disk, network)
- **cAdvisor** - Container metrics per service
- **Clash Exporter** - sing-box proxy metrics via Clash API
- **WireGuard Exporter** - VPN peer and traffic metrics
- **Snowflake Metrics** - Native Tor Snowflake statistics

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
System-level metrics from Node Exporter:
- CPU usage (gauge + time series)
- Memory usage (gauge + time series)
- Disk usage
- Network I/O (receive/transmit)
- System load (1m, 5m, 15m)
- Uptime

### MoaV - Containers
Per-container metrics from cAdvisor:
- Running container count
- Total memory and CPU usage
- Memory usage by container (stacked)
- CPU usage by container (stacked)
- Network receive by container
- Network transmit by container

### MoaV - sing-box
Proxy metrics via Clash Exporter:
- Active connections
- Total upload/download traffic
- Memory usage
- Connections over time
- Traffic rate (upload/download)
- Connections by inbound type (pie chart)

### MoaV - WireGuard
VPN metrics from WireGuard Exporter:
- Total peers
- Last handshake time
- Total received/sent bytes
- Traffic rate per peer
- Peer details table (name, public key, allowed IPs, traffic, last handshake)

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

Approximate additional resources when monitoring is enabled:

| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| Prometheus | 0.1-0.3 cores | 200-500 MB | ~50 MB/day |
| Grafana | 0.1-0.2 cores | 100-200 MB | ~50 MB |
| Node Exporter | <0.1 cores | ~20 MB | - |
| cAdvisor | 0.1-0.3 cores | 50-150 MB | - |
| Clash Exporter | <0.1 cores | ~30 MB | - |
| WireGuard Exporter | <0.1 cores | ~10 MB | - |
| **Total** | **~0.5-1 cores** | **~400-900 MB** | **~1 GB/15 days** |

**Recommended minimum**: 2 vCPU, 2 GB RAM when running monitoring alongside other services.

## Security

- **Prometheus** is internal only (no external port exposed)
- **Grafana** requires authentication via `ADMIN_PASSWORD`
- All exporters expose metrics only to the internal Docker network
- Snowflake metrics use host networking but only listen on localhost

## What's Not Included

The following services do not currently expose metrics:

| Service | Reason |
|---------|--------|
| **TrustTunnel** | No metrics API available |
| **dnstt** | No metrics API available |
| **Conduit GeoIP** | Country-level stats remain in admin dashboard |

Container-level metrics (CPU, memory, network) are still available for these services via cAdvisor.

## Troubleshooting

### Grafana shows "No Data"

1. Check Prometheus is running:
   ```bash
   docker logs moav-prometheus
   ```

2. Verify targets are up - access Prometheus internally:
   ```bash
   docker exec moav-prometheus wget -qO- http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
   ```

3. Ensure services are on the same Docker network (`moav_net`)

### High memory usage from cAdvisor

Limit cAdvisor resources in `docker-compose.yml`:
```yaml
cadvisor:
  deploy:
    resources:
      limits:
        memory: 256M
```

### Snowflake metrics not showing

Snowflake uses host networking, so Prometheus accesses it via `host.docker.internal:9999`. If metrics aren't appearing:

1. Check Snowflake exposes metrics:
   ```bash
   curl http://localhost:9999/internal/metrics
   ```

2. Verify Docker supports `host.docker.internal`:
   ```bash
   docker run --rm alpine ping -c1 host.docker.internal
   ```

### WireGuard exporter not starting

The exporter needs read access to WireGuard config. Check:
```bash
docker logs moav-wireguard-exporter
ls -la configs/wireguard/wg0.conf
```

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
moav stop prometheus grafana node-exporter cadvisor clash-exporter wireguard-exporter
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
docker exec moav-prometheus kill -HUP 1
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
           ┌───────────────┼───────────────┐
           │               │               │
    ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
    │ node-export │ │  cAdvisor   │ │clash-export │
    │  (system)   │ │ (containers)│ │ (sing-box)  │
    └─────────────┘ └─────────────┘ └─────────────┘
           │               │               │
    ┌──────▼──────┐ ┌──────▼──────┐
    │  wg-export  │ │  snowflake  │
    │ (wireguard) │ │  (native)   │
    └─────────────┘ └─────────────┘
```
