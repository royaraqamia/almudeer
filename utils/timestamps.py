"""
Al-Mudeer - Timestamp Utilities
Centralized timestamp handling for consistent LWW conflict resolution

FIX P3: All timestamp functions use timezone-aware UTC for consistency
"""

from datetime import datetime, timezone
from typing import Optional, Union


def utcnow() -> datetime:
    """
    FIX P3: Get current UTC time consistently.
    Always returns timezone-aware datetime for proper comparisons.
    
    Returns:
        Timezone-aware UTC datetime
    """
    return datetime.now(timezone.utc)


def utcnow_naive() -> datetime:
    """
    FIX P3: Get current UTC time as naive datetime for database storage.
    Use this when storing to database to maintain compatibility with existing code.
    
    Returns:
        Naive UTC datetime (no timezone info, but represents UTC)
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def normalize_timestamp(ts: Optional[Union[datetime, str]]) -> datetime:
    """
    Convert any timestamp to UTC datetime for consistent LWW comparison.

    Args:
        ts: Timestamp that can be None, datetime, or ISO format string

    Returns:
        Naive UTC datetime for database storage
    """
    if ts is None:
        return utcnow_naive()

    if isinstance(ts, datetime):
        # If timezone-aware, convert to UTC
        if ts.tzinfo is not None:
            return ts.astimezone(timezone.utc).replace(tzinfo=None)
        return ts

    if isinstance(ts, str):
        try:
            # Parse ISO format string (handle 'Z' suffix)
            parsed = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            # Convert to UTC if timezone-aware
            if parsed.tzinfo is not None:
                return parsed.astimezone(timezone.utc).replace(tzinfo=None)
            return parsed
        except (ValueError, TypeError):
            return utcnow_naive()

    # Fallback for any other type
    return utcnow_naive()


def to_utc_iso(dt: Optional[datetime]) -> Optional[str]:
    """
    Convert datetime to UTC ISO format string.
    
    Args:
        dt: datetime object (naive or aware)
        
    Returns:
        ISO format string with UTC timezone, or None if input is None
    """
    if dt is None:
        return None
    
    # If naive, assume UTC
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc).isoformat().replace('+00:00', 'Z')
    
    # Convert to UTC and format
    return dt.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def generate_stable_id(value: str) -> str:
    """
    Generate a stable, deterministic ID from a string value.
    Useful for preserving subtask identity when parsing from JSON strings.
    
    Args:
        value: String to hash
        
    Returns:
        16-character hex string (MD5 hash prefix)
    """
    import hashlib
    return hashlib.md5(value.encode()).hexdigest()[:16]
