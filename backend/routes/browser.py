import logging
import asyncio
import unicodedata
import re
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, Request
from pydantic import BaseModel, HttpUrl, field_validator
from typing import Optional
import httpx
from bs4 import BeautifulSoup
import tempfile
import os
import uuid
from datetime import datetime, timedelta

import ipaddress
import socket
from urllib.parse import urlparse, urljoin

from dependencies import get_current_user, get_license_from_header
from models.library import add_library_item
from services.file_storage_service import get_file_storage
from rate_limiting import limiter, RateLimits, limit_browser_scrape, limit_browser_preview

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/browser", tags=["browser"])

MAX_CONTENT_SIZE = 2 * 1024 * 1024  # 2MB max content
MAX_IMAGES = 10
DEFAULT_TIMEOUT = 15.0
SCRAPE_TIMEOUT = 30.0

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

# Preview cache with thread-safe locking
_preview_cache = {}
_cache_ttl = timedelta(minutes=15)
_cache_lock = asyncio.Lock()

async def _clean_preview_cache():
    """Clean old cache entries based on TTL (thread-safe)"""
    async with _cache_lock:
        now = datetime.now()
        expired_keys = [
            k for k, v in _preview_cache.items()
            if (now - v['timestamp']) > _cache_ttl
        ]
        for key in expired_keys:
            _preview_cache.pop(key, None)

        if len(_preview_cache) > 100:
            oldest_keys = sorted(_preview_cache.keys(),
                               key=lambda k: _preview_cache[k]['timestamp'])[:50]
            for key in oldest_keys:
                _preview_cache.pop(key, None)


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
        if ":" in host:
            host = host.split(":")[0]

        # Check blocked patterns
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
            pass  # DNS resolution failure - let httpx handle it

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


async def scrape_url(url: str, include_images: bool = True) -> tuple[str, str, list]:
    """
    Scrape a URL and return (title, content, images)

    SSRF Protection: Validates URL before making request.
    """
    # SSRF Protection: Validate URL before making request
    if not _is_safe_url(url):
        raise HTTPException(status_code=400, detail="URL is blocked for security reasons")

    try:
        # Use follow_redirects=False to validate each redirect manually (SSRF protection)
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(SCRAPE_TIMEOUT, connect=DEFAULT_TIMEOUT),
            follow_redirects=False,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
                    raise HTTPException(status_code=400, detail="Too many redirects")

                redirect_url = response.headers.get("location")
                if not redirect_url:
                    raise HTTPException(status_code=400, detail="Redirect missing location header")

                # Resolve relative redirect URLs
                redirect_url = urljoin(current_url, redirect_url)

                # SSRF Protection: Validate redirect URL before following
                if not _is_safe_url(redirect_url):
                    raise HTTPException(status_code=400, detail=f"Redirect to {redirect_url} is blocked for security reasons")

                current_url = redirect_url
                response = await client.get(current_url)

            response.raise_for_status()

            # Check content length header
            content_length = response.headers.get("content-length")
            if content_length and int(content_length) > MAX_CONTENT_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail=f"Content too large: {content_length} bytes (max: {MAX_CONTENT_SIZE})"
                )

            # Limit response reading
            content = response.content[:MAX_CONTENT_SIZE]
    except httpx.TimeoutException:
        raise HTTPException(status_code=408, detail="Request timed out")
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=f"HTTP error: {e.response.status_code}")
    except httpx.RequestError as e:
        raise HTTPException(status_code=400, detail=f"Request failed: {str(e)}")

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
                from urllib.parse import urljoin

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
    """Convert content to markdown format"""
    md = f"# {title}\n\n"
    md += f"**Source:** [{url}]({url})\n\n"
    md += f"**Saved:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n"
    md += "---\n\n"
    md += content
    if images:
        md += "\n\n---\n\n## Images\n\n"
        for i, img_url in enumerate(images[:3], 1):
            md += f"![Image {i}]({img_url})\n\n"
    return md


