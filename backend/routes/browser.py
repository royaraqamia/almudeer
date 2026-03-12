import logging
import asyncio
import unicodedata
import re
import html
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, Request
from pydantic import BaseModel, HttpUrl, field_validator
from typing import Optional
import httpx
from bs4 import BeautifulSoup
import bleach
import tempfile
import os
import uuid
from datetime import datetime, timedelta
from collections import OrderedDict
from dataclasses import dataclass, field

import ipaddress
import socket
from urllib.parse import urlparse, urljoin

from dependencies import get_current_user, get_license_from_header
from models.library import add_library_item
from services.file_storage_service import get_file_storage
from rate_limiting import limiter, RateLimits, limit_browser_scrape, limit_browser_preview
from services.jwt_auth import verify_token_async, TokenType, security
from fastapi.security import HTTPAuthorizationCredentials

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/browser", tags=["browser"])

MAX_CONTENT_SIZE = 2 * 1024 * 1024  # 2MB max content
MAX_IMAGES = 10
DEFAULT_TIMEOUT = 15.0
SCRAPE_TIMEOUT = 30.0

# Allowed content types for web scraping
ALLOWED_CONTENT_TYPES = [
    'text/html',
    'application/xhtml+xml',
    'text/plain',
]

# Transparent bot User-Agent
BOT_USER_AGENT = "AlMudeerBot/1.0 (+https://almudeer.app/bot)"

# Circuit breaker configuration
CIRCUIT_BREAKER_FAILURE_THRESHOLD = 5
CIRCUIT_BREAKER_RECOVERY_TIMEOUT = 60  # seconds
CIRCUIT_BREAKER_TIMEOUT = 30  # seconds for request timeout


@dataclass
class CircuitBreakerState:
    """Circuit breaker state for a specific host"""
    failures: int = 0
    last_failure_time: float = 0
    state: str = "closed"  # closed, open, half-open
    success_count: int = 0


class CircuitBreaker:
    """
    Circuit breaker pattern implementation for external HTTP requests.
    Prevents cascading failures when target services are unavailable.
    """
    def __init__(self, failure_threshold: int = CIRCUIT_BREAKER_FAILURE_THRESHOLD,
                 recovery_timeout: int = CIRCUIT_BREAKER_RECOVERY_TIMEOUT):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.states: dict[str, CircuitBreakerState] = {}
        self._lock = asyncio.Lock()

    async def _get_state(self, host: str) -> CircuitBreakerState:
        """Get or create state for a host (thread-safe)"""
        async with self._lock:
            if host not in self.states:
                self.states[host] = CircuitBreakerState()
            return self.states[host]

    async def record_success(self, host: str):
        """Record a successful request"""
        async with self._lock:
            if host not in self.states:
                self.states[host] = CircuitBreakerState()
            state = self.states[host]
            if state.state == "half-open":
                state.success_count += 1
                if state.success_count >= 2:
                    # Reset after 2 successful requests in half-open state
                    state.state = "closed"
                    state.failures = 0
                    state.success_count = 0
                    logger.info(f"Circuit breaker CLOSED for {host} (recovered)")
            elif state.state == "closed":
                state.failures = 0

    async def record_failure(self, host: str):
        """Record a failed request"""
        import time
        async with self._lock:
            if host not in self.states:
                self.states[host] = CircuitBreakerState()
            state = self.states[host]
            state.failures += 1
            state.last_failure_time = time.time()

            # If failure occurs during half-open state, reset to open immediately
            if state.state == "half-open":
                state.state = "open"
                state.success_count = 0
                logger.warning(f"Circuit breaker re-OPENED for {host} (recovery failed)")
            elif state.failures >= self.failure_threshold:
                state.state = "open"
                logger.warning(f"Circuit breaker OPENED for {host} (failures: {state.failures})")

    async def can_execute(self, host: str) -> bool:
        """Check if request can be executed"""
        import time
        async with self._lock:
            if host not in self.states:
                self.states[host] = CircuitBreakerState()
            state = self.states[host]

            if state.state == "closed":
                return True

            if state.state == "open":
                # Check if recovery timeout has passed
                if time.time() - state.last_failure_time > self.recovery_timeout:
                    state.state = "half-open"
                    state.success_count = 0
                    logger.info(f"Circuit breaker HALF-OPEN for {host} (testing recovery)")
                    return True
                return False

            # half-open: allow one request to test
            return True

    async def get_status(self, host: str) -> dict:
        """Get circuit breaker status for a host"""
        async with self._lock:
            if host not in self.states:
                self.states[host] = CircuitBreakerState()
            state = self.states[host]
            return {
                "state": state.state,
                "failures": state.failures,
                "last_failure_time": state.last_failure_time,
            }

    async def get_all_status(self) -> dict[str, dict]:
        """Get circuit breaker status for all hosts (for monitoring)"""
        async with self._lock:
            return {
                host: {
                    "state": state.state,
                    "failures": state.failures,
                    "last_failure_time": state.last_failure_time,
                }
                for host, state in self.states.items()
            }


# Global circuit breaker instance
_circuit_breaker = CircuitBreaker()

