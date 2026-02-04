#!/usr/bin/env python3
"""
MoaV Admin Dashboard
Simple stats viewer for the circumvention stack
"""

import os
import json
import asyncio
import socket
import zipfile
import io
import time
from datetime import datetime
from pathlib import Path

import httpx
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import HTMLResponse, StreamingResponse
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

# Current version
CURRENT_VERSION = "unknown"
try:
    with open("/app/VERSION") as f:
        CURRENT_VERSION = f.read().strip()
except FileNotFoundError:
    pass

# Update check cache
UPDATE_CACHE = {"version": None, "checked_at": 0}
UPDATE_CACHE_TTL = 3600  # 1 hour


def version_gt(v1: str, v2: str) -> bool:
    """Check if v1 > v2 (semver comparison)"""
    try:
        v1_parts = [int(x) for x in v1.split(".")[:3]]
        v2_parts = [int(x) for x in v2.split(".")[:3]]
        return v1_parts > v2_parts
    except (ValueError, AttributeError):
        return False


async def check_for_updates() -> dict:
    """Check GitHub for latest release (cached for 1 hour)"""
    now = time.time()

    # Return cached result if still valid
    if UPDATE_CACHE["version"] and (now - UPDATE_CACHE["checked_at"]) < UPDATE_CACHE_TTL:
        latest = UPDATE_CACHE["version"]
        return {
            "update_available": version_gt(latest, CURRENT_VERSION),
            "latest_version": latest,
            "current_version": CURRENT_VERSION,
        }

    # Fetch from GitHub API
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(
                "https://api.github.com/repos/shayanb/MoaV/releases/latest"
            )
            if resp.status_code == 200:
                data = resp.json()
                latest = data.get("tag_name", "").lstrip("v")
                if latest:
                    UPDATE_CACHE["version"] = latest
                    UPDATE_CACHE["checked_at"] = now
                    return {
                        "update_available": version_gt(latest, CURRENT_VERSION),
                        "latest_version": latest,
                        "current_version": CURRENT_VERSION,
                    }
    except Exception:
        pass

    return {
        "update_available": False,
        "latest_version": None,
        "current_version": CURRENT_VERSION,
    }


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
    timeout = httpx.Timeout(connect=2.0, read=3.0, write=2.0, pool=2.0)

    try:
        # Wrap entire operation in asyncio timeout as backup
        async with asyncio.timeout(10.0):
            async with httpx.AsyncClient(timeout=timeout) as client:
                try:
                    # Get connections (includes upload/download per connection)
                    resp = await client.get(f"{SINGBOX_API}/connections", headers=headers)
                    if resp.status_code == 200:
                        data = resp.json()
                        stats["connections"] = data.get("connections", []) or []
                        stats["traffic"]["upload"] = data.get("uploadTotal", 0)
                        stats["traffic"]["download"] = data.get("downloadTotal", 0)

                    # Get memory - this is a streaming endpoint, read first line only
                    async with client.stream("GET", f"{SINGBOX_API}/memory", headers=headers) as resp:
                        if resp.status_code == 200:
                            async for line in resp.aiter_lines():
                                if line.strip():
                                    try:
                                        data = json.loads(line)
                                        stats["memory"] = data.get("inuse", 0)
                                    except json.JSONDecodeError:
                                        pass
                                    break  # Only need first line

                except httpx.ConnectError:
                    stats["error"] = "sing-box API not reachable"
                except httpx.ConnectTimeout:
                    stats["error"] = "sing-box connection timeout"
                except httpx.ReadTimeout:
                    stats["error"] = "sing-box read timeout"
                except httpx.TimeoutException:
                    stats["error"] = "sing-box API timeout"

    except asyncio.TimeoutError:
        stats["error"] = "sing-box API timeout (10s)"
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
    update_info = await check_for_updates()

    # Count active connections by source IP
    user_stats = {}
    for conn in stats.get("connections", []):
        metadata = conn.get("metadata", {})
        source_ip = metadata.get("sourceIP", "unknown")
        if source_ip not in user_stats:
            user_stats[source_ip] = {"connections": 0, "upload": 0, "download": 0}
        user_stats[source_ip]["connections"] += 1
        user_stats[source_ip]["upload"] += conn.get("upload", 0)
        user_stats[source_ip]["download"] += conn.get("download", 0)

    # Get all users with their bundle info (no active status tracking)
    all_users = list_users()

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "stats": stats,
        "conduit_stats": conduit_stats,
        "services": services,
        "connection_stats": user_stats,
        "all_users": all_users,
        "format_bytes": format_bytes,
        "total_connections": len(stats.get("connections", [])),
        "memory_usage": format_bytes(stats.get("memory", 0)),
        "total_upload": format_bytes(stats["traffic"]["upload"]),
        "total_download": format_bytes(stats["traffic"]["download"]),
        "error": stats.get("error"),
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"),
        "update_available": update_info["update_available"],
        "latest_version": update_info["latest_version"],
        "current_version": update_info["current_version"],
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


# User bundle paths - check multiple possible locations
BUNDLE_PATHS = [
    Path("/outputs/bundles"),
    Path("/app/outputs/bundles"),
]


