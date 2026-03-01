"""
Al-Mudeer - Version API Route
Public endpoint for version checking (force update system)

RELIABLE FORCE UPDATE SYSTEM (Build Number Based):
1. Mobile app has a build number in pubspec.yaml (e.g., version: 1.0.0+2)
2. Backend reads minimum required build number from DATABASE (app_config table)
3. If app_build_number < min_build_number → force update

SOFT UPDATE SUPPORT:
- Set is_soft_update=true in update config for optional updates
- Users can dismiss and update later

To trigger update:
1. Use the Admin API (or update_version.py script) to set new version info in DB
2. Upload APK to backend/static/download/almudeer.apk (or CDN)
"""

from fastapi import APIRouter, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse, Response
from datetime import datetime, timezone
from pydantic import BaseModel
from typing import Any, Dict, List, Optional
import os
import json
import hashlib
import time
import threading
import asyncio
import httpx
from datetime import datetime, timezone
import pytz
from database import (
    save_update_event, 
    get_update_events,
    get_app_config,
    get_all_app_config,
    set_app_config,
    add_version_history,
    get_version_history_list
)
from logging_config import get_logger

logger = get_logger(__name__)

router = APIRouter(tags=["Version"])

# Paths
_STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "download")
_APK_FILE = os.path.join(_STATIC_DIR, "almudeer.apk")

# Multi-architecture APK variants
# Structure: {arch_name: filename}
_APK_VARIANTS = {
    "universal": "almudeer.apk",  # Universal APK (all architectures)
    "arm64_v8a": "almudeer_arm64_v8a.apk",  # ARM 64-bit (most modern devices)
    "armeabi_v7a": "almudeer_armeabi_v7a.apk",  # ARM 32-bit (older devices)
    "x86_64": "almudeer_x86_64.apk",  # x86 64-bit (emulators, some tablets)
}

# CDN URLs for architecture-specific APKs (optional)
_APK_CDN_VARIANTS = {
    "universal": os.getenv("APK_CDN_URL_UNIVERSAL", ""),
    "arm64_v8a": os.getenv("APK_CDN_URL_ARM64", ""),
    "armeabi_v7a": os.getenv("APK_CDN_URL_ARMV7", ""),
    "x86_64": os.getenv("APK_CDN_URL_X86", ""),
}

# Version for display purposes only
_APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
_BACKEND_VERSION = os.getenv("BACKEND_VERSION", "1.0.0")

# APK download URL - can be CDN URL or Railway backend
# For CDN: Set APK_CDN_URL environment variable
_APK_CDN_URL = os.getenv("APK_CDN_URL", "")
_APP_DOWNLOAD_URL = _APK_CDN_URL if _APK_CDN_URL else os.getenv(
    "APP_DOWNLOAD_URL", "https://almudeer.up.railway.app/download/almudeer.apk"
)

# iOS Store URL - Fallback if not in DB config
_IOS_STORE_URL = os.getenv("IOS_STORE_URL", "")

# iOS App Store ID - Used for deep linking (itms-apps://)
_IOS_APP_STORE_ID = os.getenv("IOS_APP_STORE_ID", "")

# Force update can be disabled in emergencies
_FORCE_UPDATE_ENABLED = os.getenv("FORCE_UPDATE_ENABLED", "true").lower() == "true"

# Force HTTPS in production
_HTTPS_ONLY = os.getenv("HTTPS_ONLY", "false").lower() == "true"

# Admin key for manual operations - using constant-time comparison
_ADMIN_KEY = os.getenv("ADMIN_KEY", "")

# Admin IP whitelist for additional security
_ADMIN_IP_WHITELIST = os.getenv("ADMIN_IP_WHITELIST", "")  # Comma-separated IPs

# Maximum APK file size in MB (prevent DoS and bandwidth abuse)
# Set to 150MB to accommodate future app growth with safety margin
_MAX_APK_SIZE_MB = int(os.getenv("MAX_APK_SIZE_MB", "150"))


def check_https(request: Request) -> bool:
    """
    Check if the request is using HTTPS.
    Handles reverse proxy headers (X-Forwarded-Proto).
    """
    # Check X-Forwarded-Proto header (set by reverse proxy)
    forwarded_proto = request.headers.get('X-Forwarded-Proto', '')
    if forwarded_proto:
        return forwarded_proto.lower() == 'https'
    
    # Check the actual scheme
    if request.url and request.url.scheme:
        return request.url.scheme == 'https'
    
    # If we can't determine, assume not HTTPS
    return False


# Middleware for HTTPS enforcement (to be added to main app)
async def https_enforcement_middleware(request: Request, call_next):
    """
    Middleware to enforce HTTPS in production.
    Redirects HTTP requests to HTTPS.
    """
    if not _HTTPS_ONLY:
        return await call_next(request)
    
    if check_https(request):
        return await call_next(request)
    
    # Redirect to HTTPS
    from fastapi.responses import RedirectResponse
    https_url = str(request.url).replace('http://', 'https://')
    return RedirectResponse(url=https_url, status_code=301)

# Update priority levels
UPDATE_PRIORITY_CRITICAL = "critical"
UPDATE_PRIORITY_HIGH = "high"
UPDATE_PRIORITY_NORMAL = "normal"
UPDATE_PRIORITY_LOW = "low"

# Localization Strings
_MESSAGES = {
    "ar": {
        "rate_limit": "تم تجاوز الحد المسموح من الطلبات. يرجى المحاولة بعد قليل.",
        "admin_required": "غير مصرح - مفتاح المسؤول مطلوب",
        "invalid_build": "رقم البناء يجب أن يكون 1 أو أكثر",
        "invalid_priority": "أولوية التحديث يجب أن تكون: {priorities}",
        "update_failed": "فشل في تحديث رقم الإصدار: {error}",
        "min_build_updated": "تم تحديث الحد الأدنى لرقم البناء",
        "changelog_updated": "تم تحديث سجل التغييرات",
        "changelog_failed": "فشل في تحديث سجل التغييرات: {error}",
        "force_update_disabled": "تم إلغاء التحديث الإجباري",
        "disable_failed": "فشل في إلغاء التحديث: {error}",
        "update_message": "يتوفر إصدار جديد من التطبيق يحتوي على تحسينات وميزات جديدة. يرجى التحديث للمتابعة.",
        "invalid_event": "حدث غير صالح. يجب أن يكون واحدًا من: {events}"
    },
    "en": {
        "rate_limit": "Rate limit exceeded. Please try again later.",
        "admin_required": "Unauthorized - Admin key required",
        "invalid_build": "Build number must be 1 or higher",
        "invalid_priority": "Update priority must be one of: {priorities}",
        "update_failed": "Failed to update version number: {error}",
        "min_build_updated": "Minimum build number updated",
        "changelog_updated": "Changelog updated successfully",
        "changelog_failed": "Failed to update changelog: {error}",
        "force_update_disabled": "Force update disabled",
        "disable_failed": "Failed to disable update: {error}",
        "update_message": "A new version of the app is available with improvements and new features. Please update to continue.",
        "invalid_event": "Invalid event. Must be one of: {events}"
    }
}

# Rate limiting configuration
# Increased from 30 to 60 requests per minute to accommodate phased rollouts
# where many users may check eligibility simultaneously
_RATE_LIMIT_REQUESTS = int(os.getenv("RATE_LIMIT_REQUESTS", "60"))  # requests per window
_RATE_LIMIT_WINDOW = int(os.getenv("RATE_LIMIT_WINDOW", "60"))  # window in seconds


def _get_client_ip(request: Request) -> str:
    """
    Get the real client IP address, handling proxies.
    
    Checks X-Forwarded-For header first, then falls back to request.client.host
    """
    # Check X-Forwarded-For header (set by reverse proxy)
    forwarded_for = request.headers.get('X-Forwarded-For', '')
    if forwarded_for:
        # Take the first IP (original client)
        client_ip = forwarded_for.split(',')[0].strip()
        if client_ip:
            return client_ip
    
    # Check X-Real-IP header (alternative proxy header)
    real_ip = request.headers.get('X-Real-IP', '')
    if real_ip:
        return real_ip.strip()
    
    # Fallback to direct connection
    if request.client and request.client.host:
        return request.client.host
    
    return "unknown"


