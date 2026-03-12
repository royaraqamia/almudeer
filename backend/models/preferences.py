"""
Al-Mudeer - User Preferences Model
Handles user settings, tone, language, and notification preferences.
"""

import json
import re
from typing import Optional, List, Union
from db_helper import get_db, execute_sql, fetch_one, commit_db, DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)


def sanitize_calculator_entry(entry: dict) -> dict:
    """
    Sanitize a calculator history entry to prevent XSS/injection.
    Each entry should have 'entry' and optionally 'timestamp' keys.
    """
    if not isinstance(entry, dict):
        return {'entry': '', 'timestamp': ''}
    
    entry_text = entry.get('entry', '')
    timestamp = entry.get('timestamp', '')
    
    # Validate entry is a string
    if not isinstance(entry_text, str):
        entry_text = str(entry_text) if entry_text else ''
    
    if not isinstance(timestamp, str):
        timestamp = str(timestamp) if timestamp else ''
    
    # Strip HTML-like tags
    entry_text = re.sub(r'<[^>]*>', '', entry_text)
    # Remove control characters except newline/tab
    entry_text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', entry_text)
    # Limit length to 500 characters
    entry_text = entry_text[:500]
    
    return {
        'entry': entry_text,
        'timestamp': timestamp
    }

async def get_preferences(license_id: int) -> dict:
    """
    Get user preferences.
    Handles backward compatibility for preferred_languages (CSV vs JSON).
    """
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT * FROM user_preferences WHERE license_key_id = ?",
            [license_id]
        )
        if row:
            prefs = dict(row)
            # CRITICAL: Always enforce notifications_enabled as True
            prefs["notifications_enabled"] = True

            # Smart handling of preferred_languages
            # It might be stored as "ar,en" (Legacy) or "[\"ar\", \"en\"]" (New JSON)
            raw_langs = prefs.get("preferred_languages")
            if raw_langs:
                try:
                    if raw_langs.strip().startswith("["):
                        # It's likely JSON
                        prefs["preferred_languages"] = json.loads(raw_langs)
                    else:
                        # Fallback to CSV splitting
                        prefs["preferred_languages"] = [l.strip() for l in raw_langs.split(",") if l.strip()]
                except Exception:
                    # On error, treat as simple string or empty list
                    prefs["preferred_languages"] = [str(raw_langs)]

            # Handle calculator_history - stored as JSON array of structured entries
            # Each entry: {entry: string, timestamp: ISO8601}
            raw_history = prefs.get("calculator_history")
            if raw_history:
                try:
                    parsed = json.loads(raw_history)
                    # Ensure it's a list and preserve structure
                    if isinstance(parsed, list):
                        prefs["calculator_history"] = parsed
                    else:
                        prefs["calculator_history"] = []
                except (json.JSONDecodeError, TypeError):
                    prefs["calculator_history"] = []
            else:
                prefs["calculator_history"] = []

            return prefs

        # Create default preferences including AI tone defaults
        # We store defaults as JSON for consistency with new standard
        default_langs_json = json.dumps(["ar"])
        default_calc_history_json = json.dumps([])

        await execute_sql(
            db,
            """
            INSERT INTO user_preferences (
                license_key_id,
                tone,
                language,
                preferred_languages,
                notifications_enabled,
                calculator_history
            ) VALUES (?, 'formal', 'ar', ?, ?, ?)
            """,
            [license_id, default_langs_json, True, default_calc_history_json]
        )
        await commit_db(db)

        return {
            "license_key_id": license_id,
            "dark_mode": False,
            "notifications_enabled": True,
            "notification_sound": True,
            "language": "ar",
            "onboarding_completed": False,
            "tone": "formal",
            "custom_tone_guidelines": None,
            "preferred_languages": ["ar"], # Return list directly
            "reply_length": None,
            "formality_level": None,
            "quran_progress": None,
            "athkar_stats": None,
            "calculator_history": [], # Return empty list for calculator history
        }


