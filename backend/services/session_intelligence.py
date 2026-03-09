"""
Al-Mudeer - Session Intelligence Service
Handles GeoIP resolution and User-Agent parsing to provide context for device sessions.
"""

import httpx
import re
from datetime import datetime, timedelta
from typing import Dict, Optional
from logging_config import get_logger

logger = get_logger(__name__)

# Cache for GeoIP to avoid redundant API calls
# In production, this should be moved to Redis
# MEDIUM FIX #6: Added TTL to prevent stale data
_geoip_cache: dict[str, tuple[str, datetime]] = {}
_GEOIP_CACHE_TTL = timedelta(hours=24)  # Cache for 24 hours

async def resolve_location(ip: str) -> str:
    """
    Resolve IP address to a human-readable location (City, Country).
    Uses ip-api.com (Free tier: 45 requests/min).

    MEDIUM FIX #6: Added TTL-based caching to reduce API calls
    """
    if not ip or ip in ("127.0.0.1", "localhost", "::1"):
        return "Local Network"

    # Check cache with TTL
    if ip in _geoip_cache:
        cached_value, cached_time = _geoip_cache[ip]
        # P2-9 FIX: Use timezone-aware datetime instead of deprecated utcnow()
        from datetime import timezone
        if datetime.now(timezone.utc) - cached_time.replace(tzinfo=timezone.utc) < _GEOIP_CACHE_TTL:
            return cached_value
        else:
            # Cache expired, remove it
            del _geoip_cache[ip]

    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            # SECURITY: Use HTTPS to prevent MITM attacks on location data
            # ip-api.com free tier does NOT support HTTPS, so we use ipapi.co instead
            # ipapi.co free tier: 1000 requests/month, HTTPS supported
            response = await client.get(f"https://ipapi.co/{ip}/json/")
            if response.status_code == 200:
                data = response.json()
                if not data.get("error"):
                    city = data.get("city", "")
                    country = data.get("country_name", "")
                    if city or country:
                        location = f"{city}, {country}".strip(", ")
                        # P2-9 FIX: Use timezone-aware datetime
                        from datetime import timezone
                        _geoip_cache[ip] = (location, datetime.now(timezone.utc))
                        return location
    except Exception as e:
        logger.debug(f"GeoIP resolution failed for {ip}: {e}")

    return "Unknown Location"

def parse_device_info(ua_string: Optional[str]) -> str:
    """
    Extract readable device info from User-Agent string.
    Basic regex-based parser (can be upgraded to 'user-agents' library).
    """
    if not ua_string:
        return "Unknown Device"
    
    # Common Patterns
    # iOS: ... (iPhone; CPU iPhone OS 17_0 like Mac OS X) ...
    # Android: ... (Linux; Android 14; Pixel 7) ...
    # Windows: ... (Windows NT 10.0; Win64; x64) ...
    
    ua = ua_string
    
    # 1. Check for Mobile Devices
    if "iPhone" in ua:
        model_match = re.search(r'iPhone OS ([\d_]+)', ua)
        version = model_match.group(1).replace('_', '.') if model_match else ""
        return f"iPhone (iOS {version})" if version else "iPhone"
    
    if "Android" in ua:
        # Try to find device model: (Linux; Android 14; SM-S911B)
        android_match = re.search(r'Android ([\d.]+); ([^;)]+)', ua)
        if android_match:
            version = android_match.group(1)
            model = android_match.group(2).strip()
            return f"{model} (Android {version})"
        return "Android Device"
    
    if "iPad" in ua:
        return "iPad"
    
    # 2. Check for Desktop
    if "Windows NT" in ua:
        return "Windows PC"
    
    if "Macintosh" in ua:
        return "Mac"
    
    if "Linux" in ua and "Android" not in ua:
        return "Linux PC"
    
    # 3. Last resort: just common browser
    if "Chrome" in ua: return "Chrome Browser"
    if "Safari" in ua: return "Safari Browser"
    if "Firefox" in ua: return "Firefox Browser"
    
    return "Unknown Device"