class RateLimiter:
    """
    Simple in-memory rate limiter using sliding window.
    Thread-safe for concurrent requests.
    
    Supports device ID-based rate limiting to prevent bypass via IP rotation.
    Falls back to IP+User-Agent hash if device ID not provided.
    """

    def __init__(self, max_requests: int, window_seconds: int):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._requests: Dict[str, List[float]] = {}
        self._lock = threading.Lock()
        self._call_count = 0  # Counter for periodic cleanup

    def is_allowed(self, client_ip: str, device_id: Optional[str] = None, user_agent: Optional[str] = None) -> tuple[bool, int]:
        """
        Check if request is allowed.
        
        Priority for identifier:
        1. Device ID (if provided) - most reliable
        2. IP + User-Agent hash (fallback)
        3. IP only (legacy fallback)

        Args:
            client_ip: Client IP address
            device_id: Optional device ID from X-Device-ID header
            user_agent: Optional User-Agent header

        Returns:
            Tuple of (is_allowed, remaining_requests)
        """
        # Generate identifier based on available data
        if device_id:
            # Primary: Use device ID (most reliable)
            identifier = f"device:{device_id}"
        elif user_agent:
            # Fallback: IP + User-Agent hash (harder to spoof than IP alone)
            identifier = f"ip_ua:{hashlib.sha256(f'{client_ip}:{user_agent}'.encode()).hexdigest()}"
        else:
            # Legacy: IP only
            identifier = f"ip:{client_ip}"
        
        now = time.time()
        window_start = now - self.window_seconds

        with self._lock:
            # Periodic cleanup: every 100 calls, purge stale entries
            self._call_count += 1
            if self._call_count >= 100:
                self._call_count = 0
                self._cleanup_stale(window_start)

            # Get existing requests for this identifier
            if identifier not in self._requests:
                self._requests[identifier] = []

            # Remove expired requests
            self._requests[identifier] = [
                ts for ts in self._requests[identifier] if ts > window_start
            ]

            # Check if under limit
            current_count = len(self._requests[identifier])
            remaining = self.max_requests - current_count

            if current_count >= self.max_requests:
                return False, 0

            # Record this request
            self._requests[identifier].append(now)
            return True, remaining - 1
    
    def _cleanup_stale(self, cutoff: float):
        """Remove all identifiers with no requests in the current window. Must hold _lock."""
        for identifier in list(self._requests.keys()):
            self._requests[identifier] = [
                ts for ts in self._requests[identifier] if ts > cutoff
            ]
            if not self._requests[identifier]:
                del self._requests[identifier]
    
    def cleanup_old_entries(self):
        """Remove entries older than the window. Call periodically."""
        cutoff = time.time() - self.window_seconds
        with self._lock:
            for identifier in list(self._requests.keys()):
                self._requests[identifier] = [
                    ts for ts in self._requests[identifier] if ts > cutoff
                ]
                if not self._requests[identifier]:
                    del self._requests[identifier]

    def get_retry_after(self, client_ip: str, device_id: Optional[str] = None, user_agent: Optional[str] = None) -> int:
        """
        Calculate seconds until the client can retry.
        
        Returns the time until the oldest request in the current window expires,
        allowing the client to make a new request.
        
        Args:
            client_ip: Client IP address
            device_id: Optional device ID from X-Device-ID header
            user_agent: Optional User-Agent header
            
        Returns:
            Seconds until retry is allowed (minimum 1, maximum window_seconds)
        """
        # Generate identifier (same logic as is_allowed)
        if device_id:
            identifier = f"device:{device_id}"
        elif user_agent:
            identifier = f"ip_ua:{hashlib.sha256(f'{client_ip}:{user_agent}'.encode()).hexdigest()}"
        else:
            identifier = f"ip:{client_ip}"
        
        now = time.time()
        window_start = now - self.window_seconds
        
        with self._lock:
            if identifier not in self._requests:
                return 1  # No requests, can retry immediately
            
            # Get requests in current window
            valid_requests = [
                ts for ts in self._requests[identifier] if ts > window_start
            ]
            
            if not valid_requests:
                return 1  # No valid requests, can retry
            
            # Find oldest request in window
            oldest = min(valid_requests)
            
            # Calculate when it will expire
            expires_at = oldest + self.window_seconds
            retry_after = int(expires_at - now)
            
            # Clamp to reasonable range
            return max(1, min(retry_after, self.window_seconds))


# Global rate limiter instance
_rate_limiter = RateLimiter(_RATE_LIMIT_REQUESTS, _RATE_LIMIT_WINDOW)
import secrets

def compare_secure(a: Optional[str], b: Optional[str]) -> bool:
    """Constant-time comparison for admin key to prevent timing attacks"""
    if not a or not b:
        return False
    return secrets.compare_digest(str(a), str(b))


def _check_admin_access(request: Request, admin_key: Optional[str]) -> bool:
    """
    Verify admin access using:
    1. Constant-time comparison of admin key
    2. IP whitelist check (if configured)
    """
    # First check admin key
    if not compare_secure(admin_key, _ADMIN_KEY):
        return False
    
    # If IP whitelist is configured, check client IP
    if _ADMIN_IP_WHITELIST:
        client_ip = request.client.host if request and request.client else None
        if not client_ip:
            return False
        
        allowed_ips = [ip.strip() for ip in _ADMIN_IP_WHITELIST.split(',') if ip.strip()]
        
        # Also check X-Forwarded-For if behind proxy
        forwarded_for = request.headers.get('X-Forwarded-For', '')
        if forwarded_for:
            client_ip = forwarded_for.split(',')[0].strip()
        
        return client_ip in allowed_ips
    
    return True



async def _get_min_build_number() -> int:
    """Read the minimum required build number from DB."""
    try:
        val = await get_app_config("min_build_number")
        return int(val) if val else 1
    except (ValueError, TypeError):
        return 1


async def _get_apk_signing_fingerprint() -> Optional[str]:
    """Read the APK signing certificate fingerprint from DB."""
    return await get_app_config("apk_signing_fingerprint")


# CDN Health Check Cache
_CDN_HEALTH_CACHE = {
    "universal": {"healthy": True, "last_check": 0},
    "arm64_v8a": {"healthy": True, "last_check": 0},
    "armeabi_v7a": {"healthy": True, "last_check": 0},
    "x86_64": {"healthy": True, "last_check": 0},
}
_CDN_HEALTH_CACHE_TTL = 60  # Check every 60 seconds
_CDN_HEALTH_LOCK = asyncio.Lock()


async def _verify_cdn_health(url: str, timeout: float = 3.0, retries: int = 2) -> bool:
    """
    Verify CDN URL is healthy by sending a GET request with Range header.
    Uses Range header to fetch only first byte - more reliable with Cloudflare than HEAD.

    Args:
        url: CDN URL to check
        timeout: Request timeout in seconds
        retries: Number of retry attempts on failure

    Returns:
        True if CDN is healthy (returns 200/204/206), False otherwise
    """
    if not url:
        return False

    attempt = 0
    while attempt <= retries:
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                # Use GET with Range header instead of HEAD - Cloudflare handles this more reliably
                response = await client.get(url, headers={"Range": "bytes=0-1"})
                # Consider 200, 204, 206 (Partial Content), 301, 302 as healthy
                if response.status_code in (200, 204, 206, 301, 302):
                    return True
                logger.debug(f"CDN health check returned {response.status_code} for {url}")
                return False
        except httpx.ReadTimeout:
            # Cloudflare may be slow for large files - retry
            attempt += 1
            if attempt > retries:
                logger.debug(f"CDN health check timed out after {retries} retries: {url}")
                return False
            await asyncio.sleep(0.5 * attempt)  # Backoff
        except Exception as e:
            logger.debug(f"CDN health check failed for {url}: {e}")
            return False

    return False


async def _get_healthy_cdn_url(arch: str) -> Optional[str]:
    """
    Get CDN URL only if it's healthy, otherwise return None for fallback.
    
    Args:
        arch: Architecture name (universal, arm64_v8a, etc.)
        
    Returns:
        Healthy CDN URL or None if unhealthy/not configured
    """
    import time
    
    cdn_url = _APK_CDN_VARIANTS.get(arch, "")
    if not cdn_url:
        return None
    
    current_time = time.time()
    cache = _CDN_HEALTH_CACHE.get(arch, {})
    
    # Check cache first
    if cache.get("last_check", 0) > current_time - _CDN_HEALTH_CACHE_TTL:
        # Use cached result
        return cdn_url if cache.get("healthy", True) else None
    
    # Refresh cache with lock to prevent concurrent checks
    async with _CDN_HEALTH_LOCK:
        # Double-check after acquiring lock
        cache = _CDN_HEALTH_CACHE.get(arch, {})
        if cache.get("last_check", 0) > current_time - _CDN_HEALTH_CACHE_TTL:
            return cdn_url if cache.get("healthy", True) else None
        
        # Perform health check
        is_healthy = await _verify_cdn_health(cdn_url)
        
        # Update cache
        _CDN_HEALTH_CACHE[arch] = {
            "healthy": is_healthy,
            "last_check": current_time
        }
        
        if not is_healthy:
            logger.warning(f"CDN unhealthy for {arch}, falling back to local: {cdn_url}")
        
        return cdn_url if is_healthy else None


