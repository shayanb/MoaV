#!/usr/bin/env python3
"""
Psiphon Conduit Prometheus Exporter

Parses conduit container logs for [STATS] lines and exposes metrics.
Log format: 2026-02-11 16:37:51 [STATS] Connecting: 27 | Connected: 4 | Up: 195.5 MB | Down: 3.4 GB | Uptime: 13h34m30s
"""

import re
import time
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

# Metrics storage
metrics = {
    'conduit_connecting_clients': 0,
    'conduit_connected_clients': 0,
    'conduit_upload_bytes_total': 0,
    'conduit_download_bytes_total': 0,
    'conduit_uptime_seconds': 0,
    'conduit_last_update_timestamp': 0,
}

# Regex to parse stats line
STATS_PATTERN = re.compile(
    r'\[STATS\]\s*'
    r'Connecting:\s*(\d+)\s*\|\s*'
    r'Connected:\s*(\d+)\s*\|\s*'
    r'Up:\s*([\d.]+)\s*(\w+)\s*\|\s*'
    r'Down:\s*([\d.]+)\s*(\w+)\s*\|\s*'
    r'Uptime:\s*(\S+)'
)

def parse_bytes(value: float, unit: str) -> int:
    """Convert value with unit to bytes."""
    unit = unit.upper()
    multipliers = {
        'B': 1,
        'KB': 1024,
        'MB': 1024 ** 2,
        'GB': 1024 ** 3,
        'TB': 1024 ** 4,
    }
    return int(value * multipliers.get(unit, 1))

def parse_uptime(uptime_str: str) -> int:
    """Parse uptime string like '13h34m30s' to seconds."""
    total_seconds = 0

    # Parse days
    if 'd' in uptime_str:
        match = re.search(r'(\d+)d', uptime_str)
        if match:
            total_seconds += int(match.group(1)) * 86400

    # Parse hours
    if 'h' in uptime_str:
        match = re.search(r'(\d+)h', uptime_str)
        if match:
            total_seconds += int(match.group(1)) * 3600

    # Parse minutes
    if 'm' in uptime_str:
        match = re.search(r'(\d+)m', uptime_str)
        if match:
            total_seconds += int(match.group(1)) * 60

    # Parse seconds
    if 's' in uptime_str:
        match = re.search(r'(\d+)s', uptime_str)
        if match:
            total_seconds += int(match.group(1))

    return total_seconds

def parse_stats_line(line: str) -> bool:
    """Parse a [STATS] line and update metrics. Returns True if parsed."""
    match = STATS_PATTERN.search(line)
    if not match:
        return False

    connecting = int(match.group(1))
    connected = int(match.group(2))
    up_value = float(match.group(3))
    up_unit = match.group(4)
    down_value = float(match.group(5))
    down_unit = match.group(6)
    uptime_str = match.group(7)

    metrics['conduit_connecting_clients'] = connecting
    metrics['conduit_connected_clients'] = connected
    metrics['conduit_upload_bytes_total'] = parse_bytes(up_value, up_unit)
    metrics['conduit_download_bytes_total'] = parse_bytes(down_value, down_unit)
    metrics['conduit_uptime_seconds'] = parse_uptime(uptime_str)
    metrics['conduit_last_update_timestamp'] = time.time()

    return True

def tail_docker_logs():
    """Tail conduit container logs and parse stats."""
    print("Starting log tailer for moav-conduit...")

    while True:
        try:
            # Use docker logs to tail the conduit container
            process = subprocess.Popen(
                ['docker', 'logs', '-f', '--tail', '100', 'moav-conduit'],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            for line in process.stdout:
                if '[STATS]' in line:
                    if parse_stats_line(line):
                        print(f"Updated metrics: connecting={metrics['conduit_connecting_clients']}, "
                              f"connected={metrics['conduit_connected_clients']}, "
                              f"up={metrics['conduit_upload_bytes_total']}, "
                              f"down={metrics['conduit_download_bytes_total']}")

            process.wait()
        except Exception as e:
            print(f"Error tailing logs: {e}")

        # Retry after delay
        print("Log tailer disconnected, retrying in 5s...")
        time.sleep(5)

class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()

            output = []
            output.append('# HELP conduit_connecting_clients Number of clients currently connecting')
            output.append('# TYPE conduit_connecting_clients gauge')
            output.append(f'conduit_connecting_clients {metrics["conduit_connecting_clients"]}')

            output.append('# HELP conduit_connected_clients Number of clients currently connected')
            output.append('# TYPE conduit_connected_clients gauge')
            output.append(f'conduit_connected_clients {metrics["conduit_connected_clients"]}')

            output.append('# HELP conduit_upload_bytes_total Total bytes uploaded')
            output.append('# TYPE conduit_upload_bytes_total counter')
            output.append(f'conduit_upload_bytes_total {metrics["conduit_upload_bytes_total"]}')

            output.append('# HELP conduit_download_bytes_total Total bytes downloaded')
            output.append('# TYPE conduit_download_bytes_total counter')
            output.append(f'conduit_download_bytes_total {metrics["conduit_download_bytes_total"]}')

            output.append('# HELP conduit_uptime_seconds Conduit uptime in seconds')
            output.append('# TYPE conduit_uptime_seconds gauge')
            output.append(f'conduit_uptime_seconds {metrics["conduit_uptime_seconds"]}')

            output.append('# HELP conduit_last_update_timestamp Unix timestamp of last stats update')
            output.append('# TYPE conduit_last_update_timestamp gauge')
            output.append(f'conduit_last_update_timestamp {metrics["conduit_last_update_timestamp"]}')

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
        # Suppress access logs
        pass

def main():
    port = 9101

    # Start log tailer in background thread
    tailer_thread = threading.Thread(target=tail_docker_logs, daemon=True)
    tailer_thread.start()

    # Start HTTP server
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    print(f"Conduit exporter listening on port {port}")
    print(f"Metrics available at http://localhost:{port}/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

if __name__ == '__main__':
    main()
