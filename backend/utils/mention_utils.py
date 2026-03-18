"""
Username mention utilities for detecting and resolving @username mentions in messages.

This module provides functionality to:
1. Detect @username patterns in message text (like Telegram)
2. Resolve usernames to user details
3. Store mention metadata with messages
"""

import re
from typing import List, Dict, Optional, Tuple
from db_helper import get_db, fetch_one, fetch_all, DB_TYPE


# Regex pattern to match @username mentions
# Username rules: 2-32 characters, alphanumeric, underscores, hyphens
# Supports both Latin (a-zA-Z) and Arabic (\u0600-\u06FF, \u0750-\u077F) characters
# Same pattern as mobile app's task_edit_screen.dart and note_edit_screen.dart
MENTION_PATTERN = re.compile(r'@([a-zA-Z0-9_\u0600-\u06FF\u0750-\u077F-]{2,32})')


def extract_mentions(text: str) -> List[str]:
    """
    Extract all @username mentions from a text message.
    
    Args:
        text: The message text to scan for mentions
        
    Returns:
        List of usernames (without the @ symbol)
        
    Examples:
        >>> extract_mentions("Hello @ayham-alali, how are you?")
        ['ayham-alali']
        >>> extract_mentions("Hi @user1 and @user_2!")
        ['user1', 'user_2']
    """
    if not text:
        return []
    
    return MENTION_PATTERN.findall(text)


def build_mention_entities(text: str, mentions: List[str] = None) -> List[Dict]:
    """
    Build structured mention entities with positions for frontend rendering.
    
    Args:
        text: The message text
        mentions: Optional list of usernames to find (if None, extracts from text)
        
    Returns:
        List of mention entities with position info:
        [
            {
                "username": "ayham-alali",
                "start": 6,
                "end": 19,
                "text": "@ayham-alali"
            },
            ...
        ]
    """
    if not text:
        return []
    
    if mentions is None:
        mentions = extract_mentions(text)
    
    entities = []
    for username in mentions:
        # Find all occurrences of this username in the text
        pattern = f'@{re.escape(username)}'
        for match in re.finditer(pattern, text):
            entities.append({
                "username": username,
                "start": match.start(),
                "end": match.end(),
                "text": match.group()
            })
    
    return entities


async def resolve_mentioned_users(
    mentions: List[str], 
    license_id: int,
    db=None
) -> List[Dict]:
    """
    Resolve a list of usernames to user details.
    
    Args:
        mentions: List of usernames to resolve
        license_id: The license ID (for filtering shared users)
        db: Optional database connection (for reuse)
        
    Returns:
        List of resolved user info:
        [
            {
                "username": "ayham-alali",
                "user_id": 123,
                "full_name": "Ayham Alali",
                "profile_pic_url": "...",
                "is_almudeer_user": True
            },
            ...
        ]
    """
    if not mentions:
        return []
    
    is_active_value = "TRUE" if DB_TYPE == "postgresql" else "1"
    
    # Use provided DB or get a new connection
    should_close = False
    if db is None:
        db = await get_db().__aenter__()
        should_close = True

    try:
        resolved_users = []
        placeholders = ", ".join(["?" for _ in mentions])

        query = f"""
            SELECT id, username, full_name, profile_pic_url,
                   (EXISTS (SELECT 1 FROM customers c
                            WHERE c.username = lk.username AND c.license_key_id = ?)) as has_customer_profile
            FROM license_keys
            WHERE username IN ({placeholders})
              AND is_active = {is_active_value}
        """

        params = [license_id] + list(mentions)
        rows = await fetch_all(db, query, params)

        for row in rows:
            resolved_users.append({
                "username": row["username"],
                "user_id": row["id"],
                "full_name": row["full_name"],
                "profile_pic_url": row["profile_pic_url"],
                "is_almudeer_user": True,
                "has_customer_profile": bool(row["has_customer_profile"])
            })

        return resolved_users
    except Exception as e:
        # Log error but don't fail the message
        from logging_config import get_logger
        get_logger(__name__).warning(f"Failed to resolve mentions: {e}")
        return []
    finally:
        if should_close:
            try:
                await db.__aexit__(None, None, None)
            except Exception as e:
                # P0-5 FIX: Connection may already be closed or have pending operation
                # Log but don't propagate - mention resolution is non-critical
                from logging_config import get_logger
                get_logger(__name__).warning(f"Failed to close mention utils DB connection: {e}")


async def process_message_mentions(
    text: str,
    license_id: int,
    db=None
) -> Tuple[str, List[Dict], List[Dict]]:
    """
    Process a message to extract and resolve username mentions.
    
    Args:
        text: The message text
        license_id: The license ID
        db: Optional database connection
        
    Returns:
        Tuple of (original_text, mention_entities, resolved_users)
    """
    mentions = extract_mentions(text)
    
    if not mentions:
        return text, [], []
    
    entities = build_mention_entities(text, mentions)
    resolved_users = await resolve_mentioned_users(mentions, license_id, db)
    
    return text, entities, resolved_users


def format_message_with_mentions(
    text: str,
    mention_entities: List[Dict]
) -> Dict:
    """
    Format message text with mention metadata for frontend rendering.
    
    This creates a structured representation that the frontend can use
    to render clickable username spans.
    
    Args:
        text: The original message text
        mention_entities: List of mention entities from build_mention_entities
        
    Returns:
        Structured message content:
        {
            "text": "Hello @ayham-alali, how are you?",
            "mentions": [
                {
                    "username": "ayham-alali",
                    "start": 6,
                    "end": 19,
                    "user_id": 123,
                    "full_name": "Ayham Alali"
                }
            ]
        }
    """
    return {
        "text": text,
        "mentions": mention_entities
    }


def has_mentions(text: str) -> bool:
    """
    Check if text contains any @username mentions.
    
    Args:
        text: The message text to check
        
    Returns:
        True if mentions are found, False otherwise
    """
    return bool(extract_mentions(text))
