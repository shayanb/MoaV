#!/usr/bin/env python3
"""
WireGuard Prometheus Exporter

Runs 'wg show' via docker exec and exposes metrics.
"""

import re
import subprocess
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

# Metrics storage
metrics = {
    'peers': {},  # public_key -> {endpoint, latest_handshake, transfer_rx, transfer_tx, allowed_ips}
    'interface': {},  # interface stats
    'last_update': 0,
}

metrics_lock = threading.Lock()

# Peer name mapping (from config file)
peer_names = {}  # public_key -> name


def load_peer_names():
    """Load peer names from wireguard config."""
    global peer_names
    try:
        with open('/etc/wireguard/wg0.conf', 'r') as f:
            content = f.read()

        # Parse config for peer names (comments before [Peer] sections)
        current_name = None
        for line in content.split('\n'):
            line = line.strip()
            if line.startswith('# ') and not line.startswith('# ='):
                current_name = line[2:].strip()
            elif line == '[Peer]':
                pass  # Next line with PublicKey will use current_name
            elif line.startswith('PublicKey') and current_name:
                pubkey = line.split('=', 1)[1].strip()
                peer_names[pubkey] = current_name
                current_name = None
    except Exception as e:
        print(f"Could not load peer names: {e}")


def parse_wg_show(output: str):
    """Parse wg show output into metrics."""
    peers = {}
    interface = {}
    current_peer = None

    for line in output.split('\n'):
        line = line.strip()
        if not line:
            continue

        if line.startswith('interface:'):
            interface['name'] = line.split(':', 1)[1].strip()
        elif line.startswith('public key:'):
            if current_peer is None:
                interface['public_key'] = line.split(':', 1)[1].strip()
        elif line.startswith('listening port:'):
            interface['listening_port'] = int(line.split(':', 1)[1].strip())
        elif line.startswith('peer:'):
            current_peer = line.split(':', 1)[1].strip()
            peers[current_peer] = {
                'endpoint': '',
                'latest_handshake': 0,
                'transfer_rx': 0,
                'transfer_tx': 0,
                'allowed_ips': '',
            }
        elif current_peer:
            if line.startswith('endpoint:'):
                peers[current_peer]['endpoint'] = line.split(':', 1)[1].strip()
            elif line.startswith('allowed ips:'):
                peers[current_peer]['allowed_ips'] = line.split(':', 1)[1].strip()
            elif line.startswith('latest handshake:'):
                # Parse "X minutes, Y seconds ago" or "X seconds ago"
                hs_str = line.split(':', 1)[1].strip()
                peers[current_peer]['latest_handshake'] = parse_handshake_time(hs_str)
            elif line.startswith('transfer:'):
                # Parse "123.45 KiB received, 678.90 KiB sent"
                transfer_str = line.split(':', 1)[1].strip()
                rx, tx = parse_transfer(transfer_str)
                peers[current_peer]['transfer_rx'] = rx
                peers[current_peer]['transfer_tx'] = tx

    return interface, peers


def parse_handshake_time(hs_str: str) -> int:
    """Parse handshake time string to seconds ago."""
    if not hs_str or hs_str == '(none)':
        return 0

    total_seconds = 0
    # Match patterns like "1 minute, 30 seconds ago" or "45 seconds ago"
    parts = re.findall(r'(\d+)\s*(second|minute|hour|day)s?', hs_str)
    for value, unit in parts:
        value = int(value)
        if 'second' in unit:
            total_seconds += value
        elif 'minute' in unit:
            total_seconds += value * 60
        elif 'hour' in unit:
            total_seconds += value * 3600
        elif 'day' in unit:
            total_seconds += value * 86400

    return int(time.time()) - total_seconds if total_seconds else 0


def parse_transfer(transfer_str: str) -> tuple:
    """Parse transfer string to bytes (rx, tx)."""
    rx_bytes = 0
    tx_bytes = 0

    # Match "123.45 KiB received, 678.90 MiB sent"
    rx_match = re.search(r'([\d.]+)\s*(B|KiB|MiB|GiB|TiB)\s*received', transfer_str)
    tx_match = re.search(r'([\d.]+)\s*(B|KiB|MiB|GiB|TiB)\s*sent', transfer_str)

    multipliers = {'B': 1, 'KiB': 1024, 'MiB': 1024**2, 'GiB': 1024**3, 'TiB': 1024**4}

    if rx_match:
        rx_bytes = int(float(rx_match.group(1)) * multipliers.get(rx_match.group(2), 1))
    if tx_match:
        tx_bytes = int(float(tx_match.group(1)) * multipliers.get(tx_match.group(2), 1))

    return rx_bytes, tx_bytes


