import logging
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
from rate_limiting import limiter, RateLimits

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/browser", tags=["browser"])

MAX_CONTENT_SIZE = 2 * 1024 * 1024  # 2MB max content
MAX_IMAGES = 10
DEFAULT_TIMEOUT = 15.0
SCRAPE_TIMEOUT = 30.0

# Preview cache
_preview_cache = {}
_cache_ttl = timedelta(minutes=15)

def _clean_preview_cache():
    """Clean old cache entries based on TTL"""
    now = datetime.now()
    expired_keys = [
        k for k, v in _preview_cache.items()
        if (now - v['timestamp']) > _cache_ttl
    ]
    for key in expired_keys:
        del _preview_cache[key]
    
    if len(_preview_cache) > 100:
        oldest_keys = sorted(_preview_cache.keys(), 
                           key=lambda k: _preview_cache[k]['timestamp'])[:50]
        for key in oldest_keys:
            del _preview_cache[key]

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
]


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
    """
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(SCRAPE_TIMEOUT, connect=DEFAULT_TIMEOUT),
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            },
        ) as client:
            response = await client.get(url)
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

    try:
        soup = BeautifulSoup(content.decode('utf-8', errors='ignore'), "html.parser")
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
    
    # Direct truncation to MAX_CONTENT_SIZE without double processing
    content = "\n".join(cleaned_lines)
    if len(content) > MAX_CONTENT_SIZE:
        content = content[:MAX_CONTENT_SIZE] + "\n\n[Content truncated due to size]"

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
@limiter.limit(RateLimits.API)
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
    """
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
        logger.error(f"HTTP error scraping {scrape_request.url}: {e}")
        raise HTTPException(status_code=502, detail=f"Failed to fetch URL: {str(e)}")
    except Exception as e:
        logger.error(f"Error scraping {scrape_request.url}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


def _validate_url_for_preview(url: str) -> str:
    """Validate URL for preview endpoint with SSRF protection"""
    if not url or not url.strip():
        raise ValueError('URL cannot be empty')
    
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    
    try:
        from urllib.parse import urlparse
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            raise ValueError('Invalid URL format')
        
        host = parsed.netloc.lower()
        if ":" in host:
            host = host.split(":")[0]

        for pattern in BLOCKED_URL_PATTERNS:
            if host == pattern or host.endswith(f".{pattern}"):
                raise ValueError(f'URL pattern blocked: {pattern}')
        
        try:
            ip_address = socket.gethostbyname(host)
            ip = ipaddress.ip_address(ip_address)
            
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
                raise ValueError(f'Access to private/reserved IP {ip_address} is blocked')
        except socket.gaierror:
            pass
        except Exception as e:
            if isinstance(e, ValueError):
                raise
            pass
                
    except Exception as e:
        if isinstance(e, ValueError):
            raise
        raise ValueError(f'Invalid URL: {str(e)}')
    
    return url


@router.post("/preview", response_model=LinkPreviewResponse)
@limiter.limit(RateLimits.API)
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
    """
    url = preview_request.url
    
    try:
        url = _validate_url_for_preview(url)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    cached = _preview_cache.get(url)
    if cached and (datetime.now() - cached['timestamp']) < _cache_ttl:
        return LinkPreviewResponse(**cached['data'])
    
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(10.0, connect=5.0),
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (compatible; AlmudeerBot/1.0; +https://almudeer.app)"
            },
        ) as client:
            response = await client.get(url)
            response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")

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
        
        _preview_cache[url] = {
            'timestamp': datetime.now(),
            'data': result.model_dump()
        }
        
        _clean_preview_cache()

        return result

    except httpx.TimeoutException:
        raise HTTPException(status_code=408, detail="Request timed out")
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=f"HTTP error: {e.response.status_code}")
    except httpx.RequestError as e:
        raise HTTPException(status_code=400, detail=f"Request failed: {str(e)}")
    except Exception as e:
        logger.error(f"Error generating preview for {url}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to generate preview: {str(e)}")