async def _get_cdn_url() -> Optional[str]:
    """Read CDN URL from DB configuration (allows runtime updates)."""
    # First check environment variable
    if _APK_CDN_URL:
        return _APK_CDN_URL
    
    # Then check database config (allows dynamic updates)
    try:
        return await get_app_config("apk_cdn_url")
    except:
        return None


async def _get_architecture_specific_url(
    arch: Optional[str],
    base_url: str
) -> tuple[str, dict]:
    """
    Get architecture-specific APK URL and all available variants.
    
    Includes CDN health checking with automatic fallback to local files.

    Args:
        arch: Requested architecture (arm64_v8a, armeabi_v7a, x86_64, universal)
        base_url: Base APK URL to use as fallback

    Returns:
        Tuple of (selected_url, variants_dict)
    """
    variants = {}

    # Build variant URLs with health checking
    for variant_name, filename in _APK_VARIANTS.items():
        variant_path = os.path.join(_STATIC_DIR, filename)

        # Check if variant has CDN URL configured
        if variant_name in _APK_CDN_VARIANTS and _APK_CDN_VARIANTS[variant_name]:
            # Use CDN URL if configured and healthy
            variants[variant_name] = _APK_CDN_VARIANTS[variant_name]
        elif os.path.exists(variant_path):
            # Use local file URL
            variants[variant_name] = f"{base_url.rsplit('/', 1)[0]}/download/{filename}"
        elif variant_name == "universal":
            # Universal always falls back to base URL
            variants[variant_name] = base_url

    # Select URL based on requested architecture
    if arch and arch in variants:
        return variants[arch], variants

    # Default to universal or base URL
    if "universal" in variants:
        return variants["universal"], variants

    return base_url, variants


async def _get_changelog() -> dict:
    """Read changelog from DB."""
    try:
        val = await get_app_config("changelog_data")
        if val:
            return json.loads(val)
    except (json.JSONDecodeError, TypeError):
        pass
        
    return {
        "version": _APP_VERSION,
        "build_number": await _get_min_build_number(),
        "changelog_ar": [],
        "changelog_en": [],
        "release_notes_url": ""
    }


async def _get_update_config() -> dict:
    """Read update configuration from DB."""
    try:
        val = await get_app_config("update_config")
        if val:
            return json.loads(val)
    except (json.JSONDecodeError, TypeError):
        pass
        
    return {
        "is_soft_update": False,
        "priority": UPDATE_PRIORITY_NORMAL,
        "min_soft_update_build": 0,
        "rollout_percentage": 100,
        "effective_from": None,
        "effective_until": None,
        "maintenance_hours": None
    }


# APK Cache for performance (avoid calculating hash on every request)
_APK_CACHE = {
    "sha256": None,
    "size_mb": None,
    "mtime": 0,
    "size_bytes": 0,
    "inode": 0,  # CRITICAL FIX #3: Add inode for reliable file replacement detection
}
_APK_CACHE_LOCK = threading.Lock()

# ETag cache for version check responses
_VERSION_ETAG_LOCK = threading.Lock()
_VERSION_ETAG_CACHE = {}


def _generate_response_etag(response: dict) -> str:
    """Generate ETag from response content."""
    content = json.dumps(response, sort_keys=True, default=str)
    return f'"{hashlib.md5(content.encode()).hexdigest()}"'


def _generate_version_etag(min_build: int, changelog_hash: str, update_config_hash: str) -> str:
    """Generate ETag for version check response."""
    content = f"{min_build}:{changelog_hash}:{update_config_hash}"
    return hashlib.sha256(content.encode()).hexdigest()


# Cache for sync access to avoid async issues
_ETAG_DATA_CACHE = {
    "changelog": None,
    "changelog_mtime": 0,
    "update_config": None,
    "update_config_mtime": 0,
    "min_build_number": 1,
    "min_build_mtime": 0,
}
# CRITICAL FIX #1: Use asyncio.Lock instead of threading.Lock to prevent deadlocks
# threading.Lock blocks the entire event loop when used with await inside
_ETAG_DATA_CACHE_LOCK = asyncio.Lock()
_ETAG_CACHE_TTL = 300  # Cache TTL in seconds (increased from 60s for better performance)


def _get_version_etag_sync() -> str:
    """Get current ETag based on version configuration (sync version for ETag generation).

    This function now uses proper caching to avoid async calls and potential deadlocks.
    The cache is refreshed by the async _refresh_etag_cache() which should be called
    periodically or after admin changes.

    If cache is stale, triggers async refresh and returns a time-based ETag that will
    change when cache refreshes.
    """
    import json
    import asyncio
    global _ETAG_DATA_CACHE

    try:
        current_time = time.time()

        # Try to get from cache first
        changelog_data = _ETAG_DATA_CACHE.get("changelog")
        update_config = _ETAG_DATA_CACHE.get("update_config")
        min_build = _ETAG_DATA_CACHE.get("min_build_number", 1)

        # Check if cache is stale
        cache_age = current_time - _ETAG_DATA_CACHE.get("min_build_mtime", 0)

        # If cache is very old (> TTL), trigger async refresh and return stale marker
        # This ensures clients will refetch when cache refreshes
        if cache_age > _ETAG_CACHE_TTL:
            # Trigger background refresh (fire-and-forget, but don't block response)
            # Note: In production, consider using a background task queue
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    # Schedule refresh in background
                    asyncio.ensure_future(_refresh_etag_cache())
                else:
                    # No running loop, create one temporarily
                    loop.run_until_complete(_refresh_etag_cache())
            except RuntimeError:
                # No event loop available, will refresh on next request
                pass
            
            # Return a time-based ETag that changes when cache refreshes
            # The stale marker ensures clients don't use outdated cached responses
            return _generate_version_etag(
                min_build,
                f"stale_{int(current_time / _ETAG_CACHE_TTL)}",
                "stale"
            )

        if changelog_data is None:
            changelog_str = json.dumps({"version": _APP_VERSION})
        else:
            changelog_str = json.dumps(changelog_data, sort_keys=True)

        if update_config is None:
            update_config_str = json.dumps({"priority": "normal"})
        else:
            update_config_str = json.dumps(update_config, sort_keys=True)

        return _generate_version_etag(
            min_build,
            hashlib.md5(changelog_str.encode()).hexdigest()[:8],
            hashlib.md5(update_config_str.encode()).hexdigest()[:8]
        )
    except Exception as e:
        logger.warning(f"ETag generation failed: {e}")
        return _generate_version_etag(1, "error", "error")


async def _refresh_etag_cache():
    """Refresh the ETag data cache (should be called periodically or after admin changes).
    
    CRITICAL FIX #1: Now uses asyncio.Lock instead of threading.Lock to prevent deadlocks.
    """
    global _ETAG_DATA_CACHE

    # CRITICAL FIX: Use async with for asyncio.Lock instead of sync with
    async with _ETAG_DATA_CACHE_LOCK:
        try:
            _ETAG_DATA_CACHE["changelog"] = await _get_changelog()
            _ETAG_DATA_CACHE["changelog_mtime"] = time.time()
            _ETAG_DATA_CACHE["update_config"] = await _get_update_config()
            _ETAG_DATA_CACHE["update_config_mtime"] = time.time()
            _ETAG_DATA_CACHE["min_build_number"] = await _get_min_build_number()
            _ETAG_DATA_CACHE["min_build_mtime"] = time.time()
        except Exception as e:
            logger.warning(f"ETag cache refresh failed: {e}")


# Alias for backward compatibility
_get_version_etag = _get_version_etag_sync

