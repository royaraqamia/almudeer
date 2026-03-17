"""
Al-Mudeer - Task Alarm Service

Handles scheduled task alarms with FCM push notifications.
Features:
- Background worker to check and send due alarms
- FCM push notifications for alarms
- Alarm acknowledgment tracking
- Recurring task alarm rescheduling
- Multi-device alarm sync
"""

import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict
import asyncio
import json

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from services.fcm_mobile_service import send_fcm_notification, ensure_fcm_tokens_table

logger = logging.getLogger(__name__)

# ============================================================================
# CONFIGURATION
# ============================================================================

# How often to check for due alarms (seconds)
ALARM_CHECK_INTERVAL_SECONDS = 30

# How far ahead to prefetch alarms (seconds) - prevents missing alarms if worker restarts
ALARM_PREFETCH_SECONDS = 120

# Alarm TTL - how long to keep alarm records after firing (days)
ALARM_RETENTION_DAYS = 7

# Maximum retries for failed alarm notifications
ALARM_MAX_RETRIES = 3

# Boolean literals for database compatibility
BOOL_TRUE = "TRUE" if DB_TYPE == "postgresql" else "1"
BOOL_FALSE = "FALSE" if DB_TYPE == "postgresql" else "0"

# ============================================================================
# DATABASE SCHEMA
# ============================================================================

async def ensure_task_alarms_table():
    """Ensure task_alarms table exists for tracking alarm state."""
    async with get_db() as db:
        # Database-agnostic ID column definition
        id_pk = "SERIAL PRIMARY KEY" if DB_TYPE == "postgresql" else "INTEGER PRIMARY KEY AUTOINCREMENT"
        
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS task_alarms (
                id {id_pk},
                task_id TEXT NOT NULL,
                license_key_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                alarm_time TIMESTAMP NOT NULL,
                scheduled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                fired_at TIMESTAMP,
                acknowledged_at TIMESTAMP,
                acknowledged_by_device_id TEXT,
                retry_count INTEGER DEFAULT 0,
                status TEXT DEFAULT 'pending',
                notification_data TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Indexes for performance
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_alarms_status_time 
            ON task_alarms(status, alarm_time)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_alarms_task 
            ON task_alarms(task_id)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_alarms_license 
            ON task_alarms(license_key_id)
        """)

        # Partial index for pending alarms (PostgreSQL only, SQLite may not support)
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_task_alarms_pending 
                ON task_alarms(status, alarm_time) 
                WHERE status = 'pending'
            """)

        await commit_db(db)
        logger.info("Task alarms table verified")


async def init_task_alarm_cleanup():
    """Initialize cleanup job for old alarm records."""
    async with get_db() as db:
        # Clean up old acknowledged alarms
        cutoff = datetime.now(timezone.utc) - timedelta(days=ALARM_RETENTION_DAYS)
        await execute_sql(
            db,
            "DELETE FROM task_alarms WHERE status = 'acknowledged' AND acknowledged_at < ?",
            [cutoff.isoformat()]
        )
        await commit_db(db)


# ============================================================================
# ALARM SCHEDULING
# ============================================================================

async def schedule_task_alarm(
    task_id: str,
    license_key_id: int,
    user_id: str,
    alarm_time: datetime,
    task_title: str,
    task_description: Optional[str] = None
) -> int:
    """
    Schedule a task alarm.
    
    Args:
        task_id: Task ID
        license_key_id: License key ID
        user_id: User ID (task owner or assignee)
        alarm_time: When the alarm should fire
        task_title: Task title for notification
        task_description: Optional task description
        
    Returns:
        Alarm ID if scheduled, 0 on error
    """
    # Don't schedule alarms in the past
    now = datetime.now(timezone.utc)
    if alarm_time < now:
        logger.debug(f"Skipping past alarm for task {task_id}")
        return 0
    
    # Check if alarm already exists for this task/time
    async with get_db() as db:
        existing = await fetch_one(
            db,
            """
            SELECT id FROM task_alarms 
            WHERE task_id = ? AND alarm_time = ? AND status = 'pending'
            """,
            [task_id, alarm_time.isoformat()]
        )
        
        if existing:
            logger.debug(f"Alarm already exists for task {task_id} at {alarm_time}")
            return existing["id"]
        
        # Insert new alarm
        notification_data = json.dumps({
            "type": "task_alarm",
            "task_id": task_id,
            "task": {
                "id": task_id,
                "title": task_title,
                "description": task_description,
                "alarm_time": alarm_time.isoformat()
            }
        })
        
        await execute_sql(
            db,
            """
            INSERT INTO task_alarms 
            (task_id, license_key_id, user_id, alarm_time, notification_data, status)
            VALUES (?, ?, ?, ?, ?, 'pending')
            """,
            [task_id, license_key_id, user_id, alarm_time.isoformat(), notification_data]
        )
        
        await commit_db(db)
        
        # Get the inserted ID
        row = await fetch_one(db, "SELECT last_insert_rowid() as id")
        alarm_id = row["id"] if row else 0
        
        logger.info(f"Scheduled task alarm {alarm_id} for task {task_id} at {alarm_time}")
        return alarm_id


