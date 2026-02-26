"""
Al-Mudeer - Input Sanitization Utilities
Prevents XSS and other injection attacks by sanitizing user input.
"""

import re
import html


def sanitize_text(text: str, max_length: int = 10000) -> str:
    """
    Sanitize text input to prevent XSS attacks.
    
    Args:
        text: The input text to sanitize
        max_length: Maximum allowed length (default 10000)
    
    Returns:
        Sanitized text safe for storage and display
    """
    if not text:
        return text
    
    # Truncate to max length
    if len(text) > max_length:
        text = text[:max_length]
    
    # Escape HTML entities to prevent XSS
    text = html.escape(text)
    
    # Remove any null bytes
    text = text.replace('\x00', '')
    
    # Normalize line endings
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    
    return text


def sanitize_rich_text(text: str, allowed_tags: list = None) -> str:
    """
    Sanitize rich text while allowing some HTML tags.
    
    Args:
        text: The input text to sanitize
        allowed_tags: List of allowed HTML tags (default: basic formatting)
    
    Returns:
        Sanitized rich text
    """
    if not text:
        return text
    
    # Default allowed tags for basic formatting
    if allowed_tags is None:
        allowed_tags = ['p', 'br', 'strong', 'em', 'u', 'ul', 'ol', 'li']
    
    # For now, just use basic sanitization
    # In future, could use bleach library for more advanced HTML sanitization
    return sanitize_text(text)


def sanitize_title(title: str) -> str:
    """
    Sanitize a task/title input.
    Strips HTML completely as titles should be plain text.
    
    Args:
        title: The title to sanitize
    
    Returns:
        Sanitized title (plain text only)
    """
    if not title:
        return title
    
    # Truncate titles to reasonable length
    if len(title) > 500:
        title = title[:500]
    
    # Remove any HTML tags completely
    title = re.sub(r'<[^>]+>', '', title)
    
    # Escape any remaining special characters
    title = html.escape(title)
    
    # Remove control characters except newline and tab
    title = ''.join(char for char in title if ord(char) >= 32 or char in '\n\t')
    
    return title.strip()


def sanitize_description(description: str) -> str:
    """
    Sanitize a description input.
    
    Args:
        description: The description to sanitize
    
    Returns:
        Sanitized description
    """
    return sanitize_text(description, max_length=5000)


def sanitize_comment(content: str) -> str:
    """
    Sanitize a comment input.
    
    Args:
        content: The comment content to sanitize
    
    Returns:
        Sanitized comment
    """
    return sanitize_text(content, max_length=2000)


def validate_category(category: str) -> str:
    """
    Validate and sanitize a category name.
    Only allows alphanumeric characters, spaces, and Arabic text.
    
    Args:
        category: The category name
    
    Returns:
        Sanitized category name or empty string if invalid
    """
    if not category:
        return ""
    
    # Truncate
    if len(category) > 100:
        category = category[:100]
    
    # Allow: alphanumeric, spaces, Arabic, underscores, hyphens
    # This regex allows most Unicode letters (including Arabic) plus basic chars
    if not re.match(r'^[\w\s\u0600-\u06FF\-_]+$', category, re.UNICODE):
        # Remove disallowed characters
        category = re.sub(r'[^\w\s\u0600-\u06FF\-_]', '', category, flags=re.UNICODE)
    
    return category.strip()
