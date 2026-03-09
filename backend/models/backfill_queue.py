"""
Al-Mudeer - Backfill Queue Model
Functions for managing the historical message backfill queue
"""

from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
import os

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)

# Configuration
BACKFILL_REVEAL_INTERVAL_SECONDS = int(os.getenv("BACKFILL_REVEAL_INTERVAL_SECONDS", "600"))  # 10 minutes default
BACKFILL_DAYS = int(os.getenv("BACKFILL_DAYS", "30"))  # 30 days of history


import json

async def add_to_backfill_queue(
    license_id: int,
    channel: str,
    body: str,
    scheduled_reveal_at: datetime,
    channel_message_id: Optional[str] = None,
    sender_contact: Optional[str] = None,
    sender_name: Optional[str] = None,
    sender_id: Optional[str] = None,
    subject: Optional[str] = None,
    received_at: Optional[datetime] = None,
    attachments: Optional[List[Dict[str, Any]]] = None,
) -> Optional[int]:
    """
    Add a historical message to the backfill queue for gradual reveal.
    """
    try:
        # Serialize attachments
        attachments_json = json.dumps(attachments) if attachments else None

        async with get_db() as db:
            # Check for duplicate
            if channel_message_id:
                existing = await fetch_one(
                    db,
                    "SELECT id FROM backfill_queue WHERE channel_message_id = ? AND license_key_id = ?",
                    [channel_message_id, license_id]
                )
                if existing:
                    logger.debug(f"Skipping duplicate backfill entry: {channel_message_id}")
                    return None
            
            # Also check if message already exists in inbox
            if channel_message_id:
                inbox_existing = await fetch_one(
                    db,
                    "SELECT id FROM inbox_messages WHERE channel_message_id = ? AND license_key_id = ?",
                    [channel_message_id, license_id]
                )
                if inbox_existing:
                    logger.debug(f"Message already in inbox, skipping backfill: {channel_message_id}")
                    return None
            
            # Insert into queue
            if DB_TYPE == "postgresql":
                result = await fetch_one(
                    db,
                    """
                    INSERT INTO backfill_queue
                    (license_key_id, channel, channel_message_id, sender_contact, sender_name,
                     sender_id, subject, body, received_at, scheduled_reveal_at, status, attachments)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'pending', $11)
                    RETURNING id
                    """,
                    [license_id, channel, channel_message_id, sender_contact, sender_name,
                     sender_id, subject, body, received_at, scheduled_reveal_at, attachments_json]
                )
                await commit_db(db)
                return result["id"] if result else None
            else:
                await execute_sql(
                    db,
                    """
                    INSERT INTO backfill_queue
                    (license_key_id, channel, channel_message_id, sender_contact, sender_name,
                     sender_id, subject, body, received_at, scheduled_reveal_at, status, attachments)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)
                    """,
                    [license_id, channel, channel_message_id, sender_contact, sender_name,
                     sender_id, subject, body, received_at, scheduled_reveal_at, attachments_json]
                )
                await commit_db(db)

                # Get the last inserted ID
                result = await fetch_one(db, "SELECT last_insert_rowid() as id", [])
                return result["id"] if result else None
                
    except Exception as e:
        logger.error(f"Error adding to backfill queue: {e}")
        return None


async def get_next_pending_reveal(license_id: Optional[int] = None) -> Optional[Dict[str, Any]]:
    """
    Get the next message that is ready to be revealed (scheduled time has passed).
    
    Args:
        license_id: Optional - filter by specific license
    
    Returns:
        The next pending message ready for reveal, or None
    """
    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                if license_id:
                    query = """
                        SELECT * FROM backfill_queue 
                        WHERE status = 'pending' 
                          AND scheduled_reveal_at <= NOW()
                          AND license_key_id = $1
                        ORDER BY scheduled_reveal_at ASC
                        LIMIT 1
                    """
                    row = await fetch_one(db, query, [license_id])
                else:
                    query = """
                        SELECT * FROM backfill_queue 
                        WHERE status = 'pending' 
                          AND scheduled_reveal_at <= NOW()
                        ORDER BY scheduled_reveal_at ASC
                        LIMIT 1
                    """
                    row = await fetch_one(db, query, [])
            else:
                if license_id:
                    query = """
                        SELECT * FROM backfill_queue 
                        WHERE status = 'pending' 
                          AND scheduled_reveal_at <= datetime('now')
                          AND license_key_id = ?
                        ORDER BY scheduled_reveal_at ASC
                        LIMIT 1
                    """
                    row = await fetch_one(db, query, [license_id])
                else:
                    query = """
                        SELECT * FROM backfill_queue 
                        WHERE status = 'pending' 
                          AND scheduled_reveal_at <= datetime('now')
                        ORDER BY scheduled_reveal_at ASC
                        LIMIT 1
                    """
                    row = await fetch_one(db, query, [])
            
            return dict(row) if row else None
            
    except Exception as e:
        logger.error(f"Error getting next pending reveal: {e}")
        return None


