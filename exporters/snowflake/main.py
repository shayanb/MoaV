#!/usr/bin/env python3
"""
Snowflake Prometheus Exporter (Optimized)

Efficiently parses snowflake proxy logs for metrics.
Uses file watching and incremental parsing to minimize CPU usage.

Log format examples:
  snowflake-proxy 2026/02/11 14:47:43 In the last 1h0m0s, this proxy served 42 connections
  snowflake-proxy 2026/02/11 14:47:43 Total bytes transferred: 123.4 MB down, 456.7 MB up
"""

import re
import os
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

# Metrics storage
metrics = {
    'served_people': 0,
    'download_gb': 0.0,  # Note: This is what the proxy RECEIVES (from Tor/users)
    'upload_gb': 0.0,    # Note: This is what the proxy SENDS (to Tor/users)
    'last_update_timestamp': 0,
}

# Lock for thread safety
metrics_lock = threading.Lock()

# Regex patterns for snowflake log parsing
# "this proxy served 42 connections"
CONNECTIONS_PATTERN = re.compile(r'served (\d+) connections?')
# "Total bytes transferred: 123.4 MB down, 456.7 MB up"
BYTES_PATTERN = re.compile(r'(\d+\.?\d*)\s*(B|KB|MB|GB|TB)\s*down.*?(\d+\.?\d*)\s*(B|KB|MB|GB|TB)\s*up', re.IGNORECASE)
# Alternative format: "123 MB ↓ 456 MB ↑" or similar
ALT_BYTES_PATTERN = re.compile(r'(\d+\.?\d*)\s*(B|KB|MB|GB|TB)\s*[↓⬇]\s*(\d+\.?\d*)\s*(B|KB|MB|GB|TB)\s*[↑⬆]', re.IGNORECASE)


def convert_to_gb(value: float, unit: str) -> float:
    """Convert value with unit to GB."""
    unit = unit.upper()
    multipliers = {
        'B': 1 / (1024 ** 3),
        'KB': 1 / (1024 ** 2),
        'MB': 1 / 1024,
        'GB': 1,
        'TB': 1024,
    }
    return value * multipliers.get(unit, 0)


def parse_log_line(line: str) -> bool:
    """Parse a log line and update metrics. Returns True if metrics updated."""
    updated = False

    # Check for connections count
    conn_match = CONNECTIONS_PATTERN.search(line)
    if conn_match:
        with metrics_lock:
            metrics['served_people'] = int(conn_match.group(1))
            metrics['last_update_timestamp'] = time.time()
        updated = True

    # Check for bytes transferred
    bytes_match = BYTES_PATTERN.search(line)
    if not bytes_match:
        bytes_match = ALT_BYTES_PATTERN.search(line)

    if bytes_match:
        down_value = float(bytes_match.group(1))
        down_unit = bytes_match.group(2)
        up_value = float(bytes_match.group(3))
        up_unit = bytes_match.group(4)

        with metrics_lock:
            # "down" in snowflake logs = bytes the proxy received/downloaded
            # "up" in snowflake logs = bytes the proxy sent/uploaded
            metrics['download_gb'] = convert_to_gb(down_value, down_unit)
            metrics['upload_gb'] = convert_to_gb(up_value, up_unit)
            metrics['last_update_timestamp'] = time.time()
        updated = True

    return updated


def tail_log_file(log_path: str):
    """Efficiently tail the log file using seek."""
    print(f"Starting log tailer for {log_path}...")

    last_position = 0
    last_inode = None

    while True:
        try:
            # Check if file exists
            if not os.path.exists(log_path):
                print(f"Waiting for log file: {log_path}")
                time.sleep(10)
                continue

            # Check if file was rotated (inode changed)
            current_inode = os.stat(log_path).st_ino
            if last_inode is not None and current_inode != last_inode:
                print("Log file rotated, resetting position")
                last_position = 0
            last_inode = current_inode

            # Open file and seek to last position
            with open(log_path, 'r') as f:
                # Check if file was truncated
                f.seek(0, 2)  # Seek to end
                file_size = f.tell()
                if file_size < last_position:
                    print("Log file truncated, resetting position")
                    last_position = 0

                f.seek(last_position)

                # Read new lines
                new_lines = False
                for line in f:
                    new_lines = True
                    if parse_log_line(line):
                        print(f"Updated: served={metrics['served_people']}, "
                              f"down={metrics['download_gb']:.2f}GB, up={metrics['upload_gb']:.2f}GB")

                last_position = f.tell()

            # Sleep longer if no new lines (file hasn't been updated)
            if new_lines:
                time.sleep(1)  # Short sleep when actively receiving data
            else:
                time.sleep(5)  # Longer sleep when idle

        except Exception as e:
            print(f"Error reading log: {e}")
            time.sleep(10)


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()

            output = []

            with metrics_lock:
                output.append('# HELP served_people Total number of connections served by snowflake proxy')
                output.append('# TYPE served_people gauge')
                output.append(f'served_people {metrics["served_people"]}')

                # Note: download_gb = bytes the proxy received (from perspective of proxy)
                # For users behind censorship, this is what they uploaded
                output.append('# HELP download_gb Total GB received by the proxy')
                output.append('# TYPE download_gb gauge')
                output.append(f'download_gb {metrics["download_gb"]:.6f}')

                # Note: upload_gb = bytes the proxy sent (from perspective of proxy)
                # For users behind censorship, this is what they downloaded
                output.append('# HELP upload_gb Total GB sent by the proxy')
                output.append('# TYPE upload_gb gauge')
                output.append(f'upload_gb {metrics["upload_gb"]:.6f}')

                output.append('# HELP snowflake_last_update Unix timestamp of last metrics update')
                output.append('# TYPE snowflake_last_update gauge')
                output.append(f'snowflake_last_update {metrics["last_update_timestamp"]}')

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
    import sys

    # Get log path from argument or use default
    log_path = sys.argv[1] if len(sys.argv) > 1 else '/var/log/snowflake/snowflake.log'
    port = 8080

    # Start log tailer in background thread
    tailer_thread = threading.Thread(target=tail_log_file, args=(log_path,), daemon=True)
    tailer_thread.start()

    # Start HTTP server
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    print(f"Snowflake exporter listening on port {port}")
    print(f"Metrics available at http://localhost:{port}/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
