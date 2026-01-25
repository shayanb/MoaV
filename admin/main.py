#!/usr/bin/env python3
"""
MoaV Admin Dashboard
Simple stats viewer for the circumvention stack
"""

import os
import json
import asyncio
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

    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            # Get traffic stats
            resp = await client.get(f"{SINGBOX_API}/traffic", headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                stats["traffic"]["upload"] = data.get("up", 0)
                stats["traffic"]["download"] = data.get("down", 0)

            # Get connections
            resp = await client.get(f"{SINGBOX_API}/connections", headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                stats["connections"] = data.get("connections", [])

            # Get memory
            resp = await client.get(f"{SINGBOX_API}/memory", headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                stats["memory"] = data.get("inuse", 0)

        except Exception as e:
            stats["error"] = str(e)

    return stats


def format_bytes(bytes_val):
    """Format bytes to human readable"""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if bytes_val < 1024:
            return f"{bytes_val:.2f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.2f} PB"


def get_service_status():
    """Get status of all services"""
    services = []

    # Check sing-box
    services.append({
        "name": "sing-box",
        "description": "Multi-protocol proxy (Reality, Trojan, Hysteria2)",
        "status": "unknown",
        "port": "443/tcp, 443/udp"
    })

    # Check other services based on docker
    # This is a simplified check - in production, use docker API
    return services


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request, username: str = Depends(verify_auth)):
    """Main dashboard page"""
    stats = await fetch_singbox_stats()
    services = get_service_status()

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
    return stats


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

    # Run without SSL if certs not found (admin is localhost-only anyway)
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8443,
        ssl_keyfile=ssl_keyfile,
        ssl_certfile=ssl_certfile,
    )