# Homograph attack detection: Confusable characters that look like Latin letters
HOMOGRAPH_PATTERNS = {
    'a': ['а', 'ɑ', 'α', 'ａ'],  # Cyrillic, Latin alpha, Greek alpha, fullwidth
    'c': ['с', 'ϲ', 'ⅽ', 'c'],  # Cyrillic, Greek lunate sigma, Roman numeral
    'e': ['е', 'ε', 'ｅ'],  # Cyrillic, Greek epsilon, fullwidth
    'i': ['і', 'ι', 'ⅰ', 'i'],  # Cyrillic, Greek iota, Roman numeral
    'o': ['о', 'ο', 'ο', '0', 'ｏ'],  # Cyrillic, Greek omicron, digit zero, fullwidth
    'p': ['р', 'ρ', 'ρ', 'ｐ'],  # Cyrillic, Greek rho, fullwidth
    's': ['ѕ', 'ｓ'],  # Cyrillic, fullwidth
    'x': ['х', 'χ', '×', 'ｘ'],  # Cyrillic, Greek chi, multiplication sign
    'y': ['у', 'γ', 'у', 'ｙ'],  # Cyrillic, Greek gamma, fullwidth
    'm': ['м', 'μ', 'ｍ'],  # Cyrillic, Greek mu, fullwidth
    'n': ['н', 'ν', 'ｎ'],  # Cyrillic, Greek nu, fullwidth
    'r': ['г', 'ｒ'],  # Cyrillic, fullwidth
    'u': ['υ', 'ｕ'],  # Greek upsilon, fullwidth
    'k': ['κ', 'ｋ'],  # Greek kappa, fullwidth
    'b': ['ь', 'β', 'ｂ'],  # Cyrillic soft sign, Greek beta, fullwidth
    'd': ['ԁ', 'δ', 'd'],  # Cyrillic, Greek delta, fullwidth
    'g': ['ɡ', 'γ', 'g'],  # Latin script g, Greek gamma, fullwidth
    'h': ['һ', 'η', 'h'],  # Cyrillic, Greek eta, fullwidth
    'j': ['ј', 'j'],  # Cyrillic, fullwidth
    'l': ['ӏ', 'λ', 'l'],  # Cyrillic palochka, Greek lambda, fullwidth
    'q': ['ԛ', 'q'],  # Cyrillic schwa, fullwidth
    't': ['т', 'τ', 't'],  # Cyrillic, Greek tau, fullwidth
    'v': ['ѵ', 'ν', 'v'],  # Cyrillic izhitsa, Greek nu, fullwidth
    'w': ['ԝ', 'ω', 'w'],  # Cyrillic we, Greek omega, fullwidth
    'z': ['ᴢ', 'ζ', 'z'],  # Latin letter z, Greek zeta, fullwidth
}

# Build reverse mapping for detection
CONFUSABLE_CHARS = set()
for replacements in HOMOGRAPH_PATTERNS.values():
    CONFUSABLE_CHARS.update(replacements)

# Preview cache with thread-safe locking and LRU eviction
# CRITICAL FIX: Use OrderedDict for proper LRU cache with hard limit
_preview_cache: OrderedDict[str, dict] = OrderedDict()
_CACHE_MAX_SIZE = 100  # Hard limit on cache entries
_cache_ttl = timedelta(minutes=15)
_cache_lock = asyncio.Lock()

async def _clean_preview_cache():
    """Clean old cache entries based on TTL (thread-safe)"""
    try:
        async with asyncio.timeout(5.0):  # 5 second timeout to prevent blocking
            async with _cache_lock:
                now = datetime.now()
                expired_keys = [
                    k for k, v in _preview_cache.items()
                    if (now - v['timestamp']) > _cache_ttl
                ]
                for key in expired_keys:
                    _preview_cache.pop(key, None)

                # Enforce hard size limit with LRU eviction
                while len(_preview_cache) > _CACHE_MAX_SIZE:
                    # Remove oldest (first) item - LRU eviction
                    _preview_cache.popitem(last=False)
    except asyncio.TimeoutError:
        logger.warning("Cache cleanup timed out - skipping until next run")


async def _get_cached_preview(url: str) -> Optional[dict]:
    """Get cached preview with LRU touch (thread-safe)"""
    async with _cache_lock:
        if url not in _preview_cache:
            return None
        cached = _preview_cache[url]
        if (datetime.now() - cached['timestamp']) > _cache_ttl:
            _preview_cache.pop(url, None)
            return None
        # Touch: move to end (most recently used)
        _preview_cache.move_to_end(url)
        return cached['data']


async def _set_cached_preview(url: str, data: dict):
    """Set cached preview with LRU eviction (thread-safe)"""
    async with _cache_lock:
        # If URL already exists, remove it first to update LRU order
        if url in _preview_cache:
            _preview_cache.pop(url)
        # Enforce hard size limit with LRU eviction BEFORE adding new entry
        # This prevents cache from exceeding _CACHE_MAX_SIZE
        elif len(_preview_cache) >= _CACHE_MAX_SIZE:
            # Evict oldest (first) item - LRU eviction
            _preview_cache.popitem(last=False)

        _preview_cache[url] = {
            'timestamp': datetime.now(),
            'data': data
        }


async def _clean_preview_cache_background():
    """Clean cache in background without holding locks"""
    try:
        await _clean_preview_cache()
    except Exception as e:
        logger.warning(f"Cache cleanup failed: {e}")

# Blocked URL patterns (internal networks, etc.)
BLOCKED_URL_PATTERNS = [
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "::1",
    ".local",
    ".internal",
    "192.168.",
    "10.",
    "172.16.",
    "172.17.",
    "172.18.",
    "172.19.",
    "172.20.",
    "172.21.",
    "172.22.",
    "172.23.",
    "172.24.",
    "172.25.",
    "172.26.",
    "172.27.",
    "172.28.",
    "172.29.",
    "172.30.",
    "172.31.",
    "169.254.",
    "0.0.0.0",
]


