#!/usr/bin/env python3
"""
Xray User Prometheus Exporter

Parses Xray container logs to extract user connection metrics.
Xray access log format:
  2024/01/01 12:00:00 [email] accepted tcp:destination:443 [inbound_tag >> outbound_tag]
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

# Lock for thread safety
metrics_lock = threading.Lock()

# Regex to parse Xray access log lines
# Example: 2026/03/14 10:30:00 from 1.2.3.4:12345 accepted tcp:google.com:443 [vless-xhttp-reality >> direct] email: user01@moav
EMAIL_PATTERN = re.compile(r'email:\s*(\S+?)@moav')

# Fallback: older Xray format puts email in brackets
# Example: 2026/03/14 10:30:00 [user01@moav] ...
BRACKET_PATTERN = re.compile(r'\[([^\]]+?)@moav\]')

# Active window in seconds (5 minutes)
ACTIVE_WINDOW = 300


def parse_log_line(line: str) -> bool:
    """Parse a log line and update metrics. Returns True if parsed."""
    # Only process access log lines (accepted connections)
    if 'accepted' not in line:
        return False

    # Try email: field first (Xray 1.8+)
    match = EMAIL_PATTERN.search(line)
    if not match:
        # Fallback to bracket format
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
    """Periodically update active users set."""
    while True:
        time.sleep(60)
        update_active_users()


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

    # Start periodic update thread
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
