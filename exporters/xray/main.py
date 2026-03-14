#!/usr/bin/env python3
"""
Xray User Prometheus Exporter

Parses Xray container logs for connection metrics and queries the
Xray Stats API (gRPC via dokodemo-door) for per-user traffic data.
"""

import re
import time
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from collections import defaultdict

# Metrics storage
user_connections = defaultdict(int)  # user -> total connections
user_last_seen = {}  # user -> timestamp
active_users = set()  # users seen in last 5 minutes
user_upload = defaultdict(int)  # user -> upload bytes (cumulative)
user_download = defaultdict(int)  # user -> download bytes (cumulative)

# Lock for thread safety
metrics_lock = threading.Lock()

# Regex to parse Xray access log lines
EMAIL_PATTERN = re.compile(r'email:\s*(\S+?)@moav')
BRACKET_PATTERN = re.compile(r'\[([^\]]+?)@moav\]')

# Regex to parse xray api statsquery output (protobuf text format)
# stat: {
#   name: "user>>>username>>>traffic>>>uplink"
#   value: 12345
# }
STAT_NAME_PATTERN = re.compile(r'name:\s*"([^"]+)"')
STAT_VALUE_PATTERN = re.compile(r'value:\s*(\d+)')

# Active window in seconds (5 minutes)
ACTIVE_WINDOW = 300

# Stats query interval (seconds)
STATS_INTERVAL = 15


def parse_log_line(line: str) -> bool:
    """Parse a log line and update metrics. Returns True if parsed."""
    if 'accepted' not in line:
        return False

    match = EMAIL_PATTERN.search(line)
    if not match:
        match = BRACKET_PATTERN.search(line)
    if not match:
        return False

    username = match.group(1)
    now = time.time()

    with metrics_lock:
        user_connections[username] += 1
        user_last_seen[username] = now

    return True


def update_active_users():
    """Update the set of active users based on last seen time."""
    global active_users
    now = time.time()
    cutoff = now - ACTIVE_WINDOW

    with metrics_lock:
        active_users = {
            user for user, last_seen in user_last_seen.items()
            if last_seen > cutoff
        }


def query_xray_stats():
    """Query Xray Stats API for per-user traffic data."""
    try:
        result = subprocess.run(
            ['docker', 'exec', 'moav-xray', 'xray', 'api', 'statsquery',
             '-s', '127.0.0.1:10085', '-pattern', 'user'],
            capture_output=True, text=True, timeout=10
        )

        if result.returncode != 0:
            if result.stderr:
                print(f"Stats API error: {result.stderr.strip()}")
            return

        parse_stats_output(result.stdout)

    except subprocess.TimeoutExpired:
        print("Stats API query timed out")
    except Exception as e:
        print(f"Stats API error: {e}")


def parse_stats_output(output: str):
    """Parse protobuf text format stats output from xray api statsquery."""
    # Split into stat blocks
    current_name = None

    for line in output.splitlines():
        line = line.strip()

        name_match = STAT_NAME_PATTERN.search(line)
        if name_match:
            current_name = name_match.group(1)
            continue

        value_match = STAT_VALUE_PATTERN.search(line)
        if value_match and current_name:
            value = int(value_match.group(1))

            # Format: user>>>username@moav>>>traffic>>>uplink/downlink
            parts = current_name.split(">>>")
            if len(parts) == 4 and parts[0] == "user" and parts[2] == "traffic":
                # Extract username (remove @moav suffix)
                username = parts[1].replace("@moav", "")
                direction = parts[3]

                with metrics_lock:
                    if direction == "uplink":
                        user_upload[username] += value
                    elif direction == "downlink":
                        user_download[username] += value

            current_name = None


def tail_docker_logs():
    """Tail Xray container logs and parse user connections."""
    print("Starting log tailer for moav-xray...")

    while True:
        try:
            process = subprocess.Popen(
                ['docker', 'logs', '-f', '--tail', '100', 'moav-xray'],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            for line in process.stdout:
                if 'accepted' in line and 'moav' in line:
                    if parse_log_line(line):
                        update_active_users()

            process.wait()
        except Exception as e:
            print(f"Error tailing logs: {e}")

        print("Log tailer disconnected, retrying in 5s...")
        time.sleep(5)


def periodic_update():
    """Periodically update active users and query stats API."""
    while True:
        time.sleep(STATS_INTERVAL)
        update_active_users()
        query_xray_stats()


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()

            output = []

            with metrics_lock:
                # Active users count
                output.append('# HELP xray_active_users Number of users active in last 5 minutes')
                output.append('# TYPE xray_active_users gauge')
                output.append(f'xray_active_users {len(active_users)}')

                # Total unique users
                output.append('# HELP xray_total_users Total number of unique users seen')
                output.append('# TYPE xray_total_users counter')
                output.append(f'xray_total_users {len(user_connections)}')

                # Total connections
                output.append('# HELP xray_total_connections Total number of user connections')
                output.append('# TYPE xray_total_connections counter')
                output.append(f'xray_total_connections {sum(user_connections.values())}')

                # Per-user connections
                output.append('# HELP xray_user_connections Total connections per user')
                output.append('# TYPE xray_user_connections counter')
                for user, count in sorted(user_connections.items()):
                    output.append(f'xray_user_connections{{user="{user}"}} {count}')

                # Per-user active status
                output.append('# HELP xray_user_active Whether user is active (1) or inactive (0)')
                output.append('# TYPE xray_user_active gauge')
                for user in user_connections:
                    is_active = 1 if user in active_users else 0
                    output.append(f'xray_user_active{{user="{user}"}} {is_active}')

                # Per-user upload bytes
                output.append('# HELP xray_user_upload_bytes Total upload bytes per user')
                output.append('# TYPE xray_user_upload_bytes counter')
                for user, bytes_val in sorted(user_upload.items()):
                    output.append(f'xray_user_upload_bytes{{user="{user}"}} {bytes_val}')

                # Per-user download bytes
                output.append('# HELP xray_user_download_bytes Total download bytes per user')
                output.append('# TYPE xray_user_download_bytes counter')
                for user, bytes_val in sorted(user_download.items()):
                    output.append(f'xray_user_download_bytes{{user="{user}"}} {bytes_val}')

                # Total upload/download
                total_up = sum(user_upload.values())
                total_down = sum(user_download.values())
                output.append('# HELP xray_upload_bytes_total Total upload bytes across all users')
                output.append('# TYPE xray_upload_bytes_total counter')
                output.append(f'xray_upload_bytes_total {total_up}')

                output.append('# HELP xray_download_bytes_total Total download bytes across all users')
                output.append('# TYPE xray_download_bytes_total counter')
                output.append(f'xray_download_bytes_total {total_down}')

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
    port = 9103

    # Start log tailer in background thread
    tailer_thread = threading.Thread(target=tail_docker_logs, daemon=True)
    tailer_thread.start()

    # Start periodic update thread (active users + stats API)
    update_thread = threading.Thread(target=periodic_update, daemon=True)
    update_thread.start()

    # Start HTTP server
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    print(f"Xray user exporter listening on port {port}")
    print(f"Metrics available at http://localhost:{port}/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