def _is_safe_url(url: str) -> bool:
    """
    SSRF Protection: Validate that a URL does not resolve to a private/internal IP.
    This should be called before making any HTTP request.
    """
    try:
        parsed = urlparse(url)
        host = parsed.netloc.lower()
        
        # Handle URLs with credentials (user:pass@host)
        # Extract the actual hostname after the @
        if '@' in host:
            host = host.split('@')[-1]
        
        # Handle IPv6 addresses
        if host.startswith('[') and host.endswith(']'):
            ipv6_addr = host[1:-1]
            try:
                ip = ipaddress.ip_address(ipv6_addr)
                if ip.is_loopback or ip.is_private or ip.is_link_local:
                    return False
            except ValueError:
                pass
            # For IPv6, if we can't parse it, be safe and block
            return False
        
        # Extract hostname without port
        if ":" in host:
            host = host.split(":")[0]
        
        # Check blocked patterns FIRST (before DNS resolution)
        # This catches .local, .internal, and private IP patterns
        for pattern in BLOCKED_URL_PATTERNS:
            if host == pattern or host.endswith(f".{pattern}"):
                return False

        # Resolve and check IP
        try:
            ip_address = socket.gethostbyname(host)
            ip = ipaddress.ip_address(ip_address)
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
                return False
        except socket.gaierror:
            # DNS resolution failure - be safe and block unknown hosts
            # This prevents accessing internal hosts that don't resolve publicly
            return False

        return True
    except Exception:
        return False


def _detect_homograph_attack(host: str) -> bool:
    """
    Detect homograph/punycode attacks where confusable characters
    are used to impersonate legitimate domains.
    
    Examples:
        - facebоok.com (Cyrillic 'о' instead of Latin 'o')
        - gοogle.com (Greek omicron instead of Latin 'o')
        - micrоsoft.cοm (Mixed scripts)
    
    Returns True if a potential homograph attack is detected.
    """
    if not host:
        return False
    
    # Normalize to NFKC form (converts compatibility characters)
    normalized = unicodedata.normalize('NFKC', host)
    
    # If normalization changes the string significantly, suspicious
    if normalized != host:
        # Check if the difference is just punycode-compatible chars
        # If so, allow it (e.g., legitimate internationalized domains)
        pass
    
    # Check for mixed scripts (strong indicator of homograph attack)
    has_latin = any('\u0000' <= c <= '\u007f' for c in host)
    has_cyrillic = any('\u0400' <= c <= '\u04FF' for c in host)
    has_greek = any('\u0370' <= c <= '\u03FF' for c in host)
    has_fullwidth = any('\uFF00' <= c <= '\uFFEF' for c in host)
    
    # Count how many different scripts are present
    script_count = sum([has_latin, has_cyrillic, has_greek, has_fullwidth])
    
    # If multiple scripts detected, likely a homograph attack
    if script_count >= 2:
        logger.warning(f"Potential homograph attack detected: {host} (mixed scripts)")
        return True
    
    # Check for known confusable characters
    for char in host:
        if char in CONFUSABLE_CHARS:
            # Found a confusable character - check if it's in a suspicious context
            char_category = unicodedata.category(char)
            char_name = unicodedata.name(char, '').lower()
            
            # Flag if it's a letter that could be confused with Latin
            if any(confusable in char_name for confusable in [
                'cyrillic', 'greek', 'fullwidth', 'modifier'
            ]):
                logger.warning(f"Confusable character detected in hostname: {host} (char: {char})")
                return True
    
    return False


class ScrapeRequest(BaseModel):
    url: str
    format: str = "markdown"
    include_images: bool = True

    @field_validator('url')
    @classmethod
    def validate_url(cls, v):
        if not v or not v.strip():
            raise ValueError('URL cannot be empty')

        # URL length validation to prevent DoS attacks
        # Most browsers limit URLs to 2048 characters
        if len(v) > 2048:
            raise ValueError('URL too long (max 2048 characters)')

        # Add scheme if missing
        if not v.startswith(('http://', 'https://')):
            v = 'https://' + v

        # Validate URL format
        try:
            parsed = urlparse(v)
            if not parsed.scheme or not parsed.netloc:
                raise ValueError('Invalid URL format')

            # Check for blocked patterns in hostname
            host = parsed.netloc.lower()
            if ":" in host:
                host = host.split(":")[0]

            for pattern in BLOCKED_URL_PATTERNS:
                if host == pattern or host.endswith(f".{pattern}"):
                    raise ValueError(f'URL pattern blocked: {pattern}')

            # Homograph Attack Detection
            if _detect_homograph_attack(host):
                raise ValueError('Potential homograph attack detected (mixed scripts or confusable characters)')

            # Robust SSRF Protection: Resolve DNS and check IP ranges
            try:
                ip_address = socket.gethostbyname(host)
                ip = ipaddress.ip_address(ip_address)

                if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
                    raise ValueError(f'Access to private/reserved IP {ip_address} is blocked')
            except socket.gaierror:
                # DNS resolution failure is handled during the actual request
                pass
            except Exception as e:
                if isinstance(e, ValueError): raise
                # Ignore other IP validation errors, let httpx handle it
                pass

        except Exception as e:
            if isinstance(e, ValueError):
                raise
            raise ValueError(f'Invalid URL: {str(e)}')

        return v
    
    @field_validator('format')
    @classmethod
    def validate_format(cls, v):
        if v not in ['markdown', 'html']:
            raise ValueError('Format must be "markdown" or "html"')
        return v


class ScrapeResponse(BaseModel):
    success: bool
    title: Optional[str] = None
    content: Optional[str] = None
    file_id: Optional[int] = None
    error: Optional[str] = None