async def cancel_task_alarm(task_id: str, license_key_id: int) -> bool:
    """
    Cancel all pending alarms for a task.
    
    Args:
        task_id: Task ID
        license_key_id: License key ID
        
    Returns:
        True if cancelled, False on error
    """
    async with get_db() as db:
        await execute_sql(
            db,
            """
            UPDATE task_alarms 
            SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP
            WHERE task_id = ? AND license_key_id = ? AND status = 'pending'
            """,
            [task_id, license_key_id]
        )
        await commit_db(db)
        logger.info(f"Cancelled pending alarms for task {task_id}")
        return True


async def acknowledge_task_alarm(
    alarm_id: int,
    device_id: Optional[str] = None
) -> bool:
    """
    Acknowledge a fired alarm.
    
    Args:
        alarm_id: Alarm ID
        device_id: Device that acknowledged the alarm
        
    Returns:
        True if acknowledged, False on error
    """
    async with get_db() as db:
        await execute_sql(
            db,
            """
            UPDATE task_alarms 
            SET status = 'acknowledged',
                acknowledged_at = CURRENT_TIMESTAMP,
                acknowledged_by_device_id = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ? AND status = 'fired'
            """,
            [device_id, alarm_id]
        )
        await commit_db(db)
        logger.info(f"Acknowledged alarm {alarm_id} from device {device_id}")
        return True


async def acknowledge_task_alarms_for_task(
    task_id: str,
    license_key_id: int,
    device_id: Optional[str] = None
) -> int:
    """
    Acknowledge all alarms for a specific task (used when user completes task).
    
    Args:
        task_id: Task ID
        license_key_id: License key ID
        device_id: Device that acknowledged
        
    Returns:
        Number of alarms acknowledged
    """
    async with get_db() as db:
        # Acknowledge pending/fired alarms
        await execute_sql(
            db,
            """
            UPDATE task_alarms 
            SET status = 'acknowledged',
                acknowledged_at = CURRENT_TIMESTAMP,
                acknowledged_by_device_id = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE task_id = ? AND license_key_id = ? 
            AND status IN ('pending', 'fired')
            """,
            [device_id, task_id, license_key_id]
        )
        await commit_db(db)
        
        # Get count of acknowledged alarms
        row = await fetch_one(
            db,
            "SELECT changes() as count"
        )
        count = row["count"] if row else 0
        
        logger.info(f"Acknowledged {count} alarms for task {task_id}")
        return count


# ============================================================================
# ALARM PROCESSING
# ============================================================================

async def get_due_alarms(limit: int = 100) -> List[dict]:
    """
    Get alarms that are due to fire.
    
    Args:
        limit: Maximum number of alarms to fetch
        
    Returns:
        List of due alarm records
    """
    now = datetime.now(timezone.utc)
    prefetch_cutoff = now + timedelta(seconds=ALARM_PREFETCH_SECONDS)
    
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT * FROM task_alarms
            WHERE status = 'pending'
            AND alarm_time <= ?
            AND retry_count < ?
            ORDER BY alarm_time ASC
            LIMIT ?
            """,
            [now.isoformat(), ALARM_MAX_RETRIES, limit]
        )
        
        return [dict(row) for row in rows]


async def send_alarm_notification(alarm: dict) -> bool:
    """
    Send FCM notification for an alarm.
    
    Args:
        alarm: Alarm record dict
        
    Returns:
        True if sent successfully, False otherwise
    """
    try:
        notification_data = json.loads(alarm.get("notification_data", "{}"))
        task_data = notification_data.get("task", {})
        
        title = "⏰ تذكير مهمَّة"
        body = task_data.get("title", "Task Reminder")
        if task_data.get("description"):
            body = f"{body}\n{task_data['description']}"
        
        # Get FCM tokens for the user
        async with get_db() as db:
            tokens = await fetch_all(
                db,
                """
                SELECT token, device_id FROM fcm_tokens
                WHERE license_key_id = ? AND user_id = ? AND is_active = TRUE
                """,
                [alarm["license_key_id"], alarm["user_id"]]
            )
        
        if not tokens:
            logger.warning(f"No FCM tokens for user {alarm['user_id']} (alarm {alarm['id']})")
            return False
        
        # Prepare FCM data payload
        fcm_data = {
            "type": "task_alarm",
            "task_id": alarm["task_id"],
            "alarm_id": str(alarm["id"]),
            "task": json.dumps(task_data)
        }
        
        # Send to all user devices
        success_count = 0
        for token_row in tokens:
            try:
                result = await send_fcm_notification(
                    token=token_row["token"],
                    title=title,
                    body=body,
                    data=fcm_data,
                    sound="default",
                    ttl_seconds=300  # 5 minutes TTL for alarms
                )
                if result:
                    success_count += 1
            except Exception as e:
                logger.error(f"Failed to send alarm to token {token_row['token'][:20]}...: {e}")
        
        if success_count > 0:
            logger.info(f"Sent alarm {alarm['id']} to {success_count}/{len(tokens)} devices")
            return True
        else:
            logger.warning(f"Failed to send alarm {alarm['id']} to any device")
            return False
            
    except Exception as e:
        logger.error(f"Error sending alarm notification: {e}", exc_info=True)
        return False


async def mark_alarm_fired(alarm_id: int) -> bool:
    """Mark an alarm as fired."""
    async with get_db() as db:
        await execute_sql(
            db,
            """
            UPDATE task_alarms 
            SET status = 'fired', fired_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            [alarm_id]
        )
        await commit_db(db)
        return True


