"""
Outbox Message Retry Service
Implements exponential backoff retry logic for failed message sends.
"""

import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any
from db_helper import get_db, execute_sql, fetch_one, fetch_all, commit_db, DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)

# Retry configuration
MAX_RETRIES = 5
BASE_DELAY_SECONDS = 60  # 1 minute
MAX_DELAY_SECONDS = 3600  # 1 hour


async def mark_message_for_retry(
    outbox_id: int,
    license_id: int,
    error_message: str
) -> Optional[datetime]:
    """
    Mark an outbox message for retry with exponential backoff.
    
    Returns the next retry timestamp, or None if max retries exceeded.
    """
    async with get_db() as db:
        # Get current retry count
        msg = await fetch_one(
            db,
            "SELECT retry_count, created_at FROM outbox_messages WHERE id = ? AND license_key_id = ?",
            [outbox_id, license_id]
        )
        
        if not msg:
            logger.error(f"Outbox message {outbox_id} not found for retry")
            return None
        
        retry_count = msg.get("retry_count", 0) or 0
        
        # Check if max retries exceeded
        if retry_count >= MAX_RETRIES:
            logger.warning(f"Message {outbox_id} exceeded max retries ({MAX_RETRIES})")
            await mark_outbox_failed(outbox_id, f"Max retries exceeded: {error_message}")
            return None
        
        # Calculate exponential backoff delay
        delay = min(BASE_DELAY_SECONDS * (2 ** retry_count), MAX_DELAY_SECONDS)
        # Add jitter (±20%) to prevent thundering herd
        import random
        jitter = delay * 0.2 * (random.random() * 2 - 1)
        delay_with_jitter = delay + jitter
        
        next_retry = datetime.now(timezone.utc) + timedelta(seconds=delay_with_jitter)
        
        # Convert for DB
        if DB_TYPE == "postgresql":
            ts_value = next_retry.replace(tzinfo=None)
        else:
            ts_value = next_retry.isoformat()
        
        # Update retry fields
        await execute_sql(
            db,
            """
            UPDATE outbox_messages
            SET retry_count = ?,
                last_retry_at = ?,
                next_retry_at = ?,
                retry_error = ?
            WHERE id = ? AND license_key_id = ?
            """,
            [
                retry_count + 1,
                datetime.now(timezone.utc).replace(tzinfo=None) if DB_TYPE == "postgresql" else datetime.now(timezone.utc).isoformat(),
                ts_value,
                error_message[:500],  # Truncate long errors
                outbox_id,
                license_id
            ]
        )
        
        await commit_db(db)
        
        logger.info(f"Message {outbox_id} scheduled for retry #{retry_count + 1} at {next_retry}")
        return next_retry


async def get_messages_due_for_retry(
    license_id: Optional[int] = None,
    limit: int = 50
) -> list:
    """
    Get outbox messages that are due for retry.
    """
    now = datetime.now(timezone.utc)
    if DB_TYPE != "postgresql":
        now = now.isoformat()
    
    params = [now]
    license_filter = ""
    if license_id:
        license_filter = "AND license_key_id = ?"
        params.insert(0, license_id)
    
    async with get_db() as db:
        rows = await fetch_all(
            db,
            f"""
            SELECT id, license_key_id, channel, body, retry_count
            FROM outbox_messages
            WHERE status = 'pending'
              AND retry_count > 0
              AND retry_count < {MAX_RETRIES}
              AND next_retry_at <= ?
              {license_filter}
            ORDER BY next_retry_at ASC
            LIMIT ?
            """,
            params + [limit]
        )
        
        return [dict(row) for row in rows]


async def mark_outbox_failed(
    outbox_id: int,
    error_message: str
):
    """
    Mark an outbox message as permanently failed.
    """
    async with get_db() as db:
        await execute_sql(
            db,
            """
            UPDATE outbox_messages
            SET status = 'failed',
                retry_error = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            [error_message[:500], outbox_id]
        )
        await commit_db(db)
    
    logger.error(f"Message {outbox_id} marked as failed: {error_message}")


async def process_retry_queue():
    """
    Background task to process retry queue.
    Should be called periodically (e.g., every minute).
    """
    try:
        messages = await get_messages_due_for_retry(limit=50)
        
        if not messages:
            return
        
        logger.info(f"Processing {len(messages)} messages due for retry")
        
        for msg in messages:
            try:
                # Re-trigger send via workers
                from workers import start_message_polling
                poller = await start_message_polling()
                await poller._send_message(
                    msg["id"],
                    msg["license_key_id"],
                    msg["channel"]
                )
            except Exception as e:
                logger.error(f"Retry failed for message {msg['id']}: {e}")
                await mark_message_for_retry(
                    msg["id"],
                    msg["license_key_id"],
                    str(e)
                )
    
    except Exception as e:
        logger.error(f"Error processing retry queue: {e}")


# ============ Integration with Workers ============

async def enhance_send_with_retry(
    send_func,
    outbox_id: int,
    license_id: int,
    channel: str
):
    """
    Wrapper for _send_message that implements retry logic.
    
    Usage in workers.py:
        await enhance_send_with_retry(
            self._send_message_impl,  # Actual send function
            outbox_id,
            license_id,
            channel
        )
    """
    try:
        await send_func(outbox_id, license_id, channel)
        # Success - reset retry count
        async with get_db() as db:
            await execute_sql(
                db,
                "UPDATE outbox_messages SET retry_count = 0 WHERE id = ?",
                [outbox_id]
            )
            await commit_db(db)
    except Exception as e:
        logger.error(f"Send failed for message {outbox_id}: {e}")
        # Schedule retry
        await mark_message_for_retry(outbox_id, license_id, str(e))
        raise  # Re-raise to let caller handle