class LinkPreviewRequest(BaseModel):
    url: str

    @field_validator('url')
    @classmethod
    def validate_url(cls, v):
        if not v or not v.strip():
            raise ValueError('URL cannot be empty')

        # URL length validation to prevent DoS attacks
        # Most browsers limit URLs to 2048 characters
        if len(v) > 2048:
            raise ValueError('URL too long (max 2048 characters)')

        if not v.startswith(('http://', 'https://')):
            v = 'https://' + v

        try:
            from urllib.parse import urlparse
            parsed = urlparse(v)
            if not parsed.scheme or not parsed.netloc:
                raise ValueError('Invalid URL format')

            # Check hostname for security issues
            host = parsed.netloc.lower()
            if ":" in host:
                host = host.split(":")[0]

            # Check blocked patterns
            for pattern in BLOCKED_URL_PATTERNS:
                if host == pattern or host.endswith(f".{pattern}"):
                    raise ValueError(f'URL pattern blocked: {pattern}')

            # Homograph Attack Detection
            if _detect_homograph_attack(host):
                raise ValueError('Potential homograph attack detected (mixed scripts or confusable characters)')

        except Exception as e:
            if isinstance(e, ValueError):
                raise
            raise ValueError(f'Invalid URL: {str(e)}')

        return v