async def update_preferences(license_id: int, **kwargs) -> bool:
    """
    Update user preferences.
    automatically serializes lists to JSON strings.
    """
    allowed = [
        'dark_mode',
        'notifications_enabled',
        'notification_sound',
        'onboarding_completed',
        # Tone & communication style
        'tone',
        'custom_tone_guidelines',
        'preferred_languages',
        'reply_length',
        'formality_level',
        # Quran & Athkar Sync
        'quran_progress',
        'athkar_stats',
        'calculator_history',
    ]
    updates = {k: v for k, v in kwargs.items() if k in allowed}
    
    # Always enforce notifications_enabled as True
    if 'notifications_enabled' in updates:
        updates['notifications_enabled'] = True
    
    logger.info(f"update_preferences called: license_id={license_id}, updates={updates}")
    
    if not updates:
        logger.info("No updates to apply")
        return False
        
    # Pre-process updates: Serialize lists to JSON
    for k, v in updates.items():
        if k == 'calculator_history':
            if isinstance(v, list):
                # Sanitize each entry to prevent XSS/injection
                sanitized_entries = []
                for entry in v:
                    if isinstance(entry, dict):
                        sanitized = sanitize_calculator_entry(entry)
                        sanitized_entries.append(sanitized)
                    elif isinstance(entry, str):
                        # Handle legacy string format
                        sanitized_entries.append({
                            'entry': entry[:500],  # Limit length
                            'timestamp': ''
                        })
                # Limit to 50 entries max
                sanitized_entries = sanitized_entries[:50]
                updates[k] = json.dumps(sanitized_entries)
                logger.info(f"Serialized and sanitized {k}: {len(sanitized_entries)} entries")
            elif isinstance(v, str) and v.strip().startswith('['):
                # Already JSON string - parse, sanitize, and re-serialize
                try:
                    parsed = json.loads(v)
                    if isinstance(parsed, list):
                        sanitized_entries = []
                        for entry in parsed:
                            if isinstance(entry, dict):
                                sanitized = sanitize_calculator_entry(entry)
                                sanitized_entries.append(sanitized)
                            elif isinstance(entry, str):
                                sanitized_entries.append({
                                    'entry': entry[:500],
                                    'timestamp': ''
                                })
                        sanitized_entries = sanitized_entries[:50]
                        updates[k] = json.dumps(sanitized_entries)
                        logger.info(f"Parsed, sanitized, and re-serialized {k}: {len(sanitized_entries)} entries")
                    else:
                        updates[k] = json.dumps([])
                except (json.JSONDecodeError, TypeError):
                    updates[k] = json.dumps([])
                    logger.warning(f"Invalid JSON in {k}, resetting to empty")
        elif k == 'preferred_languages':
            if isinstance(v, list):
                # For preferred_languages, entries are strings
                updates[k] = json.dumps(v)
                logger.info(f"Serialized {k} list to JSON: {updates[k][:100]}...")
            elif isinstance(v, str) and v.strip().startswith('['):
                # Already JSON string, keep as-is
                updates[k] = v
                logger.info(f"Keeping {k} as JSON string: {v[:50]}...")
    
    set_clause = ", ".join(f"{k} = ?" for k in updates.keys())
    update_values = list(updates.values())

    async with get_db() as db:
        # Use UPSERT pattern - INSERT with ON CONFLICT UPDATE
        # PostgreSQL and SQLite both support this syntax
        if DB_TYPE == "postgresql":
            # PostgreSQL: use EXCLUDED reference for cleaner syntax
            set_clause_pg = ", ".join(f"{k} = EXCLUDED.{k}" for k in updates.keys())
            cols = ", ".join(["license_key_id"] + list(updates.keys()))
            placeholders = ", ".join(["?"] * (1 + len(updates)))
            sql = f"""
                INSERT INTO user_preferences ({cols}) VALUES ({placeholders})
                ON CONFLICT(license_key_id) DO UPDATE SET {set_clause_pg}
                """
            logger.info(f"PostgreSQL UPSERT SQL: {sql.strip()}, params: {[license_id] + update_values}")
            await execute_sql(
                db,
                sql,
                [license_id] + update_values
            )
        else:
            # SQLite: use standard ON CONFLICT DO UPDATE SET with explicit values
            cols = ", ".join(["license_key_id"] + list(updates.keys()))
            placeholders = ", ".join(["?"] * (1 + len(updates)))
            await execute_sql(
                db,
                f"""
                INSERT INTO user_preferences ({cols}) VALUES ({placeholders})
                ON CONFLICT(license_key_id) DO UPDATE SET {set_clause}
                """,
                [license_id] + update_values + update_values  # Values for INSERT + UPDATE
            )
        await commit_db(db)
        logger.info("Preferences update completed successfully")
        return True


async def delete_preferences(license_id: int, db=None) -> bool:
    """Delete user preferences"""
    if db:
        await execute_sql(
            db,
            "DELETE FROM user_preferences WHERE license_key_id = ?",
            [license_id]
        )
        return True

    async with get_db() as new_db:
        await execute_sql(
            new_db,
            "DELETE FROM user_preferences WHERE license_key_id = ?",
            [license_id]
        )
        await commit_db(new_db)
        return True