def _refresh_apk_cache(force: bool = False):
    """Refresh APK cache if file changed or forced.

    CRITICAL FIX #3: Now checks inode (Unix) or volume serial + file index (Windows)
    to detect file replacements that preserve mtime and size.
    
    Checks mtime, size, AND inode for reliable change detection.
    Can be forced via admin endpoint to invalidate cache manually.
    """
    if not os.path.exists(_APK_FILE):
        with _APK_CACHE_LOCK:
            _APK_CACHE["sha256"] = None
            _APK_CACHE["size_mb"] = None
            _APK_CACHE["mtime"] = 0
            _APK_CACHE["size_bytes"] = 0
            _APK_CACHE["inode"] = 0
        return

    try:
        current_mtime = os.path.getmtime(_APK_FILE)
        current_size = os.path.getsize(_APK_FILE)
        
        # CRITICAL FIX #3: Get inode for reliable file replacement detection
        # On Unix: st_ino is the inode number
        # On Windows: st_ino is the file index (combined with volume for uniqueness)
        current_inode = os.stat(_APK_FILE).st_ino

        # Check mtime, size, AND inode for maximum reliability
        # This catches:
        # 1. Normal modifications (mtime changes)
        # 2. File content changes without mtime change (size changes)
        # 3. File replacement with same mtime/size (inode changes)
        should_refresh = (
            force or
            current_mtime != _APK_CACHE.get("mtime", 0) or
            current_size != _APK_CACHE.get("size_bytes", -1) or
            current_inode != _APK_CACHE.get("inode", 0)
        )

        if should_refresh:
            with _APK_CACHE_LOCK:
                # Double-check inside lock (thread-safe)
                if (force or
                    current_mtime != _APK_CACHE.get("mtime", 0) or
                    current_size != _APK_CACHE.get("size_bytes", -1) or
                    current_inode != _APK_CACHE.get("inode", 0)):

                    # Get size
                    _APK_CACHE["size_bytes"] = current_size
                    _APK_CACHE["size_mb"] = round(current_size / (1024 * 1024), 1)

                    # Calculate hash with chunked reading for memory efficiency
                    sha256_hash = hashlib.sha256()
                    with open(_APK_FILE, "rb") as f:
                        for chunk in iter(lambda: f.read(8192), b""):
                            sha256_hash.update(chunk)

                    _APK_CACHE["sha256"] = sha256_hash.hexdigest()
                    _APK_CACHE["mtime"] = current_mtime
                    _APK_CACHE["inode"] = current_inode

                    logger.info(f"APK cache refreshed: size={_APK_CACHE['size_mb']}MB, hash={_APK_CACHE['sha256'][:16]}..., inode={current_inode}")
    except (OSError, IOError) as e:
        logger.error(f"Failed to refresh APK cache: {e}")
        with _APK_CACHE_LOCK:
            _APK_CACHE["sha256"] = None
            _APK_CACHE["size_mb"] = None
            _APK_CACHE["inode"] = 0

def _get_apk_sha256() -> Optional[str]:
    """
    Get cached SHA256 hash of APK file.
    """
    _refresh_apk_cache()
    return _APK_CACHE["sha256"]


def _get_apk_size_mb() -> Optional[float]:
    """
    Get cached APK file size in megabytes.
    """
    _refresh_apk_cache()
    return _APK_CACHE["size_mb"]


def _is_update_active(config: dict) -> tuple[bool, str]:
    """
    Check if update is currently active based on scheduling.

    CRITICAL FIX #8: Fixed maintenance window logic to handle midnight-crossing windows.
    
    Returns:
        Tuple of (is_active, reason)
    """
    now = datetime.now(timezone.utc)

    # Check effective_from
    effective_from = config.get("effective_from")
    if effective_from:
        try:
            from_dt = datetime.fromisoformat(effective_from.replace("Z", "+00:00"))
            if now < from_dt:
                return False, f"Update scheduled for {effective_from}"
        except (ValueError, TypeError):
            pass

    # Check effective_until
    effective_until = config.get("effective_until")
    if effective_until:
        try:
            until_dt = datetime.fromisoformat(effective_until.replace("Z", "+00:00"))
            if now > until_dt:
                return False, "Update window has expired"
        except (ValueError, TypeError):
            pass

    # Check maintenance hours
    maintenance = config.get("maintenance_hours")
    if maintenance:
        try:
            tz_name = maintenance.get("timezone", "UTC")
            try:
                tz = pytz.timezone(tz_name)
            except:
                tz = pytz.UTC

            local_now = datetime.now(tz)
            current_time = local_now.time()
            
            # Parse start and end times
            start_str = maintenance.get("start", "00:00")
            end_str = maintenance.get("end", "24:00")
            start_time = datetime.strptime(start_str, "%H:%M").time()
            end_time = datetime.strptime(end_str, "%H:%M").time()

            # CRITICAL FIX #8: Handle midnight-crossing windows correctly
            # Example: 23:00-02:00 should match 23:30 and 01:00
            if start_time <= end_time:
                # Normal window (e.g., 02:00-04:00)
                if start_time <= current_time <= end_time:
                    return False, f"Maintenance window: {start_str} - {end_str}"
            else:
                # Midnight-crossing window (e.g., 23:00-02:00)
                # Match if current time is >= start OR <= end
                if current_time >= start_time or current_time <= end_time:
                    return False, f"Maintenance window: {start_str} - {end_str}"
        except Exception as e:
            logger.warning(f"Maintenance window check failed: {e}")
            pass

    return True, "Active"




def _is_in_rollout(identifier: str, rollout_percentage: int) -> bool:
    """
    Determine if a user is in the rollout based on their identifier.
    Uses consistent SHA-256 hashing so the same user always gets the same result.
    
    Args:
        identifier: User identifier (license key, device ID, etc.)
        rollout_percentage: Percentage of users to include (0-100)
    
    Returns:
        True if user is in the rollout group
    """
    if rollout_percentage >= 100:
        return True
    if rollout_percentage <= 0:
        return False
    
    # Hash the identifier to get a consistent value 0-99 using SHA-256
    # SHA-256 is more secure than MD5 (which is broken for security purposes)
    hash_value = int(hashlib.sha256(identifier.encode()).hexdigest(), 16) % 100
    return hash_value < rollout_percentage


def _parse_categorized_changelog(changelog_data: dict) -> dict:
    """
    Parse changelog into categorized format.
    Supports both old format (changelog_ar list) and new format (changes list).
    """
    # Check for new categorized format
    if "changes" in changelog_data:
        return {
            "changes": changelog_data["changes"],
            "changelog_ar": [c.get("text_ar", "") for c in changelog_data["changes"]],
            "changelog_en": [c.get("text_en", "") for c in changelog_data["changes"]],
        }

    # Old format - return as-is
    return {
        "changes": [],
        "changelog_ar": changelog_data.get("changelog_ar", []),
        "changelog_en": changelog_data.get("changelog_en", []),
    }


def _get_delta_update_info(
    from_build: Optional[int],
    to_build: int,
    base_url: str
) -> dict:
    """
    Get delta update information if available.
    
    Delta updates allow users to download only the difference between APK versions,
    significantly reducing download size (typically 30-50% of full APK).
    
    To enable:
    1. pip install bsdiff4
    2. Generate patches: python scripts/generate_delta_patch.py
    3. Upload .patch files to static/download/
    
    Args:
        from_build: Current app build number
        to_build: Target build number
        base_url: Base URL for downloads
    
    Returns:
        Delta update info dict
    """
    if from_build is None or from_build >= to_build:
        return {
            "supported": False,
            "from_build": from_build or 0,
            "to_build": to_build,
            "delta_url": None,
            "delta_size_mb": None,
        }
    
    # Check for delta patch file
    delta_file = f"almudeer_{from_build}_to_{to_build}.patch"
    delta_path = os.path.join(_STATIC_DIR, delta_file)
    
    if os.path.exists(delta_path):
        try:
            delta_size_mb = round(os.path.getsize(delta_path) / (1024 * 1024), 1)
            delta_url = f"{base_url.rsplit('/', 1)[0]}/download/{delta_file}"
            
            logger.info(f"Delta update available: {delta_file} ({delta_size_mb}MB)")
            return {
                "supported": True,
                "from_build": from_build,
                "to_build": to_build,
                "delta_url": delta_url,
                "delta_size_mb": delta_size_mb,
            }
        except Exception as e:
            logger.error(f"Error reading delta patch {delta_file}: {e}")
    
    # No delta patch available
    return {
        "supported": False,
        "from_build": from_build,
        "to_build": to_build,
        "delta_url": None,
        "delta_size_mb": None,
    }


@router.get("/api/version", summary="Get current app version (public)")
async def get_version():
    """
    Public endpoint to check current version.
    No authentication required.
    """
    changelog = await _get_changelog()
    return {
        "frontend": _APP_VERSION,
        "backend": _BACKEND_VERSION,
        "min_build_number": await _get_min_build_number(),
        "changelog": changelog.get("changelog_ar", []),
    }