class LinkPreviewResponse(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    image: Optional[str] = None
    site_name: Optional[str] = None


def _sanitize_text(text: str) -> str:
    """
    Sanitize text content to prevent XSS and injection attacks.
    Uses bleach to clean HTML and html.escape for plain text.
    """
    if not text:
        return ""
    
    # Strip any HTML tags and keep only text
    cleaned = bleach.clean(text, tags=[], strip=True)
    
    # Escape any remaining special characters
    cleaned = html.escape(cleaned, quote=True)
    
    # Remove control characters except newlines and tabs
    cleaned = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', cleaned)
    
    return cleaned


def _validate_content_type(content_type: str) -> bool:
    """
    Validate that the content type is allowed for scraping.
    """
    if not content_type:
        return True  # Allow if no content-type header
    
    # Extract base content type (ignore charset and other parameters)
    base_type = content_type.split(';')[0].strip().lower()
    
    return base_type in ALLOWED_CONTENT_TYPES


async def scrape_url(url: str, include_images: bool = True, request_context: Optional[dict] = None) -> tuple[str, str, list]:
    """
    Scrape a URL and return (title, content, images)

    SSRF Protection: Validates URL before making request.
    Circuit Breaker: Prevents cascading failures.
    Content-Type Validation: Ensures we only process allowed content types.
    """
    import time
    
    # SSRF Protection: Validate URL before making request
    if not _is_safe_url(url):
        logger.warning(f"Blocked unsafe URL for scraping: {url}")
        raise HTTPException(status_code=400, detail="URL is blocked for security reasons")

    parsed_url = urlparse(url)
    host = parsed_url.netloc.lower()
    
    # Circuit Breaker: Check if we can make the request
    if not await _circuit_breaker.can_execute(host):
        logger.warning(f"Circuit breaker OPEN - blocking request to {host}")
        raise HTTPException(
            status_code=503,
            detail=f"Service temporarily unavailable (circuit breaker open for {host})"
        )

    request_start = time.time()
    request_logged = False
    
    try:
        # Use follow_redirects=False to validate each redirect manually (SSRF protection)
        # EXPLICIT SSL VERIFICATION: verify=True ensures certificate validation
        async with httpx.AsyncClient(
            verify=True,  # Explicit SSL certificate verification
            timeout=httpx.Timeout(SCRAPE_TIMEOUT, connect=DEFAULT_TIMEOUT),
            follow_redirects=False,
            headers={
                "User-Agent": BOT_USER_AGENT,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.5",
            },
        ) as client:
            response = await client.get(url)

            # Handle redirects manually with SSRF validation
            redirect_count = 0
            max_redirects = 5
            current_url = url

            while response.status_code in (301, 302, 307, 308):
                redirect_count += 1
                if redirect_count > max_redirects:
                    logger.warning(f"Too many redirects for {url} (count: {redirect_count})")
                    raise HTTPException(status_code=400, detail="Too many redirects")

                redirect_url = response.headers.get("location")
                if not redirect_url:
                    raise HTTPException(status_code=400, detail="Redirect missing location header")

                # Resolve relative redirect URLs
                redirect_url = urljoin(current_url, redirect_url)

                # SSRF Protection: Validate redirect URL before following
                if not _is_safe_url(redirect_url):
                    logger.warning(f"Blocked redirect to unsafe URL: {redirect_url}")
                    raise HTTPException(status_code=400, detail=f"Redirect to {redirect_url} is blocked for security reasons")

                current_url = redirect_url
                response = await client.get(current_url)

            response.raise_for_status()

            # Content-Type Validation: Ensure we're processing allowed content types
            content_type = response.headers.get("content-type", "")
            if not _validate_content_type(content_type):
                logger.warning(f"Blocked unsupported content type: {content_type} for {url}")
                raise HTTPException(
                    status_code=415,
                    detail=f"Unsupported content type: {content_type}"
                )

            # Check content length header
            content_length = response.headers.get("content-length")
            if content_length and int(content_length) > MAX_CONTENT_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail=f"Content too large: {content_length} bytes (max: {MAX_CONTENT_SIZE})"
                )

            # Stream response to prevent memory exhaustion
            # CRITICAL FIX: Read response in chunks with hard byte limit
            content_chunks = []
            bytes_read = 0
            async for chunk in response.aiter_bytes(chunk_size=8192):
                bytes_read += len(chunk)
                if bytes_read > MAX_CONTENT_SIZE:
                    logger.warning(f"Content exceeded max size during streaming: {bytes_read} bytes")
                    raise HTTPException(
                        status_code=413,
                        detail=f"Content exceeded max size: {MAX_CONTENT_SIZE} bytes"
                    )
                content_chunks.append(chunk)

            content = b"".join(content_chunks)

            # Record success for circuit breaker
            await _circuit_breaker.record_success(host)
            request_logged = True

    except httpx.TimeoutException as e:
        await _circuit_breaker.record_failure(host)
        logger.error(f"Timeout scraping {url}: {e}")
        raise HTTPException(status_code=408, detail="Request timed out")
    except httpx.HTTPStatusError as e:
        await _circuit_breaker.record_failure(host)
        logger.error(f"HTTP {e.response.status_code} error scraping {url}: {e}")
        raise HTTPException(status_code=e.response.status_code, detail=f"HTTP error: {e.response.status_code}")
    except httpx.RequestError as e:
        await _circuit_breaker.record_failure(host)
        logger.error(f"Request error scraping {url}: {e}")
        raise HTTPException(status_code=400, detail=f"Request failed: {str(e)}")
    except HTTPException:
        # Re-raise HTTP exceptions without recording failure (already handled)
        raise
    except Exception as e:
        await _circuit_breaker.record_failure(host)
        logger.error(f"Unexpected error scraping {url}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")
    finally:
        # Log request timing if not already logged
        if not request_logged:
            request_duration = time.time() - request_start
            logger.info(f"Scrape request to {host} completed in {request_duration:.2f}s (status: failed)")

    # Parse HTML with timeout protection (prevents ReDoS attacks)
    try:
        # Use asyncio.wait_for to timeout the parsing operation
        # BeautifulSoup can be slow on malformed or malicious HTML
        async def parse_html():
            return BeautifulSoup(content.decode('utf-8', errors='ignore'), "html.parser")
        
        soup = await asyncio.wait_for(parse_html(), timeout=10.0)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="HTML parsing timed out (malformed content)")
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Failed to parse HTML: {str(e)}")

    for tag in soup(["script", "style", "nav", "header", "footer", "aside"]):
        tag.decompose()

    title = soup.title.string.strip() if soup.title and soup.title.string else "Untitled"

    images = []
    if include_images:
        og_image = soup.find("meta", property="og:image")
        if og_image and og_image.get("content"):
            images.append(og_image["content"])
        
        twitter_image = soup.find("meta", attrs={"name": "twitter:image"})
        if twitter_image and twitter_image.get("content"):
            images.append(twitter_image["content"])
        
        for img in soup.find_all("img", src=True)[:MAX_IMAGES]:
            src = img["src"]
            if src.startswith("//"):
                src = "https:" + src
            elif not src.startswith("http"):
                src = urljoin(url, src)
            if src not in images:
                images.append(src)

    article = soup.find("article") or soup.find("main")
    
    # Heuristic-based extraction if standard tags missing
    if not article:
        # Look for class/id containing 'content' or 'article' or 'post'
        potential_containers = soup.find_all(lambda tag: tag.name in ['div', 'section'] and 
            (any(s in str(tag.get('class', [])).lower() for s in ['content', 'article', 'post', 'body-text']) or
             any(s in str(tag.get('id', '')).lower() for s in ['content', 'article', 'post', 'body-text'])))
        
        if potential_containers:
            # Pick the one with the most text
            article = max(potential_containers, key=lambda t: len(t.get_text()))
    
    if not article:
        article = soup.find("body")

    if article:
        # Pre-process elements for better spacing
        for element in article.find_all(["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "div", "br"]):
            element.insert_after("\n")
            
        content = article.get_text(separator="\n", strip=True)
    else:
        content = soup.get_text(separator="\n", strip=True)

    # Clean up excessive newlines while preserving structure
    lines = [line.strip() for line in content.split("\n")]
    cleaned_lines = []
    last_was_empty = False

    for line in lines:
        if line:
            cleaned_lines.append(line)
            last_was_empty = False
        elif not last_was_empty:
            cleaned_lines.append("")
            last_was_empty = True

    content = "\n".join(cleaned_lines)
    
    # Truncate at word boundary if content exceeds max size
    truncation_marker = "\n\n[Content truncated due to size]"
    if len(content) > MAX_CONTENT_SIZE - len(truncation_marker):
        # Find last space before limit to avoid cutting mid-word
        truncate_at = content.rfind(' ', 0, MAX_CONTENT_SIZE - len(truncation_marker))
        if truncate_at == -1:
            truncate_at = MAX_CONTENT_SIZE - len(truncation_marker)
        content = content[:truncate_at] + truncation_marker

    return title, content, images[:MAX_IMAGES]


def content_to_markdown(title: str, content: str, url: str, images: list) -> str:
    """Convert content to markdown format with sanitization"""
    # Sanitize title and content to prevent injection
    safe_title = _sanitize_text(title)
    safe_content = content  # Content is already text from BeautifulSoup
    
    md = f"# {safe_title}\n\n"
    md += f"**Source:** [{url}]({url})\n\n"
    md += f"**Saved:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n"
    md += "---\n\n"
    md += safe_content
    if images:
        md += "\n\n---\n\n## Images\n\n"
        for i, img_url in enumerate(images[:3], 1):
            md += f"![Image {i}]({img_url})\n\n"
    return md


def content_to_html(title: str, content: str, url: str, images: list) -> str:
    """Convert content to HTML format with sanitization"""
    # Sanitize title to prevent XSS
    safe_title = _sanitize_text(title)
    
    paragraphs = content.split("\n\n")
    body = ""
    for p in paragraphs:
        if p.startswith("# "):
            body += f"<h1>{html.escape(p[2:])}</h1>\n"
        elif p.startswith("## "):
            body += f"<h2>{html.escape(p[3:])}</h2>\n"
        elif p.startswith("### "):
            body += f"<h3>{html.escape(p[4:])}</h3>\n"
        else:
            body += f"<p>{html.escape(p)}</p>\n"

    images_html = ""
    if images:
        images_html = "<hr><h2>Images</h2>"
        for img_url in images[:3]:
            images_html += f'<img src="{html.escape(img_url)}" style="max-width:100%"><br>'

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{safe_title}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }}
        h1, h2, h3 {{ color: #333; }}
        a {{ color: #0066cc; }}
        img {{ max-width: 100%; height: auto; }}
    </style>
</head>
<body>
    <h1>{safe_title}</h1>
    <p><strong>Source:</strong> <a href="{html.escape(url)}">{html.escape(url)}</a></p>
    <p><strong>Saved:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M')}</p>
    <hr>
    {body}
    {images_html}
</body>
</html>"""


async def save_to_library(
    license_id: int, user_id: str, title: str, content: str, file_type: str
) -> dict:
    """Save scraped content to user's library"""
    file_storage = get_file_storage()
    
    # Determine mime type
    mime_type = "text/markdown" if file_type == "md" else "text/html"
    
    try:
        # Save to persistent storage
        relative_path, public_url = file_storage.save_file(
            content=content.encode("utf-8"),
            filename=f"scraped_{uuid.uuid4().hex[:8]}.{file_type}",
            mime_type=mime_type,
            subfolder="library/scraped"
        )

        # Add to database
        item = await add_library_item(
            license_id=license_id,
            user_id=user_id,
            item_type="file",
            title=title,
            file_path=public_url,
            file_size=len(content),
            mime_type=mime_type
        )

        return item
    except Exception as e:
        logger.error(f"Error saving to library: {e}")
        raise e


@router.post("/scrape", response_model=ScrapeResponse)
@limit_browser_scrape
async def scrape_and_save(
    request: Request,
    scrape_request: ScrapeRequest,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user),
    license: dict = Depends(get_license_from_header),
):
    """
    Scrape a URL and save the content to the user's library.
    Supports markdown and HTML formats.

    Rate limit: 10 requests/minute (expensive operation)
    """
    import time
    request_start = time.time()
    
    url_for_logging = scrape_request.url
    user_id = None
    license_id = None
    client_ip = request.client.host if request.client else "unknown"
    
    try:
        user_id = current_user.get("id") or current_user.get("user_id")
        license_id = license.get("license_id") if license else None
        
        if not user_id:
            logger.warning(f"Unauthorized scrape request from {client_ip}")
            raise HTTPException(status_code=401, detail="Unauthorized")

        # Audit log: Request received
        logger.info(
            f"Browser scrape requested",
            extra={
                "event": "browser_scrape_request",
                "user_id": user_id,
                "license_id": license_id,
                "url": url_for_logging,
                "format": scrape_request.format,
                "include_images": scrape_request.include_images,
                "client_ip": client_ip,
            }
        )

        title, content, images = await scrape_url(
            scrape_request.url,
            include_images=scrape_request.include_images,
            request_context={"user_id": user_id, "license_id": license_id}
        )

        if scrape_request.format == "markdown":
            file_content = content_to_markdown(title, content, scrape_request.url, images)
            file_type = "md"
        else:
            file_content = content_to_html(title, content, scrape_request.url, images)
            file_type = "html"

        library_item = await save_to_library(
            license["license_id"], user_id, title, file_content, file_type
        )

        request_duration = time.time() - request_start
        
        # Audit log: Success
        logger.info(
            f"Browser scrape completed successfully",
            extra={
                "event": "browser_scrape_success",
                "user_id": user_id,
                "license_id": license_id,
                "url": url_for_logging,
                "file_id": library_item.get("id"),
                "duration_ms": round(request_duration * 1000, 2),
                "content_length": len(content),
                "client_ip": client_ip,
            }
        )

        return ScrapeResponse(
            success=True,
            title=title,
            content=content[:500] + "..." if len(content) > 500 else content,
            file_id=library_item.get("id"),
        )

    except HTTPException:
        raise
    except httpx.HTTPError as e:
        request_duration = time.time() - request_start
        logger.error(
            f"HTTP error scraping {url_for_logging}: {e}",
            extra={
                "event": "browser_scrape_http_error",
                "user_id": user_id,
                "license_id": license_id,
                "url": url_for_logging,
                "duration_ms": round(request_duration * 1000, 2),
                "client_ip": client_ip,
            }
        )
        # Generic error message to client (security: don't leak internal details)
        raise HTTPException(status_code=502, detail="Failed to fetch URL. Please try again later.")
    except asyncio.TimeoutError as e:
        request_duration = time.time() - request_start
        logger.error(
            f"Timeout scraping {url_for_logging}: {e}",
            extra={
                "event": "browser_scrape_timeout",
                "user_id": user_id,
                "license_id": license_id,
                "url": url_for_logging,
                "duration_ms": round(request_duration * 1000, 2),
                "client_ip": client_ip,
            }
        )
        raise HTTPException(status_code=408, detail="Request timed out")
    except ValueError as e:
        request_duration = time.time() - request_start
        logger.warning(
            f"Validation error scraping {url_for_logging}: {e}",
            extra={
                "event": "browser_scrape_validation_error",
                "user_id": user_id,
                "license_id": license_id,
                "url": url_for_logging,
                "duration_ms": round(request_duration * 1000, 2),
                "client_ip": client_ip,
            }
        )
        # Generic error message to client (security: don't leak validation details)
        raise HTTPException(status_code=400, detail="Invalid request. Please check the URL and try again.")
    except Exception as e:
        request_duration = time.time() - request_start
        logger.error(
            f"Unexpected error scraping {url_for_logging}: {e}",
            extra={
                "event": "browser_scrape_error",
                "user_id": user_id,
                "license_id": license_id,
                "url": url_for_logging,
                "duration_ms": round(request_duration * 1000, 2),
                "client_ip": client_ip,
            },
            exc_info=True
        )
        # Generic error message to client (security: don't leak internal error details)
        raise HTTPException(status_code=500, detail="An unexpected error occurred. Please try again later.")


def _validate_url_for_preview(url: str) -> str:
    """Validate URL for preview endpoint with SSRF and homograph protection"""
    if not url or not url.strip():
        raise ValueError('URL cannot be empty')

    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url

    try:
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            raise ValueError('Invalid URL format')

        # Extract hostname for security checks
        host = parsed.netloc.lower()
        if ":" in host:
            host = host.split(":")[0]

        # Homograph Attack Detection (same as scrape endpoint)
        if _detect_homograph_attack(host):
            raise ValueError('Potential homograph attack detected (mixed scripts or confusable characters)')

        # Use shared _is_safe_url for SSRF protection
        if not _is_safe_url(url):
            raise ValueError('URL is blocked for security reasons')

    except ValueError:
        raise
    except Exception as e:
        raise ValueError(f'Invalid URL: {str(e)}')

    return url


@router.post("/preview", response_model=LinkPreviewResponse)
@limit_browser_preview
async def get_link_preview(
    request: Request,
    preview_request: LinkPreviewRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Generate a preview for a URL (title, description, image).
    Used for rich link previews in chat.
    Cached for 15 minutes.
    Requires authentication.

    Rate limit: 30 requests/minute (cheaper operation)
    """
    import time
    request_start = time.time()
    
    url_for_logging = preview_request.url
    user_id = current_user.get("id") or current_user.get("user_id")
    client_ip = request.client.host if request.client else "unknown"
    
    # Audit log: Preview request
    logger.info(
        f"Link preview requested",
        extra={
            "event": "browser_preview_request",
            "user_id": user_id,
            "url": url_for_logging,
            "client_ip": client_ip,
        }
    )

    try:
        url = _validate_url_for_preview(url_for_logging)
    except ValueError as e:
        logger.warning(f"Invalid preview URL {url_for_logging}: {e}")
        raise HTTPException(status_code=400, detail=str(e))

    # Thread-safe cache read with LRU touch
    cached = await _get_cached_preview(url)
    if cached:
        # Audit log: Cache hit
        logger.info(
            f"Link preview cache hit",
            extra={
                "event": "browser_preview_cache_hit",
                "user_id": user_id,
                "url": url_for_logging,
                "client_ip": client_ip,
            }
        )
        return LinkPreviewResponse(**cached)

    try:
        # SSRF Protection: Validate URL before making request (defense in depth)
        if not _is_safe_url(url):
            logger.warning(f"Blocked unsafe preview URL: {url}")
            raise HTTPException(status_code=400, detail="URL is blocked for security reasons")

        parsed_url = urlparse(url)
        host = parsed_url.netloc.lower()
        
        # Circuit Breaker: Check if we can make the request
        if not await _circuit_breaker.can_execute(host):
            logger.warning(f"Circuit breaker OPEN - blocking preview request to {host}")
            raise HTTPException(
                status_code=503,
                detail=f"Service temporarily unavailable (circuit breaker open for {host})"
            )

        # Use follow_redirects=False to validate each redirect manually (SSRF protection)
        # EXPLICIT SSL VERIFICATION: verify=True ensures certificate validation
        async with httpx.AsyncClient(
            verify=True,  # Explicit SSL certificate verification
            timeout=httpx.Timeout(10.0, connect=5.0),
            follow_redirects=False,
            headers={
                "User-Agent": BOT_USER_AGENT,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.5",
            },
        ) as client:
            response = await client.get(url)

            # Handle redirects manually with SSRF validation
            redirect_count = 0
            max_redirects = 5
            current_url = url

            while response.status_code in (301, 302, 307, 308):
                redirect_count += 1
                if redirect_count > max_redirects:
                    logger.info(f"Too many redirects for preview: {url}")
                    raise HTTPException(status_code=400, detail="Too many redirects")

                redirect_url = response.headers.get("location")
                if not redirect_url:
                    raise HTTPException(status_code=400, detail="Redirect missing location header")

                # Resolve relative redirect URLs
                redirect_url = urljoin(current_url, redirect_url)

                # SSRF Protection: Validate redirect URL before following
                if not _is_safe_url(redirect_url):
                    logger.warning(f"Blocked redirect in preview: {redirect_url}")
                    raise HTTPException(status_code=400, detail=f"Redirect to {redirect_url} is blocked for security reasons")

                current_url = redirect_url
                response = await client.get(current_url)

            response.raise_for_status()

            # Content-Type Validation for preview
            content_type = response.headers.get("content-type", "")
            if not _validate_content_type(content_type):
                logger.warning(f"Blocked unsupported content type in preview: {content_type}")
                # Return partial result instead of failing for preview
                result = LinkPreviewResponse(
                    title=None,
                    description=None,
                    image=None,
                    site_name=parsed_url.netloc,
                )
            else:
                # Stream response to prevent memory exhaustion (same as scrape endpoint)
                content_chunks = []
                bytes_read = 0
                async for chunk in response.aiter_bytes(chunk_size=8192):
                    bytes_read += len(chunk)
                    if bytes_read > MAX_CONTENT_SIZE:
                        logger.warning(f"Preview content exceeded max size: {bytes_read} bytes")
                        raise HTTPException(
                            status_code=413,
                            detail=f"Content exceeded max size: {MAX_CONTENT_SIZE} bytes"
                        )
                    content_chunks.append(chunk)

                response_content = b"".join(content_chunks)

                # Record success for circuit breaker
                await _circuit_breaker.record_success(host)

            # Final SSRF check: validate the final destination URL after all redirects
            # This prevents bypass where intermediate redirects are safe but final URL is not
            if not _is_safe_url(current_url):
                logger.warning(f"Final redirect destination blocked: {current_url}")
                raise HTTPException(status_code=400, detail="Final redirect destination is blocked for security reasons")

        # Parse HTML with timeout protection
        try:
            async def parse_preview_html():
                # Use streamed content instead of response.text
                content_to_parse = response_content if 'response_content' in dir() else response.content
                return BeautifulSoup(content_to_parse.decode('utf-8', errors='ignore'), "html.parser")
            soup = await asyncio.wait_for(parse_preview_html(), timeout=5.0)
        except asyncio.TimeoutError:
            logger.warning(f"Preview parsing timed out for: {url}")
            # Return partial result instead of failing
            result = LinkPreviewResponse(
                title=None,
                description=None,
                image=None,
                site_name=parsed_url.netloc,
            )
        else:
            title = None
            og_title = soup.find("meta", property="og:title")
            if og_title:
                title = og_title.get("content")
            if not title:
                twitter_title = soup.find("meta", attrs={"name": "twitter:title"})
                if twitter_title:
                    title = twitter_title.get("content")
            if not title and soup.title:
                title = soup.title.string

            description = None
            og_desc = soup.find("meta", property="og:description")
            if og_desc:
                description = og_desc.get("content")
            if not description:
                meta_desc = soup.find("meta", attrs={"name": "description"})
                if meta_desc:
                    description = meta_desc.get("content")

            image = None
            og_image = soup.find("meta", property="og:image")
            if og_image:
                image = og_image.get("content")
            if not image:
                twitter_image = soup.find("meta", attrs={"name": "twitter:image"})
                if twitter_image:
                    image = twitter_image.get("content")

            site_name = None
            og_site = soup.find("meta", property="og:site_name")
            if og_site:
                site_name = og_site.get("content")
            if not site_name:
                site_name = parsed_url.netloc

            result = LinkPreviewResponse(
                title=title,
                description=description,
                image=image,
                site_name=site_name,
            )

        # Thread-safe cache write with LRU eviction
        await _set_cached_preview(url, result.model_dump())

        # Clean cache in background (outside lock to prevent race conditions)
        asyncio.create_task(_clean_preview_cache_background())

        request_duration = time.time() - request_start
        
        # Audit log: Success
        logger.info(
            f"Link preview generated successfully",
            extra={
                "event": "browser_preview_success",
                "user_id": user_id,
                "url": url_for_logging,
                "duration_ms": round(request_duration * 1000, 2),
                "has_title": result.title is not None,
                "has_description": result.description is not None,
                "has_image": result.image is not None,
                "client_ip": client_ip,
            }
        )

        return result

    except httpx.TimeoutException:
        request_duration = time.time() - request_start
        logger.info(f"Preview timeout for {url_for_logging}")
        raise HTTPException(status_code=408, detail="Request timed out")
    except httpx.HTTPStatusError as e:
        request_duration = time.time() - request_start
        logger.info(f"HTTP {e.response.status_code} for preview {url_for_logging}")
        # Generic error message to client (security: don't leak internal details)
        raise HTTPException(status_code=e.response.status_code, detail="Failed to fetch page preview")
    except httpx.RequestError as e:
        request_duration = time.time() - request_start
        logger.warning(f"Preview request failed for {url_for_logging}: {e}")
        # Generic error message to client (security: don't leak internal details)
        raise HTTPException(status_code=400, detail="Failed to fetch preview. Please check the URL and try again.")
    except asyncio.TimeoutError as e:
        request_duration = time.time() - request_start
        logger.info(f"Preview parsing timeout for {url_for_logging}")
        raise HTTPException(status_code=408, detail="Parsing timed out")
    except Exception as e:
        request_duration = time.time() - request_start
        logger.error(f"Unexpected error generating preview for {url_for_logging}: {e}", exc_info=True)
        # Generic error message to client (security: don't leak internal error details)
        raise HTTPException(status_code=500, detail="An unexpected error occurred. Please try again later.")


@router.get("/admin/circuit-breakers")
async def get_circuit_breaker_status(
    request: Request,
    auth: Optional[HTTPAuthorizationCredentials] = Depends(security),
):
    """
    Get circuit breaker status for all hosts (admin-only monitoring endpoint).
    Returns state (closed/open/half-open), failure count, and last failure time.
    
    Requires valid admin JWT token.
    """
    # Verify admin access via JWT
    if not auth:
        raise HTTPException(status_code=401, detail="Authentication required")
    
    try:
        payload = await verify_token_async(auth.credentials, TokenType.ACCESS)
        if not payload:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        # Check if user has admin privileges (adjust based on your admin check logic)
        is_admin = payload.get("is_admin", False) or payload.get("role") == "admin"
        if not is_admin:
            logger.warning(f"Non-admin user attempted to access circuit breaker status: {payload.get('sub')}")
            raise HTTPException(status_code=403, detail="Admin access required")
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Circuit breaker status auth error: {e}")
        raise HTTPException(status_code=401, detail="Authentication failed")
    
    # Get all circuit breaker states
    status_data = await _circuit_breaker.get_all_status()
    
    return {
        "total_hosts": len(status_data),
        "open_circuits": sum(1 for s in status_data.values() if s["state"] == "open"),
        "half_open_circuits": sum(1 for s in status_data.values() if s["state"] == "half-open"),
        "hosts": status_data,
    }