def collect_metrics():
    """Run wg show and collect metrics."""
    try:
        result = subprocess.run(
            ['docker', 'exec', 'moav-wireguard', 'wg', 'show'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            print(f"wg show failed: {result.stderr}")
            return

        interface, peers = parse_wg_show(result.stdout)

        with metrics_lock:
            metrics['interface'] = interface
            metrics['peers'] = peers
            metrics['last_update'] = time.time()

        print(f"Updated: {len(peers)} peers")

    except Exception as e:
        print(f"Error collecting metrics: {e}")


def metrics_collector():
    """Background thread to collect metrics periodically."""
    while True:
        collect_metrics()
        time.sleep(15)  # Collect every 15 seconds


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()

            output = []

            with metrics_lock:
                # Interface info
                if metrics['interface'].get('name'):
                    output.append('# HELP wireguard_interface_info WireGuard interface information')
                    output.append('# TYPE wireguard_interface_info gauge')
                    output.append(f'wireguard_interface_info{{interface="{metrics["interface"].get("name", "")}"}} 1')

                # Peer count
                output.append('# HELP wireguard_peers_total Total number of configured peers')
                output.append('# TYPE wireguard_peers_total gauge')
                output.append(f'wireguard_peers_total {len(metrics["peers"])}')

                # Per-peer metrics
                output.append('# HELP wireguard_peer_transfer_rx_bytes Bytes received from peer')
                output.append('# TYPE wireguard_peer_transfer_rx_bytes counter')

                output.append('# HELP wireguard_peer_transfer_tx_bytes Bytes sent to peer')
                output.append('# TYPE wireguard_peer_transfer_tx_bytes counter')

                output.append('# HELP wireguard_peer_latest_handshake_seconds UNIX timestamp of last handshake')
                output.append('# TYPE wireguard_peer_latest_handshake_seconds gauge')

                output.append('# HELP wireguard_peer_active Whether peer has recent handshake (1=active)')
                output.append('# TYPE wireguard_peer_active gauge')

                for pubkey, peer in metrics['peers'].items():
                    # Get friendly name if available
                    name = peer_names.get(pubkey, pubkey[:8] + '...')
                    labels = f'public_key="{pubkey}",name="{name}"'

                    output.append(f'wireguard_peer_transfer_rx_bytes{{{labels}}} {peer["transfer_rx"]}')
                    output.append(f'wireguard_peer_transfer_tx_bytes{{{labels}}} {peer["transfer_tx"]}')

                    if peer['latest_handshake'] > 0:
                        output.append(f'wireguard_peer_latest_handshake_seconds{{{labels}}} {peer["latest_handshake"]}')
                        # Active if handshake within last 3 minutes
                        is_active = 1 if (time.time() - peer['latest_handshake']) < 180 else 0
                        output.append(f'wireguard_peer_active{{{labels}}} {is_active}')
                    else:
                        output.append(f'wireguard_peer_latest_handshake_seconds{{{labels}}} 0')
                        output.append(f'wireguard_peer_active{{{labels}}} 0')

                # Last update timestamp
                output.append('# HELP wireguard_last_update_timestamp Unix timestamp of last successful update')
                output.append('# TYPE wireguard_last_update_timestamp gauge')
                output.append(f'wireguard_last_update_timestamp {metrics["last_update"]}')

            self.wfile.write('\n'.join(output).encode())

        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def main():
    port = 9586

    # Load peer names from config
    load_peer_names()
    print(f"Loaded {len(peer_names)} peer names from config")

    # Initial collection
    collect_metrics()

    # Start background collector
    collector_thread = threading.Thread(target=metrics_collector, daemon=True)
    collector_thread.start()

    # Start HTTP server
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    print(f"WireGuard exporter listening on port {port}")
    print(f"Metrics available at http://localhost:{port}/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