class UpdateCheckResponse(BaseModel):
    """Complete version check response for mobile app force update system"""
    # Core update flags
    update_available: bool
    update_required: bool
    force_update: bool
    
    # Version info
    min_build_number: int
    version: str
    
    # Download info
    update_url: Optional[str] = None
    apk_size_mb: Optional[float] = None
    apk_sha256: Optional[str] = None
    
    # Update metadata
    message: Optional[str] = None
    priority: str = UPDATE_PRIORITY_NORMAL
    changelog: List[str] = []
    changelog_en: List[str] = []
    release_notes_url: Optional[str] = None
    changes: List[dict] = []
    
    # Rollout and scheduling
    rollout_percentage: int = 100
    update_active: bool = True
    update_active_reason: Optional[str] = None
    
    # Security
    apk_signing_fingerprint: Optional[str] = None
    
    # Server time for client sync
    server_time: str = ""
    
    # iOS support
    ios_store_url: Optional[str] = None


@router.get("/check-update")
async def check_update(request: Request, current_version: str = Query(None), platform: str = Query("android")):
    """Internal/Legacy alias for check_app_version"""
    client_ip = _get_client_ip(request)
    allowed, _ = _rate_limiter.is_allowed(client_ip)
    if not allowed:
        from fastapi.responses import JSONResponse
        return JSONResponse(
            status_code=429,
            content={"detail": "Too many requests. Please try again later."},
            headers={"Retry-After": str(_RATE_LIMIT_WINDOW)},
        )
    return await _get_app_version_logic(current_version, platform, client_ip)


@router.get("/api/app/version-check", summary="Mobile app version check (public)")
@router.get("/api/v1/app/version-check", summary="Mobile app version check v1 (public)")
@router.get("/check")
async def check_app_version(
    request: Request, 
    current_version: str = Query(None), 
    platform: str = Query("android"),
    app_build_number: int = Query(None, description="App build number for force update check"),
    language: str = Query("ar", description="Language code: ar, en"),
    arch: str = Query(None, description="Device architecture: arm64_v8a, armeabi_v7a, x86_64, universal"),
    if_none_match: Optional[str] = Header(None, alias="If-None-Match")
):
    """
    Public endpoint for mobile app version check.
    
    Supports both legacy version string checks and new build number-based force updates.
    For force updates, provide app_build_number parameter.
    
    Architecture support:
    - arm64_v8a: Most modern ARM devices (64-bit)
    - armeabi_v7a: Older ARM devices (32-bit)
    - x86_64: Emulators and some tablets
    - universal: All architectures (larger file)

    Supports ETag caching: Send If-None-Match header with previous ETag
    to receive 304 Not Modified if nothing changed.
    
    Rate limiting: Uses device ID (X-Device-ID header) if available,
    otherwise falls back to IP+User-Agent hash to prevent bypass via IP rotation.
    """
    client_ip = _get_client_ip(request)
    device_id = request.headers.get("X-Device-ID")
    
    # Rate limiting: use device ID if available, otherwise IP
    # This prevents bypass via IP rotation (airplane mode, mobile networks)
    allowed, remaining = _rate_limiter.is_allowed(client_ip, device_id=device_id)
    if not allowed:
        logger.warning(f"Rate limited version check from IP: {client_ip}, device_id: {device_id}")
        
        # Calculate dynamic retry-after based on when the oldest request in window expires
        retry_after = _rate_limiter.get_retry_after(client_ip, device_id=device_id)
        
        from fastapi.responses import JSONResponse
        return JSONResponse(
            status_code=429,
            content={
                "detail": "Too many requests. Please try again later.",
                "retry_after_seconds": retry_after,
                "limit": _RATE_LIMIT_REQUESTS,
                "window_seconds": _RATE_LIMIT_WINDOW
            },
            headers={"Retry-After": str(retry_after)},
        )

    logger.info(f"Version check request: build={app_build_number}, platform={platform}, arch={arch}, version={current_version}, ip={client_ip}, device_id={device_id}")

    # Get version check result
    result = await _get_app_version_logic(current_version, platform, client_ip, app_build_number, language, arch)

    # Log update availability for analytics
    if result.get("update_required"):
        logger.info(
            f"FORCE_UPDATE_AVAILABLE: build={app_build_number}, "
            f"min_build={result.get('min_build_number')}, "
            f"device_id={device_id}"
        )
    elif result.get("update_available"):
        logger.info(
            f"SOFT_UPDATE_AVAILABLE: build={app_build_number}, "
            f"min_build={result.get('min_build_number')}, "
            f"device_id={device_id}"
        )

    # Generate ETag for response
    response_etag = _generate_response_etag(result)

    # Check if client has cached version
    if if_none_match and if_none_match == response_etag:
        from fastapi.responses import Response
        logger.debug(f"Cache hit (ETag match): device_id={device_id}")
        return Response(status_code=304, headers={"ETag": response_etag})

    # Add ETag to response
    if isinstance(result, dict):
        result["etag"] = response_etag

    from fastapi.responses import JSONResponse
    return JSONResponse(
        content=result,
        headers={"ETag": response_etag, "Cache-Control": "public, max-age=60"}
    )


async def _get_app_version_logic(
    current_version: Optional[str] = None, 
    platform: str = "android", 
    client_ip: str = "unknown",
    app_build_number: Optional[int] = None,
    language: str = "ar",
    arch: Optional[str] = None
):
    """
    Main version check logic supporting both legacy and new force update system.
    
    If app_build_number is provided, uses build number-based force update logic.
    Otherwise falls back to legacy version string comparison.
    
    Architecture support allows returning architecture-specific APK URLs.
    """
    # Get all configuration
    min_build_number = await _get_min_build_number()
    changelog_data = await _get_changelog()
    update_config = await _get_update_config()
    signing_fingerprint = await _get_apk_signing_fingerprint()
    
    # Refresh APK cache to get current SHA256 and size
    _refresh_apk_cache()
    
    # Check if update is active based on scheduling
    is_update_active, update_active_reason = _is_update_active(update_config)
    
    # Determine update status
    update_available = False
    update_required = False
    force_update = False
    
    if app_build_number is not None:
        # New build number-based force update logic
        update_available = app_build_number < min_build_number
        if not is_update_active:
            # During maintenance windows, suppress ALL update UI
            # to prevent force updates leaking as soft/dismissible prompts
            update_available = False
        force_update = update_available and is_update_active
        update_required = force_update
    elif current_version:
        # Legacy version string comparison
        try:
            config = await get_all_app_config()
            min_version = config.get(f"min_{platform}_version", "1.0.0")
            latest_version = config.get(f"latest_{platform}_version", "1.0.0")
            update_available = latest_version > current_version
            if not is_update_active:
                # During maintenance windows, suppress ALL update UI
                # to prevent force updates leaking as soft/dismissible prompts
                update_available = False
            update_required = update_available and is_update_active
            force_update = update_required
        except Exception:
            update_available = False
    
    # Build response
    # Get architecture-specific APK URL if available
    base_url = await _get_cdn_url() or _APP_DOWNLOAD_URL
    apk_url, apk_variants = await _get_architecture_specific_url(arch, base_url)
    
    response = {
        # Core flags
        "update_available": update_available,
        "update_required": update_required,
        "force_update": force_update,
        
        # Version info
        "min_build_number": min_build_number,
        "version": _APP_VERSION,
        
        # Download info - get CDN URL dynamically if available
        "update_url": apk_url,
        "apk_size_mb": _get_apk_size_mb(),
        "apk_sha256": _get_apk_sha256(),
        
        # Architecture-specific APK URLs
        "apk_arch": arch or "universal",
        "apk_variants": apk_variants,

        # Delta update support - Framework ready for implementation
        # To enable delta updates:
        # 1. pip install bsdiff4
        # 2. Create delta patch files: almudeer_{from}_to_{to}.patch
        # 3. Store them in static/download/
        # 4. Use generate_delta_patch.py script to create patches
        "delta_update": _get_delta_update_info(
            app_build_number, 
            min_build_number, 
            base_url
        ) if app_build_number and app_build_number < min_build_number else {
            "supported": False,
            "from_build": app_build_number if app_build_number else 0,
            "to_build": min_build_number,
            "delta_url": None,
            "delta_size_mb": None,
        },
        
        # Update metadata - include both languages
        "message": _MESSAGES.get(language, _MESSAGES["ar"]).get("update_message") if update_required else None,
        "message_ar": _MESSAGES["ar"].get("update_message") if update_required else None,
        "message_en": _MESSAGES["en"].get("update_message") if update_required else None,
        "priority": update_config.get("priority", UPDATE_PRIORITY_NORMAL),
        "changelog": changelog_data.get("changelog_ar", []),
        "changelog_en": changelog_data.get("changelog_en", []),
        "release_notes_url": changelog_data.get("release_notes_url", ""),
        "changes": changelog_data.get("changes", []),
        
        # Rollout and scheduling
        "rollout_percentage": update_config.get("rollout_percentage", 100),
        "update_active": is_update_active,
        "update_active_reason": update_active_reason if not is_update_active else None,
        
        # Security
        "apk_signing_fingerprint": signing_fingerprint,
        
        # Server time
        "server_time": datetime.now(timezone.utc).isoformat(),
        
        # iOS support
        "ios_store_url": update_config.get("ios_store_url") or _IOS_STORE_URL,
        "ios_app_store_id": update_config.get("ios_app_store_id") or _IOS_APP_STORE_ID,
    }
    
    return response


