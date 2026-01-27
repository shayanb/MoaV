#!/usr/bin/env python3
"""
MoaV Admin Dashboard
Simple stats viewer for the circumvention stack
"""

import os
import json
import asyncio
import socket
from datetime import datetime
from pathlib import Path

import httpx
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.templating import Jinja2Templates
import secrets

app = FastAPI(title="MoaV Admin", docs_url=None, redoc_url=None)
security = HTTPBasic()
templates = Jinja2Templates(directory="templates")

# Configuration
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "admin")
ADMIN_IP_WHITELIST = os.environ.get("ADMIN_IP_WHITELIST", "").split(",")
ADMIN_IP_WHITELIST = [ip.strip() for ip in ADMIN_IP_WHITELIST if ip.strip()]

SINGBOX_API = "http://moav-sing-box:9090"
CLASH_SECRET = ""

# Try to load Clash API secret
try:
    with open("/state/keys/clash-api.env") as f:
        for line in f:
            if line.startswith("CLASH_API_SECRET="):
                CLASH_SECRET = line.split("=", 1)[1].strip()
except FileNotFoundError:
    pass


def verify_auth(request: Request, credentials: HTTPBasicCredentials = Depends(security)):
    """Verify authentication via password and optional IP whitelist"""
    client_ip = request.client.host

    # Check IP whitelist if configured
    if ADMIN_IP_WHITELIST:
        ip_allowed = any(
            client_ip.startswith(allowed.rstrip("0123456789").rstrip("."))
            if "/" in allowed else client_ip == allowed
            for allowed in ADMIN_IP_WHITELIST
        )
        if not ip_allowed:
            raise HTTPException(status_code=403, detail="IP not allowed")

    # Check password
    correct_password = secrets.compare_digest(credentials.password, ADMIN_PASSWORD)
    if not correct_password:
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username