async def mark_as_revealed(queue_id: int, inbox_message_id: Optional[int] = None) -> bool:
    """
    Mark a backfill queue entry as revealed (moved to inbox).
    
    Args:
        queue_id: The backfill queue entry ID
        inbox_message_id: The created inbox message ID (for reference)
    
    Returns:
        True if successful
    """
    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                await execute_sql(
                    db,
                    "UPDATE backfill_queue SET status = 'revealed', revealed_at = NOW() WHERE id = $1",
                    [queue_id]
                )
            else:
                await execute_sql(
                    db,
                    "UPDATE backfill_queue SET status = 'revealed', revealed_at = datetime('now') WHERE id = ?",
                    [queue_id]
                )
            await commit_db(db)
            return True
    except Exception as e:
        logger.error(f"Error marking backfill as revealed: {e}")
        return False


async def mark_as_failed(queue_id: int, error_message: str) -> bool:
    """
    Mark a backfill queue entry as failed.
    
    Args:
        queue_id: The backfill queue entry ID
        error_message: Description of the failure
    
    Returns:
        True if successful
    """
    try:
        async with get_db() as db:
            await execute_sql(
                db,
                "UPDATE backfill_queue SET status = 'failed', error_message = ? WHERE id = ?",
                [error_message, queue_id]
            )
            await commit_db(db)
            return True
    except Exception as e:
        logger.error(f"Error marking backfill as failed: {e}")
        return False


async def get_backfill_progress(license_id: int) -> Dict[str, int]:
    """
    Get backfill progress statistics for a license.
    
    Args:
        license_id: The license key ID
    
    Returns:
        Dict with counts: {pending, revealed, failed, total}
    """
    try:
        async with get_db() as db:
            rows = await fetch_all(
                db,
                """
                SELECT status, COUNT(*) as count 
                FROM backfill_queue 
                WHERE license_key_id = ?
                GROUP BY status
                """,
                [license_id]
            )
            
            result = {"pending": 0, "revealed": 0, "failed": 0, "total": 0}
            for row in rows:
                status = row.get("status") or row[0]
                count = row.get("count") or row[1]
                if status in result:
                    result[status] = count
                result["total"] += count
            
            return result
            
    except Exception as e:
        logger.error(f"Error getting backfill progress: {e}")
        return {"pending": 0, "revealed": 0, "failed": 0, "total": 0}


async def has_pending_backfill(license_id: int, channel: str) -> bool:
    """
    Check if a license has any pending backfill entries for a channel.
    Used to avoid triggering duplicate backfills.
    
    Args:
        license_id: The license key ID
        channel: The channel type
    
    Returns:
        True if there are pending entries
    """
    try:
        async with get_db() as db:
            row = await fetch_one(
                db,
                """
                SELECT COUNT(*) as count FROM backfill_queue 
                WHERE license_key_id = ? AND channel = ? AND status = 'pending'
                """,
                [license_id, channel]
            )
            if not row:
                return False
            count = row.get("count", 0)
            return count > 0
    except Exception as e:
        logger.error(f"Error checking pending backfill: {e}")
        return False


async def get_backfill_queue_count(license_id: int, channel: Optional[str] = None) -> int:
    """
    Get count of all backfill entries (any status) for a license/channel.
    Used to check if backfill was already triggered.
    
    Args:
        license_id: The license key ID
        channel: Optional channel filter
    
    Returns:
        Total count of backfill entries
    """
    try:
        async with get_db() as db:
            if channel:
                row = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM backfill_queue WHERE license_key_id = ? AND channel = ?",
                    [license_id, channel]
                )
            else:
                row = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM backfill_queue WHERE license_key_id = ?",
                    [license_id]
                )
            return row.get("count", 0) if row else 0
    except Exception as e:
        logger.error(f"Error getting backfill queue count: {e}")
        return 0


async def cleanup_old_backfill_entries(days_old: int = 60) -> int:
    """
    Clean up old revealed/failed backfill entries to prevent table bloat.
    
    Args:
        days_old: Remove entries older than this many days
    
    Returns:
        Number of entries deleted
    """
    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                result = await fetch_one(
                    db,
                    """
                    DELETE FROM backfill_queue 
                    WHERE status IN ('revealed', 'failed') 
                      AND created_at < NOW() - INTERVAL '%s days'
                    RETURNING COUNT(*) as count
                    """ % days_old,
                    []
                )
            else:
                # SQLite doesn't support RETURNING with DELETE, do it in two steps
                count_row = await fetch_one(
                    db,
                    """
                    SELECT COUNT(*) as count FROM backfill_queue 
                    WHERE status IN ('revealed', 'failed') 
                      AND created_at < datetime('now', '-%s days')
                    """ % days_old,
                    []
                )
                await execute_sql(
                    db,
                    """
                    DELETE FROM backfill_queue 
                    WHERE status IN ('revealed', 'failed') 
                      AND created_at < datetime('now', '-%s days')
                    """ % days_old,
                    []
                )
                result = count_row
            
            await commit_db(db)
            count = result.get("count") or result[0] if result else 0
            if count > 0:
                logger.info(f"Cleaned up {count} old backfill entries")
            return count
            
    except Exception as e:
        logger.error(f"Error cleaning up backfill entries: {e}")
        return 0