@router.post("/api/app/set-min-build", summary="Set minimum build number (admin only)")
async def set_min_build_number(
    request: Request,
    build_number: int,
    is_soft_update: bool = False,
    priority: str = UPDATE_PRIORITY_NORMAL,
    ios_store_url: Optional[str] = None,
    ios_app_store_id: Optional[str] = None,
    rollout_percentage: Optional[int] = None,
    maintenance_hours: Optional[dict] = None,
    effective_from: Optional[str] = None,
    effective_until: Optional[str] = None,
    force_downgrade: bool = False,  # CRITICAL FIX #10: Require explicit flag for downgrades
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Manually set the minimum required build number and update configuration.
    Uses DB persistence (Source of Truth).

    CRITICAL FIX #10: Added build number monotonicity validation.
    - Prevents accidental downgrades (setting lower build number than current)
    - Requires force_downgrade=true flag for intentional downgrades
    
    Requires: X-Admin-Key header (and IP whitelist if configured)

    Args:
        build_number: Minimum required build number
        is_soft_update: If true, users can dismiss update
        priority: Update priority (critical/high/normal/low)
        ios_store_url: iOS App Store URL
        ios_app_store_id: iOS App Store ID for deep linking
        rollout_percentage: Phased rollout percentage (0-100)
        maintenance_hours: Maintenance window config {timezone, start, end}
        effective_from: ISO8601 datetime when update becomes active
        effective_until: ISO8601 datetime when update expires
        force_downgrade: If true, allows setting lower build number than current
    """
    # Verify admin access
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )

    if build_number < 1:
        raise HTTPException(
            status_code=400,
            detail=_MESSAGES["ar"]["invalid_build"]
        )

    valid_priorities = [UPDATE_PRIORITY_CRITICAL, UPDATE_PRIORITY_HIGH, UPDATE_PRIORITY_NORMAL, UPDATE_PRIORITY_LOW]
    if priority not in valid_priorities:
        raise HTTPException(
            status_code=400,
            detail=_MESSAGES["ar"]["invalid_priority"].format(priorities=', '.join(valid_priorities))
        )

    # CRITICAL FIX #10: Check for downgrade attempt
    current_min = await _get_min_build_number()
    if build_number < current_min:
        if not force_downgrade:
            logger.warning(
                f"ADMIN ALERT: Attempted to downgrade min_build from {current_min} to {build_number}. "
                f"Blocked unless force_downgrade=true is provided."
            )
            raise HTTPException(
                status_code=400,
                detail=f"Downgrade detected. Current min_build is {current_min}, you're trying to set {build_number}. "
                       f"This would allow users on older builds to continue using the app. "
                       f"If this is intentional, set force_downgrade=true."
            )
        else:
            # Log the intentional downgrade
            logger.warning(
                f"ADMIN ACTION: Intentional downgrade from {current_min} to {build_number} by admin. "
                f"This may allow older builds to continue using the app."
            )

    # Write to DB
    try:
        await set_app_config("min_build_number", str(build_number))

        update_config = {
            "is_soft_update": is_soft_update,
            "priority": priority,
            "min_soft_update_build": 0,
            "ios_store_url": ios_store_url,
            "ios_app_store_id": ios_app_store_id,
            "rollout_percentage": rollout_percentage if rollout_percentage is not None else 100,
            "maintenance_hours": maintenance_hours,
            "effective_from": effective_from,
            "effective_until": effective_until,
        }
        await set_app_config("update_config", json.dumps(update_config))

    except Exception as e:
        logger.error(f"Failed to update min build: {str(e)}", extra={"extra_fields": {"build_number": build_number}})
        raise HTTPException(
            status_code=500,
            detail=_MESSAGES["ar"]["update_failed"].format(error=str(e))
        )

    logger.info(f"App min build updated to {build_number} (soft={is_soft_update}, priority={priority})")

    # Refresh ETag cache after admin change
    await _refresh_etag_cache()

    return {
        "success": True,
        "message": _MESSAGES["ar"]["min_build_updated"],
        "min_build_number": build_number,
        "is_soft_update": is_soft_update,
        "priority": priority,
        "ios_store_url": ios_store_url,
        "rollout_percentage": rollout_percentage,
        "maintenance_hours": maintenance_hours,
        "effective_from": effective_from,
        "effective_until": effective_until,
    }


@router.post("/api/app/set-signing-fingerprint", summary="Set APK signing fingerprint (admin only)")
async def set_signing_fingerprint(
    request: Request,
    fingerprint: str,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Set the SHA256 fingerprint of the APK signing certificate.
    Used for security verification by the mobile app.
    
    Requires: X-Admin-Key header (and IP whitelist if configured)
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    # Basic validation of SHA256 format (hex string, 64 chars) or empty to clear
    clean_fingerprint = fingerprint.strip()
    if clean_fingerprint:
        # Allow colons or spaces in input, strip them for storage
        clean_fingerprint = clean_fingerprint.replace(":", "").replace(" ", "").upper()
        
        # Check if valid hex and length
        import re
        if not re.match(r'^[0-9A-F]{64}$', clean_fingerprint):
             raise HTTPException(
                status_code=400,
                detail="Invalid SHA256 fingerprint format. Must be 64 signs hex string."
            )
    
    try:
        await set_app_config("apk_signing_fingerprint", clean_fingerprint)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to update fingerprint: {str(e)}"
        )
    
    # Refresh ETag cache after admin change
    await _refresh_etag_cache()
    
    return {
        "success": True,
        "message": "APK signing fingerprint updated",
        "fingerprint": clean_fingerprint
    }


@router.post("/api/app/set-changelog", summary="Update changelog (admin only)")
async def set_changelog(
    request: Request,
    changelog_ar: List[str],
    changelog_en: Optional[List[str]] = None,
    release_notes_url: Optional[str] = None,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Update the changelog for the current version.
    
    Requires: X-Admin-Key header (and IP whitelist if configured)
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    try:
        min_build = await _get_min_build_number()
        
        changelog_data = {
            "version": _APP_VERSION,
            "build_number": min_build,
            "changelog_ar": changelog_ar,
            "changelog_en": changelog_en or [],
            "release_notes_url": release_notes_url or ""
        }
        
        await set_app_config("changelog_data", json.dumps(changelog_data))
        
        # Also add to history
        await add_version_history(
            version=_APP_VERSION,
            build_number=min_build,
            changelog_ar="\n".join(changelog_ar),
            changelog_en="\n".join(changelog_en or []),
            changes_json=json.dumps(changelog_data)
        )
        
        # Refresh ETag cache after admin change
        await _refresh_etag_cache()
            
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=_MESSAGES["ar"]["changelog_failed"].format(error=str(e))
        )
    
    return {
        "success": True,
        "message": _MESSAGES["ar"]["changelog_updated"],
        "changelog": changelog_data,
    }


@router.delete("/api/app/force-update", summary="Disable force update (admin only)")
async def disable_force_update(
    request: Request,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Emergency: Reset min build to 0 to stop forcing updates.
    
    Requires: X-Admin-Key header (and IP whitelist if configured)
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    try:
        await set_app_config("min_build_number", "0")
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=_MESSAGES["ar"]["disable_failed"].format(error=str(e))
        )
    
    return {
        "success": True,
        "message": _MESSAGES["ar"]["force_update_disabled"],
        "min_build_number": 0,
    }


# ============ Analytics ============

class UpdateEventRequest(BaseModel):
    """Request model for update analytics events"""
    event: str  # viewed, clicked_update, clicked_later, installed, rolled_back, download_started, download_completed, download_failed, verification_failed
    from_build: int
    to_build: int
    device_id: Optional[str] = None
    device_type: Optional[str] = None  # android, ios, unknown
    license_key: Optional[str] = None
    language: Optional[str] = Query("ar", description="Language code: ar, en")
    # Additional fields for download events
    error_code: Optional[str] = None  # For failure events
    error_message: Optional[str] = None  # For failure events
    download_size_mb: Optional[float] = None  # For download events
    download_duration_seconds: Optional[float] = None  # For download events


@router.post("/api/app/update-event", summary="Track update event (analytics)")
@router.post("/api/v1/app/update-event", summary="Track update event v1 (analytics)")
async def track_update_event(data: UpdateEventRequest):
    """
    Track update-related events for analytics.
    No authentication required (public endpoint for app usage).
    
    Supported events:
    - viewed: User viewed update dialog
    - clicked_update: User clicked update button
    - clicked_later: User deferred update
    - installed: Update installed successfully
    - rolled_back: App was downgraded
    - download_started: APK download began
    - download_completed: APK download finished
    - download_failed: APK download failed
    - verification_failed: SHA256 verification failed
    """
    valid_events = [
        "viewed", "clicked_update", "clicked_later", "installed", "rolled_back",
        "download_started", "download_completed", "download_failed", "verification_failed"
    ]
    if data.event not in valid_events:
        lang = data.language or "ar"
        error_msg = _MESSAGES.get(lang, _MESSAGES["ar"])["invalid_event"].format(events=', '.join(valid_events))
        raise HTTPException(
            status_code=400,
            detail=error_msg
        )

    # Validate device_type if provided
    valid_device_types = ["android", "ios", "unknown", None]
    if data.device_type and data.device_type not in valid_device_types:
        data.device_type = "unknown"

    # Log analytics event to DB
    await save_update_event(
        event=data.event,
        from_build=data.from_build,
        to_build=data.to_build,
        device_id=data.device_id,
        device_type=data.device_type,
        license_key=data.license_key
    )
    
    # Log additional details for download events (store in separate table for detailed analysis)
    if data.event in ["download_started", "download_completed", "download_failed", "verification_failed"]:
        try:
            from database import get_db, execute_sql, commit_db
            async with get_db() as db:
                await execute_sql(db, """
                    INSERT INTO download_events 
                    (event, from_build, to_build, device_id, device_type, 
                     error_code, error_message, download_size_mb, download_duration_seconds, timestamp)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """, [
                    data.event, data.from_build, data.to_build, data.device_id,
                    data.device_type, data.error_code, data.error_message,
                    data.download_size_mb, data.download_duration_seconds
                ])
                await commit_db(db)
        except Exception as e:
            # Non-fatal, don't fail the request
            logger.warning(f"Failed to log download event details: {e}")

    return {"success": True, "message": "Event tracked"}


@router.get("/api/app/update-analytics", summary="Get update analytics (admin only)")
@router.get("/api/v1/app/update-analytics", summary="Get update analytics v1 (admin only)")
async def get_update_analytics(
    request: Request,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Get update analytics summary.
    
    Requires: X-Admin-Key header (and IP whitelist if configured)
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    events: List[Dict[str, Any]] = []
    events = await get_update_events(1000)

    # Calculate summary
    total_views = sum(1 for e in events if e.get("event") == "viewed")
    total_updates = sum(1 for e in events if e.get("event") == "clicked_update")
    total_later = sum(1 for e in events if e.get("event") == "clicked_later")
    total_installed = sum(1 for e in events if e.get("event") == "installed")
    total_rollbacks = sum(1 for e in events if e.get("event") == "rolled_back")

    adoption_rate = round((total_updates / total_views * 100), 1) if total_views > 0 else 0
    rollback_rate = round((total_rollbacks / total_installed * 100), 2) if total_installed > 0 else 0

    # Rollback statistics
    rollback_details = []
    for e in events:
        if e.get("event") == "rolled_back":
            rollback_details.append({
                "from_build": e.get("from_build"),
                "to_build": e.get("to_build"),
                "device_type": e.get("device_type"),
                "timestamp": str(e.get("timestamp", ""))
            })

    # Device type breakdown
    by_device_type = {
        "android": {
            "views": sum(1 for e in events if e.get("event") == "viewed" and e.get("device_type") == "android"),
            "updates": sum(1 for e in events if e.get("event") == "clicked_update" and e.get("device_type") == "android"),
            "later": sum(1 for e in events if e.get("event") == "clicked_later" and e.get("device_type") == "android"),
            "installed": sum(1 for e in events if e.get("event") == "installed" and e.get("device_type") == "android"),
            "rollbacks": sum(1 for e in events if e.get("event") == "rolled_back" and e.get("device_type") == "android"),
        },
        "ios": {
            "views": sum(1 for e in events if e.get("event") == "viewed" and e.get("device_type") == "ios"),
            "updates": sum(1 for e in events if e.get("event") == "clicked_update" and e.get("device_type") == "ios"),
            "later": sum(1 for e in events if e.get("event") == "clicked_later" and e.get("device_type") == "ios"),
            "installed": sum(1 for e in events if e.get("event") == "installed" and e.get("device_type") == "ios"),
            "rollbacks": sum(1 for e in events if e.get("event") == "rolled_back" and e.get("device_type") == "ios"),
        },
    }

    return {
        "total_views": total_views,
        "total_updates": total_updates,
        "total_later": total_later,
        "total_installed": total_installed,
        "total_rollbacks": total_rollbacks,
        "adoption_rate": adoption_rate,
        "rollback_rate": rollback_rate,
        "rollback_details": rollback_details[:20],  # Last 20 rollbacks
        "by_device_type": by_device_type,
        "recent_events": events[:50],
    }


# ============ APK Download ============

@router.get("/apk", summary="Redirect to latest APK download (short URL)")
async def redirect_to_apk(
    request: Request,
    arch: Optional[str] = Query(None, description="Device architecture override")
):
    """
    Redirect /apk to the correct APK download URL based on device architecture.

    Users can access: https://almudeer.royaraqamia.com/apk
    This will redirect them to the correct APK for their device.

    Architecture detection:
    1. Query parameter: ?arch=arm64_v8a (explicit override)
    2. User-Agent header (automatic detection)
    3. Fallback to universal APK for non-Android devices

    Benefits:
    - Short, memorable URL for users
    - Automatic architecture detection for Android
    - Universal APK fallback for PC/iOS users
    - Can switch CDN without updating users
    - Track download analytics
    """
    # Get user architecture from query or User-Agent
    if arch:
        # Explicit architecture override - assume Android
        device_arch = arch
        is_android = True
    else:
        device_arch, is_android = _detect_device_arch(request)

    # Get architecture-specific CDN URL
    cdn_url = _get_architecture_cdn_url(device_arch)

    # Log download event
    device_type = "android" if is_android else "desktop/ios"
    logger.info(f"APK redirect: arch={device_arch}, device={device_type}, url={cdn_url}")

    from fastapi.responses import RedirectResponse
    return RedirectResponse(url=cdn_url, status_code=302)


def _detect_device_arch(request: Request) -> tuple[str, bool]:
    """
    Detect device architecture from User-Agent header.

    Returns:
        Tuple of (architecture, is_android)
        - architecture: 'arm64_v8a', 'armeabi_v7a', 'x86_64', or 'universal'
        - is_android: True if device is Android, False otherwise
    """
    user_agent = request.headers.get("User-Agent", "").lower()

    # Android User-Agent patterns
    if "android" in user_agent:
        # Check for 64-bit ARM (most modern devices)
        if any(pattern in user_agent for pattern in ["arm64", "aarch64", "armv8"]):
            return "arm64_v8a", True

        # Check for 32-bit ARM (older devices)
        if any(pattern in user_agent for pattern in ["armv7", "armeabi"]):
            return "armeabi_v7a", True

        # Check for x86_64 (tablets, emulators)
        if "x86_64" in user_agent or "x64" in user_agent:
            return "x86_64", True

        # Default to ARM64 for most Android devices (safe assumption in 2026)
        return "arm64_v8a", True

    # iOS - not supported for APK download
    if "iphone" in user_agent or "ipad" in user_agent:
        return "universal", False

    # Desktop/Unknown (Windows, Mac, Linux) - return universal for manual download
    return "universal", False


def _get_architecture_cdn_url(arch: str) -> str:
    """
    Get CDN URL for specific architecture.

    Falls back to universal APK if architecture-specific URL not configured.
    """
    # Architecture-specific URLs from environment
    arch_urls = {
        "universal": os.getenv("APK_CDN_URL_UNIVERSAL", ""),
        "arm64_v8a": os.getenv("APK_CDN_URL_ARM64", ""),
        "armeabi_v7a": os.getenv("APK_CDN_URL_ARMV7", ""),
        "x86_64": os.getenv("APK_CDN_URL_X86", ""),
    }

    # Try architecture-specific URL first
    url = arch_urls.get(arch, "")
    if url:
        return url

    # Fallback to universal
    return arch_urls["universal"]


@router.head("/download/almudeer.apk", summary="Check APK file info (HEAD)")
async def head_apk():
    """
    Return APK file headers without body.
    Allows clients to check file existence and size before downloading.
    """
    if not os.path.exists(_APK_FILE):
        raise HTTPException(
            status_code=404,
            detail="APK file not found. Please contact support."
        )

    file_size = os.path.getsize(_APK_FILE)
    max_size_bytes = _MAX_APK_SIZE_MB * 1024 * 1024
    
    if file_size > max_size_bytes:
        logger.error(f"APK file too large: {file_size} bytes (max: {max_size_bytes})")
        raise HTTPException(
            status_code=500,
            detail="APK file exceeds size limit. Please contact support."
        )

    return Response(
        headers={
            "Content-Length": str(file_size),
            "Content-Type": "application/vnd.android.package-archive",
            "Accept-Ranges": "bytes",
            "Content-Disposition": "attachment; filename=almudeer.apk"
        }
    )


@router.get("/download/almudeer.apk", summary="Download mobile app APK")
async def download_apk():
    """
    Download the Al-Mudeer mobile app APK.
    Returns the APK file with proper headers for browser download.
    
    Security: Validates file size before serving to prevent DoS.
    """
    if not os.path.exists(_APK_FILE):
        raise HTTPException(
            status_code=404,
            detail="APK file not found. Please contact support."
        )

    # Validate file size
    file_size = os.path.getsize(_APK_FILE)
    max_size_bytes = _MAX_APK_SIZE_MB * 1024 * 1024
    
    if file_size > max_size_bytes:
        logger.error(f"APK file too large: {file_size} bytes (max: {max_size_bytes})")
        raise HTTPException(
            status_code=500,
            detail="APK file exceeds size limit. Please contact support."
        )

    return FileResponse(
        path=_APK_FILE,
        filename="almudeer.apk",
        media_type="application/vnd.android.package-archive",
        headers={
            "Content-Disposition": "attachment; filename=almudeer.apk",
            "Accept-Ranges": "bytes",
            # Critical: Prevent caching of the APK file
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0",
        }
    )


# ============ Version History ============

@router.get("/api/app/versions", summary="Get version history (public)")
async def get_version_history(
    limit: int = Query(5, ge=1, le=20, description="Number of versions to return")
):
    """
    Get changelog history for multiple versions.
    """
    return {
        "versions": await get_version_history_list(limit)
    }


# ============ Admin Dashboard API ============

@router.get("/api/admin/dashboard", summary="Get admin dashboard data")
async def get_admin_dashboard(
    request: Request,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Get comprehensive dashboard data for admin panel.
    
    Returns:
    - Current version info
    - Update status
    - Analytics summary
    - Available APK variants
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    # Get current version info
    min_build = await _get_min_build_number()
    changelog = await _get_changelog()
    update_config = await _get_update_config()
    
    # Get analytics
    events = await get_update_events(100)
    total_views = sum(1 for e in events if e.get("event") == "viewed")
    total_updates = sum(1 for e in events if e.get("event") == "clicked_update")
    total_installed = sum(1 for e in events if e.get("event") == "installed")
    adoption_rate = round((total_updates / total_views * 100), 1) if total_views > 0 else 0
    
    # Get version distribution
    try:
        from database import get_version_distribution
        version_dist = await get_version_distribution()
    except:
        version_dist = []
    
    # Check available APK variants
    available_variants = []
    for variant_name, filename in _APK_VARIANTS.items():
        variant_path = os.path.join(_STATIC_DIR, filename)
        if os.path.exists(variant_path):
            size_mb = round(os.path.getsize(variant_path) / (1024 * 1024), 1)
            available_variants.append({
                "name": variant_name,
                "filename": filename,
                "size_mb": size_mb,
                "has_cdn": bool(_APK_CDN_VARIANTS.get(variant_name))
            })

    # Get CDN health status
    cdn_health_status = {}
    for arch in _APK_VARIANTS.keys():
        cache = _CDN_HEALTH_CACHE.get(arch, {})
        cdn_health_status[arch] = {
            "healthy": cache.get("healthy", None),  # None = not checked yet
            "last_check": cache.get("last_check", 0),
            "has_cdn_configured": bool(_APK_CDN_VARIANTS.get(arch))
        }

    return {
        "version": {
            "current": _APP_VERSION,
            "min_build_number": min_build,
            "backend_version": _BACKEND_VERSION,
        },
        "update_config": {
            "is_soft_update": update_config.get("is_soft_update", False),
            "priority": update_config.get("priority", "normal"),
            "rollout_percentage": update_config.get("rollout_percentage", 100),
            "update_active": _is_update_active(update_config)[0],  # ✅ Actual check
            "update_active_reason": _is_update_active(update_config)[1],
        },
        "changelog": changelog,
        "analytics": {
            "total_views": total_views,
            "total_updates": total_updates,
            "total_installed": total_installed,
            "adoption_rate": adoption_rate,
            "version_distribution": version_dist,
        },
        "apk": {
            "available_variants": available_variants,
            "cdn_enabled": bool(_APK_CDN_URL),
            "health_status": cdn_health_status,  # ✅ CDN health monitoring
        },
        # CRITICAL FIX #12: Removed sensitive security info from dashboard
        # Security configuration should only be viewed via dedicated security endpoints
        # with additional authentication layers
    }


@router.get("/api/admin/config", summary="Get current configuration")
async def get_admin_config(
    request: Request,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Get current app configuration (admin view with sensitive data).
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    config = await get_all_app_config()
    
    # Mask sensitive values
    if config.get("apk_signing_fingerprint"):
        config["apk_signing_fingerprint"] = "***configured***"
    if config.get("update_config"):
        import json
        try:
            update_cfg = json.loads(config["update_config"])
            if update_cfg.get("ios_store_url"):
                update_cfg["ios_store_url"] = "***configured***"
            config["update_config"] = json.dumps(update_cfg)
        except:
            pass
    
    return config


@router.post("/api/admin/batch-update", summary="Batch update configuration")
async def batch_update_config(
    request: Request,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key"),
    min_build_number: Optional[int] = None,
    is_soft_update: Optional[bool] = None,
    priority: Optional[str] = None,
    rollout_percentage: Optional[int] = None,
    changelog_ar: Optional[List[str]] = None,
    changelog_en: Optional[List[str]] = None,
):
    """
    Batch update multiple configuration values at once.
    More efficient than making multiple API calls.
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )
    
    results = []
    
    # Update min build number
    if min_build_number is not None:
        try:
            await set_app_config("min_build_number", str(min_build_number))
            results.append({"field": "min_build_number", "success": True})
        except Exception as e:
            results.append({"field": "min_build_number", "success": False, "error": str(e)})
    
    # Get existing update config and update
    if any(x is not None for x in [is_soft_update, priority, rollout_percentage]):
        try:
            existing_config = await _get_update_config()
            existing_config["is_soft_update"] = is_soft_update if is_soft_update is not None else existing_config.get("is_soft_update", False)
            existing_config["priority"] = priority if priority else existing_config.get("priority", "normal")
            existing_config["rollout_percentage"] = rollout_percentage if rollout_percentage is not None else existing_config.get("rollout_percentage", 100)
            await set_app_config("update_config", json.dumps(existing_config))
            results.append({"field": "update_config", "success": True})
        except Exception as e:
            results.append({"field": "update_config", "success": False, "error": str(e)})
    
    # Update changelog
    if changelog_ar is not None:
        try:
            min_build = await _get_min_build_number()
            changelog_data = {
                "version": _APP_VERSION,
                "build_number": min_build,
                "changelog_ar": changelog_ar,
                "changelog_en": changelog_en or [],
            }
            await set_app_config("changelog_data", json.dumps(changelog_data))
            results.append({"field": "changelog_data", "success": True})
        except Exception as e:
            results.append({"field": "changelog_data", "success": False, "error": str(e)})
    
    # Refresh cache after batch update
    await _refresh_etag_cache()
    
    return {
        "success": True,
        "results": results,
    }


@router.post("/api/admin/invalidate-apk-cache", summary="Invalidate APK cache (admin only)")
async def invalidate_apk_cache(
    request: Request,
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key")
):
    """
    Force invalidate and refresh the APK cache.
    
    Use this endpoint after uploading a new APK file to ensure
    the backend immediately picks up the new file's hash and size.
    
    Requires: X-Admin-Key header (and IP whitelist if configured)
    """
    if not _check_admin_access(request, x_admin_key):
        raise HTTPException(
            status_code=403,
            detail=_MESSAGES["ar"]["admin_required"]
        )

    # Force refresh the cache
    _refresh_apk_cache(force=True)

    logger.info("APK cache invalidated by admin")

    return {
        "success": True,
        "message": "APK cache invalidated and refreshed",
        "sha256": _APK_CACHE.get("sha256"),
        "size_mb": _APK_CACHE.get("size_mb"),
    }
