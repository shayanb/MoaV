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


def check_host_port(host: str, port: int, timeout: float = 0.5) -> bool:
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
    """Check if a Docker service is running by trying to connect to it"""
    service_checks = {
        "sing-box": ("moav-sing-box", 9090),
        "decoy": ("moav-decoy", 80),
        "wstunnel": ("moav-wstunnel", 8080),
        "wireguard": ("moav-wireguard", 51820),
        "dnstt": ("moav-dnstt", 5353),
        "conduit": ("moav-conduit", 8080),
    }

    if name not in service_checks:
        return "unknown"

    host, port = service_checks[name]
    try:
        # Try DNS resolution first - if container exists, Docker DNS resolves it
        ip = socket.gethostbyname(host)
        # Then check if port is open
        if check_host_port(ip, port):
            return "running"
        # Container exists but port not responding - might be starting up
        return "starting"
    except socket.gaierror:
        # DNS resolution failed - container doesn't exist
        return "stopped"
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

    async with httpx.AsyncClient(timeout=3.0) as client:
        try:
            # Get connections (includes upload/download per connection)
            # This is a regular JSON endpoint, not streaming
            resp = await client.get(f"{SINGBOX_API}/connections", headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                stats["connections"] = data.get("connections", []) or []
                # Calculate total traffic from connections
                stats["traffic"]["upload"] = data.get("uploadTotal", 0)
                stats["traffic"]["download"] = data.get("downloadTotal", 0)

            # Get memory
            resp = await client.get(f"{SINGBOX_API}/memory", headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                stats["memory"] = data.get("inuse", 0)

            # Note: /traffic endpoint is SSE (streaming), skip it
            # Traffic totals are available from /connections endpoint

        except httpx.ConnectError:
            stats["error"] = "sing-box not running (start with --profile proxy)"
        except httpx.ReadTimeout:
            stats["error"] = "sing-box API timeout"
        except Exception as e:
            stats["error"] = str(e)

    return stats


async def fetch_conduit_stats():
    """Fetch stats from Psiphon Conduit if running"""
    stats = {
        "running": False,
        "clients": 0,
        "bytes_relayed": 0,
        "error": None
    }

    # Check if conduit is running
    if check_service_status("conduit") != "running":
        stats["error"] = "Conduit not running"
        return stats

    stats["running"] = True
    # Note: Conduit doesn't expose an API, so we can only show running status
    # Future: could parse logs for stats
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