def get_bundle_path():
    """Find the bundles directory"""
    for path in BUNDLE_PATHS:
        if path.exists():
            return path
    return BUNDLE_PATHS[0]  # Default


def list_users():
    """List all users from bundles directory"""
    users = []
    bundle_path = get_bundle_path()

    if not bundle_path.exists():
        return users

    for user_dir in sorted(bundle_path.iterdir()):
        # Skip non-directories and zip files
        if not user_dir.is_dir():
            continue
        # Skip special directories
        if user_dir.name.startswith('.') or user_dir.name.endswith('-configs'):
            continue

        username = user_dir.name

        # Check what files exist in the bundle
        has_reality = (user_dir / "reality.txt").exists()
        has_wireguard = (user_dir / "wireguard.conf").exists()
        has_hysteria2 = (user_dir / "hysteria2.yaml").exists() or (user_dir / "hysteria2.txt").exists()
        has_trojan = (user_dir / "trojan.txt").exists()

        # Check if zip already exists
        zip_exists = (bundle_path / f"{username}.zip").exists()

        users.append({
            "username": username,
            "has_reality": has_reality,
            "has_wireguard": has_wireguard,
            "has_hysteria2": has_hysteria2,
            "has_trojan": has_trojan,
            "zip_exists": zip_exists,
        })

    return users


@app.get("/download/{username}")
async def download_bundle(username: str, _: str = Depends(verify_auth)):
    """Download user bundle as zip file"""
    bundle_path = get_bundle_path()
    user_dir = bundle_path / username

    # Security: validate username (no path traversal)
    if ".." in username or "/" in username or "\\" in username:
        raise HTTPException(status_code=400, detail="Invalid username")

    if not user_dir.exists() or not user_dir.is_dir():
        raise HTTPException(status_code=404, detail="User bundle not found")

    # Check if pre-packaged zip exists
    zip_path = bundle_path / f"{username}.zip"
    if zip_path.exists():
        # Serve existing zip
        def iter_file():
            with open(zip_path, "rb") as f:
                yield from f
        return StreamingResponse(
            iter_file(),
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename={username}.zip"}
        )

    # Create zip on-the-fly
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for file_path in user_dir.rglob("*"):
            if file_path.is_file():
                arcname = file_path.relative_to(user_dir)
                zf.write(file_path, arcname)

    zip_buffer.seek(0)

    return StreamingResponse(
        iter([zip_buffer.getvalue()]),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={username}.zip"}
    )


def find_certificates(wait_for_letsencrypt=True, max_wait=60):
    """
    Find SSL certificates with priority: Let's Encrypt > Self-signed

    Args:
        wait_for_letsencrypt: If True, wait for Let's Encrypt certs to appear
        max_wait: Maximum seconds to wait for Let's Encrypt certs

    Returns:
        Tuple of (ssl_keyfile, ssl_certfile) or (None, None)
    """
    import glob
    import time

    # Check for self-signed first to determine if we're in domain-less mode
    selfsigned_key = "/certs/selfsigned/privkey.pem"
    selfsigned_cert = "/certs/selfsigned/fullchain.pem"
    has_selfsigned = Path(selfsigned_key).exists() and Path(selfsigned_cert).exists()

    # Wait for Let's Encrypt certs if requested
    if wait_for_letsencrypt:
        waited = 0
        check_interval = 5
        print(f"Waiting for Let's Encrypt certificate (up to {max_wait}s)...")

        while waited < max_wait:
            cert_dirs = glob.glob("/certs/live/*/")
            for cert_dir in cert_dirs:
                # Skip README-only directories
                key_path = f"{cert_dir}privkey.pem"
                cert_path = f"{cert_dir}fullchain.pem"
                if Path(key_path).exists() and Path(cert_path).exists():
                    print(f"Found Let's Encrypt certificate from {cert_dir}")
                    return key_path, cert_path

            # If we have self-signed, we might be in domain-less mode
            # Don't wait too long in that case
            if has_selfsigned and waited >= 15:
                print("Self-signed cert exists, assuming domain-less mode")
                break

            time.sleep(check_interval)
            waited += check_interval
            if waited < max_wait:
                print(f"  Still waiting... ({waited}s)")

    # Check one more time without waiting
    cert_dirs = glob.glob("/certs/live/*/")
    for cert_dir in cert_dirs:
        key_path = f"{cert_dir}privkey.pem"
        cert_path = f"{cert_dir}fullchain.pem"
        if Path(key_path).exists() and Path(cert_path).exists():
            print(f"Using Let's Encrypt certificate from {cert_dir}")
            return key_path, cert_path

    # Fallback to self-signed certificate (domain-less mode)
    if has_selfsigned:
        print("Using self-signed certificate (domain-less mode)")
        return selfsigned_key, selfsigned_cert

    return None, None


if __name__ == "__main__":
    import uvicorn

    # Find certificate files (waits for Let's Encrypt if needed)
    ssl_keyfile, ssl_certfile = find_certificates(wait_for_letsencrypt=True, max_wait=60)

    if not ssl_keyfile:
        print("WARNING: No SSL certificates found, running without HTTPS")

    # Run with SSL if certs found
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8443,
        ssl_keyfile=ssl_keyfile,
        ssl_certfile=ssl_certfile,
    )