async def mark_alarm_retry(alarm_id: int, error: str) -> bool:
    """Increment retry count for a failed alarm."""
    async with get_db() as db:
        await execute_sql(
            db,
            """
            UPDATE task_alarms 
            SET retry_count = retry_count + 1, 
                updated_at = CURRENT_TIMESTAMP,
                notification_data = json_insert(
                    COALESCE(notification_data, '{}'),
                    '$.last_error', ?,
                    '$.last_error_time', ?
                )
            WHERE id = ?
            """,
            [error, datetime.now(timezone.utc).isoformat(), alarm_id]
        )
        await commit_db(db)
        return True


async def process_due_alarms() -> Dict[str, int]:
    """
    Process all due alarms.
    
    Returns:
        Dict with processing statistics
    """
    stats = {"processed": 0, "success": 0, "failed": 0}
    
    # Get due alarms
    alarms = await get_due_alarms()
    
    for alarm in alarms:
        stats["processed"] += 1
        
        try:
            # Send notification
            success = await send_alarm_notification(alarm)
            
            if success:
                await mark_alarm_fired(alarm["id"])
                stats["success"] += 1
            else:
                await mark_alarm_retry(alarm["id"], "Failed to send notification")
                stats["failed"] += 1
                
        except Exception as e:
            logger.error(f"Error processing alarm {alarm['id']}: {e}", exc_info=True)
            await mark_alarm_retry(alarm["id"], str(e))
            stats["failed"] += 1
    
    return stats


# ============================================================================
# BACKGROUND WORKER
# ============================================================================

_alarm_worker_task = None
_alarm_worker_running = False
_alarm_worker_stats = {
    "last_run": None,
    "total_processed": 0,
    "total_success": 0,
    "total_failed": 0
}


async def start_task_alarm_worker():
    """Start the task alarm background worker."""
    global _alarm_worker_running, _alarm_worker_task
    
    if _alarm_worker_running:
        logger.warning("Task alarm worker already running")
        return {"status": "already_running"}
    
    # Ensure table exists
    await ensure_task_alarms_table()
    
    _alarm_worker_running = True
    logger.info("Task alarm worker started")
    
    async def worker_loop():
        global _alarm_worker_stats
        
        while _alarm_worker_running:
            try:
                # Process due alarms
                stats = await process_due_alarms()
                
                # Update global stats
                _alarm_worker_stats["last_run"] = datetime.now(timezone.utc).isoformat()
                _alarm_worker_stats["total_processed"] += stats.get("processed", 0)
                _alarm_worker_stats["total_success"] += stats.get("success", 0)
                _alarm_worker_stats["total_failed"] += stats.get("failed", 0)
                
                if stats.get("processed", 0) > 0:
                    logger.info(
                        f"Alarm worker processed {stats['processed']} alarms: "
                        f"{stats['success']} success, {stats['failed']} failed"
                    )
                
            except Exception as e:
                logger.error(f"Task alarm worker error: {e}", exc_info=True)
            
            # Wait for next check
            await asyncio.sleep(ALARM_CHECK_INTERVAL_SECONDS)
    
    # Start worker in background
    _alarm_worker_task = asyncio.create_task(worker_loop())
    
    return {"status": "started"}