def content_to_html(title: str, content: str, url: str, images: list) -> str:
    """Convert content to HTML format"""
    paragraphs = content.split("\n\n")
    body = ""
    for p in paragraphs:
        if p.startswith("# "):
            body += f"<h1>{p[2:]}</h1>\n"
        elif p.startswith("## "):
            body += f"<h2>{p[3:]}</h2>\n"
        elif p.startswith("### "):
            body += f"<h3>{p[4:]}</h3>\n"
        else:
            body += f"<p>{p}</p>\n"

    images_html = ""
    if images:
        images_html = "<hr><h2>Images</h2>"
        for img_url in images[:3]:
            images_html += f'<img src="{img_url}" style="max-width:100%"><br>'

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{title}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }}
        h1, h2, h3 {{ color: #333; }}
        a {{ color: #0066cc; }}
        img {{ max-width: 100%; height: auto; }}
    </style>
</head>
<body>
    <h1>{title}</h1>
    <p><strong>Source:</strong> <a href="{url}">{url}</a></p>
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
    url_for_logging = scrape_request.url  # Capture URL for error logging
    
    try:
        user_id = current_user.get("id") or current_user.get("user_id")
        if not user_id:
            raise HTTPException(status_code=401, detail="Unauthorized")

        title, content, images = await scrape_url(
            scrape_request.url, include_images=scrape_request.include_images
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

        return ScrapeResponse(
            success=True,
            title=title,
            content=content[:500] + "..." if len(content) > 500 else content,
            file_id=library_item.get("id"),
        )

    except HTTPException:
        raise
    except httpx.HTTPError as e:
        logger.error(f"HTTP error scraping {url_for_logging}: {e}")
        raise HTTPException(status_code=502, detail=f"Failed to fetch URL: {str(e)}")
    except asyncio.TimeoutError as e:
        logger.error(f"Timeout scraping {url_for_logging}: {e}")
        raise HTTPException(status_code=408, detail="Request timed out")
    except ValueError as e:
        logger.error(f"Validation error scraping {url_for_logging}: {e}")
        raise HTTPException(status_code=400, detail=f"Invalid request: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error scraping {url_for_logging}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


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
    url_for_logging = preview_request.url
    
    try:
        url = _validate_url_for_preview(url_for_logging)
    except ValueError as e:
        logger.warning(f"Invalid preview URL {url_for_logging}: {e}")
        raise HTTPException(status_code=400, detail=str(e))

    # Thread-safe cache read
    async with _cache_lock:
        cached = _preview_cache.get(url)
        if cached and (datetime.now() - cached['timestamp']) < _cache_ttl:
            return LinkPreviewResponse(**cached['data'])

    try:
        # SSRF Protection: Validate URL before making request (defense in depth)
        if not _is_safe_url(url):
            logger.warning(f"Blocked unsafe preview URL: {url}")
            raise HTTPException(status_code=400, detail="URL is blocked for security reasons")

        # Use follow_redirects=False to validate each redirect manually (SSRF protection)
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(10.0, connect=5.0),
            follow_redirects=False,
            headers={
                "User-Agent": "Mozilla/5.0 (compatible; AlmudeerBot/1.0; +https://almudeer.app)"
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

            # Final SSRF check: validate the final destination URL after all redirects
            # This prevents bypass where intermediate redirects are safe but final URL is not
            if not _is_safe_url(current_url):
                logger.warning(f"Final redirect destination blocked: {current_url}")
                raise HTTPException(status_code=400, detail="Final redirect destination is blocked for security reasons")

        # Parse HTML with timeout protection
        try:
            async def parse_preview_html():
                return BeautifulSoup(response.text, "html.parser")
            soup = await asyncio.wait_for(parse_preview_html(), timeout=5.0)
        except asyncio.TimeoutError:
            logger.warning(f"Preview parsing timed out for: {url}")
            # Return partial result instead of failing
            return LinkPreviewResponse(
                title=None,
                description=None,
                image=None,
                site_name=urlparse(url).netloc,
            )

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
            from urllib.parse import urlparse
            site_name = urlparse(url).netloc

        result = LinkPreviewResponse(
            title=title,
            description=description,
            image=image,
            site_name=site_name,
        )

        # Thread-safe cache write
        async with _cache_lock:
            _preview_cache[url] = {
                'timestamp': datetime.now(),
                'data': result.model_dump()
            }

        # Clean cache in background (outside lock to prevent race conditions)
        asyncio.create_task(_clean_preview_cache_background())

        return result

    except httpx.TimeoutException:
        logger.info(f"Preview timeout for {url_for_logging}")
        raise HTTPException(status_code=408, detail="Request timed out")
    except httpx.HTTPStatusError as e:
        logger.info(f"HTTP {e.response.status_code} for preview {url_for_logging}")
        raise HTTPException(status_code=e.response.status_code, detail=f"HTTP error: {e.response.status_code}")
    except httpx.RequestError as e:
        logger.warning(f"Preview request failed for {url_for_logging}: {e}")
        raise HTTPException(status_code=400, detail=f"Request failed: {str(e)}")
    except asyncio.TimeoutError as e:
        logger.info(f"Preview parsing timeout for {url_for_logging}")
        raise HTTPException(status_code=408, detail="Parsing timed out")
    except Exception as e:
        logger.error(f"Unexpected error generating preview for {url_for_logging}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to generate preview: {str(e)}")