def check_host_port(host: str, port: int, timeout: float = 0.3) -> bool:
    """Check if a host:port is reachable"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()
        return result == 0
    except Exception:
        return False


def check_service_status(name: str) -> str:
    """Check if a Docker service is running by trying DNS resolution"""
    service_hosts = {
        "sing-box": "moav-sing-box",
        "decoy": "moav-decoy",
        "wstunnel": "moav-wstunnel",
        "wireguard": "moav-wireguard",
        "dnstt": "moav-dnstt",
        "conduit": "moav-conduit",
    }

    # Snowflake uses host networking, can't check from inside container
    # Return "running" as default since we can't reliably detect from here
    if name == "snowflake":
        return "running"  # Assume running if profile is enabled

    if name not in service_hosts:
        return "unknown"

    host = service_hosts[name]
    try:
        # Try DNS resolution with a local timeout (not global)
        # Create a socket just for the DNS check
        old_timeout = socket.getdefaulttimeout()
        socket.setdefaulttimeout(0.5)
        try:
            socket.gethostbyname(host)
            return "running"
        finally:
            # Restore original timeout
            socket.setdefaulttimeout(old_timeout)
    except socket.gaierror:
        return "stopped"
    except socket.timeout:
        return "unknown"
    except Exception:
        return "unknown"


async def fetch_singbox_stats():
    """Fetch stats from sing-box Clash API"""
    stats = {
        "connections": [],
        "traffic": {"upload": 0, "download": 0},
        "memory": 0,
        "error": None
    }

    headers = {}
    if CLASH_SECRET:
        headers["Authorization"] = f"Bearer {CLASH_SECRET}"

    # Use explicit timeout config to prevent hanging
    timeout = httpx.Timeout(connect=1.0, read=2.0, write=1.0, pool=1.0)

    try:
        # Wrap entire operation in asyncio timeout as backup
        async with asyncio.timeout(5.0):
            async with httpx.AsyncClient(timeout=timeout) as client:
                try:
                    # Get connections (includes upload/download per connection)
                    resp = await client.get(f"{SINGBOX_API}/connections", headers=headers)
                    if resp.status_code == 200:
                        data = resp.json()
                        stats["connections"] = data.get("connections", []) or []
                        stats["traffic"]["upload"] = data.get("uploadTotal", 0)
                        stats["traffic"]["download"] = data.get("downloadTotal", 0)

                    # Get memory
                    resp = await client.get(f"{SINGBOX_API}/memory", headers=headers)
                    if resp.status_code == 200:
                        data = resp.json()
                        stats["memory"] = data.get("inuse", 0)

                except httpx.ConnectError:
                    stats["error"] = "sing-box API not reachable"
                except httpx.ConnectTimeout:
                    stats["error"] = "sing-box connection timeout"
                except httpx.ReadTimeout:
                    stats["error"] = "sing-box read timeout"
                except httpx.TimeoutException:
                    stats["error"] = "sing-box API timeout"

    except asyncio.TimeoutError:
        stats["error"] = "sing-box API timeout (5s)"
    except Exception as e:
        stats["error"] = f"Error: {type(e).__name__}: {str(e)}"

    return stats


async def fetch_conduit_stats():
    """Fetch stats from Psiphon Conduit if running"""
    stats = {
        "running": False,
        "connections": {"connecting": 0, "connected": 0},
        "bandwidth": {"upload": "0 B", "download": "0 B"},
        "traffic_from": [],
        "traffic_to": [],
        "error": None
    }

    # Check if conduit is running
    if check_service_status("conduit") != "running":
        stats["error"] = "Conduit not running"
        return stats

    stats["running"] = True

    # Try to read stats from shared state file
    stats_file = Path("/state/conduit-stats.json")
    if stats_file.exists():
        try:
            with open(stats_file) as f:
                file_stats = json.load(f)
                stats["connections"] = file_stats.get("connections", stats["connections"])
                stats["bandwidth"] = file_stats.get("bandwidth", stats["bandwidth"])
                stats["traffic_from"] = file_stats.get("traffic_from", [])
                stats["traffic_to"] = file_stats.get("traffic_to", [])
        except (json.JSONDecodeError, IOError) as e:
            stats["error"] = f"Failed to read stats: {e}"

    return stats


def format_bytes(bytes_val):
    """Format bytes to human readable"""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if bytes_val < 1024:
            return f"{bytes_val:.2f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.2f} PB"


def get_services_status():
    """Get status of all services with live checks"""
    services = [
        {
            "name": "sing-box",
            "description": "Multi-protocol proxy (Reality, Trojan, Hysteria2)",
            "ports": "443/tcp, 443/udp, 8443/tcp",
            "profile": "proxy",
            "status": check_service_status("sing-box")
        },
        {
            "name": "decoy",
            "description": "Decoy website (nginx)",
            "ports": "internal",
            "profile": "proxy",
            "status": check_service_status("decoy")
        },
        {
            "name": "wstunnel",
            "description": "WebSocket tunnel for WireGuard",
            "ports": "8080/tcp",
            "profile": "wireguard",
            "status": check_service_status("wstunnel")
        },
        {
            "name": "dnstt",
            "description": "DNS tunnel (last resort)",
            "ports": "53/udp",
            "profile": "dnstt",
            "status": check_service_status("dnstt")
        },
        {
            "name": "conduit",
            "description": "Psiphon bandwidth donation",
            "ports": "dynamic",
            "profile": "conduit",
            "status": check_service_status("conduit")
        },
        {
            "name": "snowflake",
            "description": "Tor Snowflake proxy",
            "ports": "dynamic",
            "profile": "snowflake",
            "status": check_service_status("snowflake")
        },
    ]
    return services


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request, username: str = Depends(verify_auth)):
    """Main dashboard page"""
    stats = await fetch_singbox_stats()
    conduit_stats = await fetch_conduit_stats()
    services = get_services_status()

    # Count active connections by user
    user_stats = {}
    for conn in stats.get("connections", []):
        metadata = conn.get("metadata", {})
        user = metadata.get("user", "unknown")
        if user not in user_stats:
            user_stats[user] = {"connections": 0, "upload": 0, "download": 0}
        user_stats[user]["connections"] += 1
        user_stats[user]["upload"] += conn.get("upload", 0)
        user_stats[user]["download"] += conn.get("download", 0)

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "stats": stats,
        "conduit_stats": conduit_stats,
        "services": services,
        "user_stats": user_stats,
        "format_bytes": format_bytes,
        "total_connections": len(stats.get("connections", [])),
        "memory_usage": format_bytes(stats.get("memory", 0)),
        "total_upload": format_bytes(stats["traffic"]["upload"]),
        "total_download": format_bytes(stats["traffic"]["download"]),
        "error": stats.get("error"),
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    })


@app.get("/api/stats")
async def api_stats(username: str = Depends(verify_auth)):
    """JSON API for stats"""
    stats = await fetch_singbox_stats()
    conduit_stats = await fetch_conduit_stats()
    services = get_services_status()
    return {
        "singbox": stats,
        "conduit": conduit_stats,
        "services": services
    }


@app.get("/api/health")
async def health():
    """Health check endpoint (no auth required)"""
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


if __name__ == "__main__":
    import uvicorn
    import glob

    # Find certificate files dynamically
    cert_dirs = glob.glob("/certs/live/*/")
    ssl_keyfile = None
    ssl_certfile = None

    if cert_dirs:
        cert_dir = cert_dirs[0]
        key_path = f"{cert_dir}privkey.pem"
        cert_path = f"{cert_dir}fullchain.pem"
        if Path(key_path).exists() and Path(cert_path).exists():
            ssl_keyfile = key_path
            ssl_certfile = cert_path

    # Run with SSL if certs found
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8443,
        ssl_keyfile=ssl_keyfile,
        ssl_certfile=ssl_certfile,
    )