async def stop_task_alarm_worker():
    """Stop the task alarm background worker."""
    global _alarm_worker_running, _alarm_worker_task
    
    _alarm_worker_running = False
    
    if _alarm_worker_task:
        _alarm_worker_task.cancel()
        try:
            await _alarm_worker_task
        except asyncio.CancelledError:
            pass
    
    logger.info("Task alarm worker stopped")
    return {"status": "stopped"}


def get_alarm_worker_status() -> dict:
    """Get the current status of the alarm worker."""
    return {
        "running": _alarm_worker_running,
        **_alarm_worker_stats
    }


# ============================================================================
# RECURRING TASK SUPPORT
# ============================================================================

async def schedule_next_occurrence_alarm(
    task_id: str,
    license_key_id: int,
    user_id: str,
    current_alarm_time: datetime,
    recurrence: str,
    task_title: str,
    task_description: Optional[str] = None
) -> Optional[int]:
    """
    Schedule alarm for the next occurrence of a recurring task.
    
    Args:
        task_id: Task ID
        license_key_id: License key ID
        user_id: User ID
        current_alarm_time: Current alarm time
        recurrence: Recurrence pattern (daily, weekly, monthly)
        task_title: Task title
        task_description: Optional task description
        
    Returns:
        New alarm ID if scheduled, None on error
    """
    from dateutil.relativedelta import relativedelta
    
    # Calculate next occurrence
    if recurrence == "daily":
        next_time = current_alarm_time + relativedelta(days=1)
    elif recurrence == "weekly":
        next_time = current_alarm_time + relativedelta(weeks=1)
    elif recurrence == "monthly":
        next_time = current_alarm_time + relativedelta(months=1)
    else:
        logger.warning(f"Unknown recurrence pattern: {recurrence}")
        return None
    
    # Schedule the new alarm
    alarm_id = await schedule_task_alarm(
        task_id=task_id,
        license_key_id=license_key_id,
        user_id=user_id,
        alarm_time=next_time,
        task_title=task_title,
        task_description=task_description
    )
    
    if alarm_id:
        logger.info(f"Scheduled next occurrence alarm {alarm_id} for {next_time}")
    
    return alarm_id


# ============================================================================
# ALARM SYNC ACROSS DEVICES
# ============================================================================

async def sync_alarm_state(
    task_id: str,
    license_key_id: int,
    action: str,
    device_id: Optional[str] = None
) -> bool:
    """
    Sync alarm state across all user devices.
    
    Args:
        task_id: Task ID
        license_key_id: License key ID
        action: Action to sync ('acknowledge', 'cancel')
        device_id: Device performing the action
        
    Returns:
        True if synced, False on error
    """
    if action == "acknowledge":
        await acknowledge_task_alarms_for_task(task_id, license_key_id, device_id)
    elif action == "cancel":
        await cancel_task_alarm(task_id, license_key_id)
    else:
        logger.warning(f"Unknown alarm sync action: {action}")
        return False
    
    logger.info(f"Synced alarm state for task {task_id}: {action}")
    return True


# ============================================================================
# CLEANUP AND MAINTENANCE
# ============================================================================

async def cleanup_old_alarms() -> int:
    """
    Clean up old alarm records.
    
    Returns:
        Number of records deleted
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=ALARM_RETENTION_DAYS)
    
    async with get_db() as db:
        await execute_sql(
            db,
            """
            DELETE FROM task_alarms 
            WHERE status = 'acknowledged' AND acknowledged_at < ?
            """,
            [cutoff.isoformat()]
        )
        await commit_db(db)
        
        # Get deleted count
        row = await fetch_one(db, "SELECT changes() as count")
        count = row["count"] if row else 0
        
        logger.info(f"Cleaned up {count} old alarm records")
        return count


async def cleanup_stale_pending_alarms() -> int:
    """
    Clean up pending alarms that are too old (task likely deleted or completed).
    
    Returns:
        Number of records cleaned up
    """
    # Pending alarms older than 7 days are likely stale
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    
    async with get_db() as db:
        await execute_sql(
            db,
            """
            DELETE FROM task_alarms 
            WHERE status = 'pending' AND created_at < ?
            """,
            [cutoff.isoformat()]
        )
        await commit_db(db)
        
        # Get deleted count
        row = await fetch_one(db, "SELECT changes() as count")
        count = row["count"] if row else 0
        
        if count > 0:
            logger.info(f"Cleaned up {count} stale pending alarms")
        
        return count
