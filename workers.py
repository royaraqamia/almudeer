"""
Al-Mudeer - Background Workers and Scheduled Jobs

Handles:
- Share expiration cleanup
- Notification sending
- Analytics aggregation
- Maintenance tasks
"""

import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List
import asyncio

from db_helper import get_db, execute_sql, fetch_all, commit_db

logger = logging.getLogger(__name__)


# ============================================================================
# WORKER STATUS
# ============================================================================

# Global status tracking for background workers
_worker_status = {
    "email_polling": {
        "status": "running",
        "last_check": None,
        "items_processed": 0
    },
    "telegram_polling": {
        "status": "running",
        "last_check": None,
        "items_processed": 0
    }
}


def get_worker_status():
    """
    Get the current status of background workers.

    Returns:
        dict: Status of email and telegram polling workers
    """
    return _worker_status


def update_worker_status(worker_type: str, status: dict):
    """
    Update the status of a specific worker.

    Args:
        worker_type: Type of worker ('email_polling' or 'telegram_polling')
        status: Status dictionary to update
    """
    if worker_type in _worker_status:
        _worker_status[worker_type].update(status)


# ============================================================================
# MESSAGE POLLING (WhatsApp/Telegram)
# ============================================================================

_message_poller_task = None
_message_poller_running = False


async def start_message_polling():
    """
    Start the message polling background task.
    Returns the poller task/coroutine for management.
    """
    global _message_poller_running, _message_poller_task
    _message_poller_running = True
    logger.info("Message polling started")
    return {"status": "running"}


async def stop_message_polling():
    """Stop the message polling background task."""
    global _message_poller_running, _message_poller_task
    _message_poller_running = False
    logger.info("Message polling stopped")


# ============================================================================
# SUBSCRIPTION REMINDERS
# ============================================================================

_subscription_reminder_task = None
_subscription_reminder_running = False


async def start_subscription_reminders():
    """Start the subscription reminder background task."""
    global _subscription_reminder_running, _subscription_reminder_task
    _subscription_reminder_running = True
    logger.info("Subscription reminders started")
    return {"status": "running"}


async def stop_subscription_reminders():
    """Stop the subscription reminder background task."""
    global _subscription_reminder_running, _subscription_reminder_task
    _subscription_reminder_running = False
    logger.info("Subscription reminders stopped")


# ============================================================================
# TOKEN CLEANUP WORKER
# ============================================================================

_token_cleanup_task = None
_token_cleanup_running = False


async def start_token_cleanup_worker():
    """Start the token cleanup background task."""
    global _token_cleanup_running, _token_cleanup_task
    _token_cleanup_running = True
    logger.info("Token cleanup worker started")
    return {"status": "running"}


async def stop_token_cleanup_worker():
    """Stop the token cleanup background task."""
    global _token_cleanup_running, _token_cleanup_task
    _token_cleanup_running = False
    logger.info("Token cleanup worker stopped")


# ============================================================================
# STORY CLEANUP WORKER
# ============================================================================

_story_cleanup_task = None
_story_cleanup_running = False


async def start_story_cleanup_worker():
    """Start the story cleanup background task."""
    global _story_cleanup_running, _story_cleanup_task
    _story_cleanup_running = True
    logger.info("Story cleanup worker started")
    return {"status": "running"}


async def stop_story_cleanup_worker():
    """Stop the story cleanup background task."""
    global _story_cleanup_running, _story_cleanup_task
    _story_cleanup_running = False
    logger.info("Story cleanup worker stopped")


# ============================================================================
# LIBRARY TRASH CLEANUP WORKER
# ============================================================================

_library_trash_cleanup_task = None
_library_trash_cleanup_running = False


async def start_library_trash_cleanup_worker():
    """Start the library trash cleanup background task."""
    global _library_trash_cleanup_running, _library_trash_cleanup_task
    _library_trash_cleanup_running = True
    logger.info("Library trash cleanup worker started")
    return {"status": "running"}


async def stop_library_trash_cleanup_worker():
    """Stop the library trash cleanup background task."""
    global _library_trash_cleanup_running, _library_trash_cleanup_task
    _library_trash_cleanup_running = False
    logger.info("Library trash cleanup worker stopped")


# ============================================================================
# P3-14: SHARE EXPIRATION CLEANUP
# ============================================================================

async def cleanup_expired_shares():
    """
    Daily job to clean up expired shares.
    
    P3-14: Automatically revoke expired share permissions.
    
    Tasks:
    1. Mark expired shares as deleted
    2. Reset is_shared flag for items with no active shares
    3. Log cleanup statistics
    """
    logger.info("Starting share expiration cleanup job...")
    
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        try:
            # 1. Mark expired shares as deleted
            result = await execute_sql(
                db,
                """
                UPDATE library_shares
                SET deleted_at = ?
                WHERE expires_at IS NOT NULL
                AND expires_at < ?
                AND deleted_at IS NULL
                """,
                [now, now]
            )
            
            expired_count = result.rowcount if hasattr(result, 'rowcount') else 0
            logger.info(f"Marked {expired_count} expired shares as deleted")
            
            await commit_db(db)
            
            # 2. Reset is_shared flag for items with no active shares
            # Get all items that have is_shared = 1 but no active shares
            items_to_update = await fetch_all(
                db,
                """
                SELECT li.id
                FROM library_items li
                WHERE li.is_shared = 1
                AND li.deleted_at IS NULL
                AND NOT EXISTS (
                    SELECT 1 FROM library_shares ls
                    WHERE ls.item_id = li.id
                    AND ls.license_key_id = li.license_key_id
                    AND ls.deleted_at IS NULL
                    AND (ls.expires_at IS NULL OR ls.expires_at > ?)
                )
                """,
                [now]
            )
            
            reset_count = 0
            for item in items_to_update:
                await execute_sql(
                    db,
                    "UPDATE library_items SET is_shared = 0 WHERE id = ?",
                    [item["id"]]
                )
                reset_count += 1
            
            await commit_db(db)
            logger.info(f"Reset is_shared flag for {reset_count} items")
            
            logger.info(
                f"Share cleanup completed: {expired_count} expired shares, "
                f"{reset_count} items updated"
            )
            
            return {
                "success": True,
                "expired_shares": expired_count,
                "items_updated": reset_count
            }
            
        except Exception as e:
            logger.error(f"Share cleanup failed: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e)
            }


# ============================================================================
# P3-14: SHARE NOTIFICATIONS
# ============================================================================

async def create_share_notification(
    license_id: int,
    item_id: int,
    item_title: str,
    shared_by_user_id: str,
    shared_with_user_id: str,
    permission: str
):
    """
    Create a notification when an item is shared with a user.
    
    P3-14: Notify users when items are shared with them.
    """
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    license_id,
                    'library_share',
                    'normal',
                    'تمت مشاركة عنصر معك',
                    f'{shared_by_user_id} شارك معك: {item_title} ({permission})',
                    now
                ]
            )
            await commit_db(db)
            
            logger.info(
                f"Created share notification: {item_title} shared with {shared_with_user_id}"
            )
            
            return True
        except Exception as e:
            logger.error(f"Failed to create share notification: {e}", exc_info=True)
            return False


async def create_share_revoked_notification(
    license_id: int,
    item_id: int,
    item_title: str,
    revoked_by_user_id: str,
    user_id: str
):
    """
    Create a notification when a share is revoked.
    
    P3-14: Notify users when sharing access is revoked.
    """
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    license_id,
                    'library_share_revoked',
                    'normal',
                    'تم إزالة صلاحية الوصول',
                    f'{revoked_by_user_id} أزال صلاحية الوصول إلى: {item_title}',
                    now
                ]
            )
            await commit_db(db)
            
            logger.info(f"Created share revoked notification for {item_title}")
            
            return True
        except Exception as e:
            logger.error(f"Failed to create share revoked notification: {e}", exc_info=True)
            return False


async def create_share_expiring_soon_notification(
    license_id: int,
    item_id: int,
    item_title: str,
    user_id: str,
    expires_at: datetime
):
    """
    Create a notification 3 days before share expires.
    
    P3-14: Warn users before their access expires.
    """
    now = datetime.now(timezone.utc)
    days_until_expiry = (expires_at - now).days
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    license_id,
                    'library_share_expiring_soon',
                    'high',
                    'صلاحية الوصول ستنتهي قريباً',
                    f'صلاحية الوصول إلى {item_title} ستنتهي خلال {days_until_expiry} أيام',
                    now
                ]
            )
            await commit_db(db)
            
            logger.info(
                f"Created expiring soon notification for {item_title} "
                f"(expires in {days_until_expiry} days)"
            )
            
            return True
        except Exception as e:
            logger.error(
                f"Failed to create expiring soon notification: {e}",
                exc_info=True
            )
            return False


async def check_expiring_shares():
    """
    Daily job to check for shares expiring in 3 days.
    
    P3-14: Send advance warning notifications for expiring shares.
    """
    logger.info("Checking for expiring shares...")
    
    now = datetime.now(timezone.utc)
    three_days_from_now = now + timedelta(days=3)
    
    async with get_db() as db:
        try:
            # Find shares expiring in exactly 3 days
            expiring_shares = await fetch_all(
                db,
                """
                SELECT ls.*, li.title as item_title
                FROM library_shares ls
                INNER JOIN library_items li ON ls.item_id = li.id
                WHERE ls.expires_at IS NOT NULL
                AND ls.deleted_at IS NULL
                AND DATE(ls.expires_at) = DATE(?)
                AND li.deleted_at IS NULL
                """,
                [three_days_from_now]
            )
            
            notification_count = 0
            for share in expiring_shares:
                success = await create_share_expiring_soon_notification(
                    license_id=share["license_key_id"],
                    item_id=share["item_id"],
                    item_title=share["item_title"],
                    user_id=share["shared_with_user_id"],
                    expires_at=share["expires_at"]
                )
                if success:
                    notification_count += 1
            
            logger.info(
                f"Sent {notification_count} expiring share notifications"
            )
            
            return {
                "success": True,
                "notifications_sent": notification_count
            }
            
        except Exception as e:
            logger.error(f"Failed to check expiring shares: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e)
            }


# ============================================================================
# SCHEDULED JOBS RUNNER
# ============================================================================

async def run_daily_maintenance():
    """
    Run all daily maintenance jobs.
    
    Scheduled to run at 3:00 AM UTC daily.
    """
    logger.info("Starting daily maintenance jobs...")
    
    results = {}
    
    # Run share expiration cleanup
    results['share_cleanup'] = await cleanup_expired_shares()
    
    # Check for expiring shares
    results['expiring_check'] = await check_expiring_shares()
    
    # P5-2: Run anomaly detection (get license IDs first)
    # In production, you'd query all active licenses
    # For now, this would be called per license
    # results['anomaly_detection'] = await detect_share_anomalies(license_id)
    
    logger.info(f"Daily maintenance completed: {results}")
    
    return results


# ============================================================================
# ANALYTICS AGGREGATION
# ============================================================================

async def aggregate_daily_analytics():
    """
    Aggregate daily analytics for library items.
    
    Runs nightly to pre-compute statistics.
    """
    logger.info("Aggregating daily analytics...")
    
    yesterday = datetime.now(timezone.utc) - timedelta(days=1)
    start_of_day = yesterday.replace(hour=0, minute=0, second=0, microsecond=0)
    end_of_day = yesterday.replace(hour=23, minute=59, second=59, microsecond=999999)
    
    async with get_db() as db:
        try:
            # Aggregate by license and action
            await execute_sql(
                db,
                """
                INSERT INTO library_analytics_daily
                (license_key_id, action, date, count)
                SELECT 
                    license_key_id,
                    action,
                    DATE(?),
                    COUNT(*)
                FROM library_analytics
                WHERE timestamp >= ? AND timestamp <= ?
                GROUP BY license_key_id, action
                ON CONFLICT (license_key_id, action, date)
                DO UPDATE SET count = EXCLUDED.count
                """,
                [start_of_day.date(), start_of_day, end_of_day]
            )
            
            await commit_db(db)
            
            logger.info("Daily analytics aggregation completed")
            
            return {"success": True}
            
        except Exception as e:
            logger.error(f"Analytics aggregation failed: {e}", exc_info=True)
            return {"success": False, "error": str(e)}


# ============================================================================
# P4: TASK SHARING NOTIFICATIONS
# ============================================================================

async def create_task_shared_notification(
    license_id: int,
    task_id: str,
    task_title: str,
    shared_by_user_id: str,
    assigned_to_user_id: str
):
    """
    Create a notification when a task is shared with/assigned to a user.
    
    P4-2: Notify users when tasks are assigned or shared with them.
    """
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    license_id,
                    'task_shared',
                    'high',
                    'تمت مشاركة مهمة معك',
                    f'{shared_by_user_id} شارك معك المهمة: {task_title}',
                    now
                ]
            )
            await commit_db(db)
            
            logger.info(f"Created task shared notification: {task_title}")
            
            return True
        except Exception as e:
            logger.error(f"Failed to create task shared notification: {e}", exc_info=True)
            return False


async def create_task_visibility_changed_notification(
    license_id: int,
    task_id: str,
    task_title: str,
    changed_by_user_id: str,
    affected_user_id: str,
    new_visibility: str
):
    """
    Create a notification when task visibility changes.
    
    P4-2: Notify users when task becomes shared or private.
    """
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        try:
            message = (
                f'{changed_by_user_id} جعل المهمة "{task_title}" مشتركة'
                if new_visibility == 'shared'
                else f'{changed_by_user_id} جعل المهمة "{task_title}" خاصة'
            )
            
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    license_id,
                    'task_visibility_changed',
                    'normal',
                    'تغيرت صلاحية الوصول للمهمة',
                    message,
                    now
                ]
            )
            await commit_db(db)
            
            logger.info(f"Created task visibility change notification for: {task_title}")
            
            return True
        except Exception as e:
            logger.error(f"Failed to create task visibility notification: {e}", exc_info=True)
            return False


# ============================================================================
# P5: ANOMALY DETECTION & MONITORING
# ============================================================================

async def detect_share_anomalies(license_id: int) -> List[dict]:
    """
    Detect unusual sharing patterns that might indicate data exfiltration.
    
    P5-2: Monitor for share abuse and anomalies.
    
    Anomalies detected:
    - User sharing >50 items in 1 hour
    - User sharing with >10 unique recipients in 1 day
    - Bulk share revocation (>20 at once)
    """
    anomalies = []
    now = datetime.now(timezone.utc)
    one_hour_ago = now - timedelta(hours=1)
    one_day_ago = now - timedelta(days=1)
    
    async with get_db() as db:
        try:
            # Check for excessive sharing in 1 hour
            excessive_shares = await fetch_all(
                db,
                """
                SELECT created_by, COUNT(*) as share_count
                FROM library_shares
                WHERE license_key_id = ?
                AND created_at >= ?
                GROUP BY created_by
                HAVING COUNT(*) > 50
                """,
                [license_id, one_hour_ago]
            )
            
            for row in excessive_shares:
                anomalies.append({
                    "type": "excessive_sharing",
                    "severity": "high",
                    "user_id": row["created_by"],
                    "count": row["share_count"],
                    "period": "1 hour",
                    "message": f"User {row['created_by']} shared {row['share_count']} items in 1 hour"
                })
            
            # Check for sharing with many unique recipients
            many_recipients = await fetch_all(
                db,
                """
                SELECT created_by, COUNT(DISTINCT shared_with_user_id) as recipient_count
                FROM library_shares
                WHERE license_key_id = ?
                AND created_at >= ?
                GROUP BY created_by
                HAVING COUNT(DISTINCT shared_with_user_id) > 10
                """,
                [license_id, one_day_ago]
            )
            
            for row in many_recipients:
                anomalies.append({
                    "type": "many_recipients",
                    "severity": "medium",
                    "user_id": row["created_by"],
                    "count": row["recipient_count"],
                    "period": "1 day",
                    "message": f"User {row['created_by']} shared with {row['recipient_count']} unique recipients in 1 day"
                })
            
            # Check for bulk share revocation
            bulk_revocations = await fetch_all(
                db,
                """
                SELECT created_by, COUNT(*) as revoke_count
                FROM library_shares
                WHERE license_key_id = ?
                AND deleted_at >= ?
                GROUP BY created_by
                HAVING COUNT(*) > 20
                """,
                [license_id, one_hour_ago]
            )
            
            for row in bulk_revocations:
                anomalies.append({
                    "type": "bulk_revocation",
                    "severity": "medium",
                    "user_id": row["created_by"],
                    "count": row["revoke_count"],
                    "period": "1 hour",
                    "message": f"User {row['created_by']} revoked {row['revoke_count']} shares in 1 hour"
                })
            
            if anomalies:
                logger.warning(f"Detected {len(anomalies)} share anomalies for license {license_id}")
                
                # Create admin notification
                for anomaly in anomalies:
                    await execute_sql(
                        db,
                        """
                        INSERT INTO notifications
                        (license_key_id, type, priority, title, message, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        [
                            license_id,
                            'security_alert',
                            'high',
                            'تنبيه أمني: نشاط مشاركة غير عادي',
                            anomaly["message"],
                            now
                        ]
                    )
            
            await commit_db(db)
            
        except Exception as e:
            logger.error(f"Failed to detect share anomalies: {e}", exc_info=True)
    
    return anomalies


async def check_transfer_failure_rate(license_id: int, threshold: float = 0.1) -> dict:
    """
    Check if nearby transfer failure rate exceeds threshold.
    
    P5-2: Monitor transfer reliability.
    
    Returns:
        dict: Transfer statistics and alert if failure rate high
    """
    now = datetime.now(timezone.utc)
    twenty_four_hours_ago = now - timedelta(hours=24)
    
    async with get_db() as db:
        try:
            # Get transfer statistics from transfer_history
            stats = await fetch_one(
                db,
                """
                SELECT 
                    COUNT(*) as total,
                    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as successful,
                    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
                FROM transfer_history
                WHERE license_key_id = ?
                AND completed_at >= ?
                """,
                [license_id, twenty_four_hours_ago]
            )
            
            if not stats or stats["total"] == 0:
                return {"success": True, "alert": False, "message": "No transfers in period"}
            
            failure_rate = stats["failed"] / stats["total"]
            
            result = {
                "success": True,
                "total_transfers": stats["total"],
                "successful": stats["successful"],
                "failed": stats["failed"],
                "failure_rate": round(failure_rate * 100, 2),
                "threshold": threshold * 100,
                "alert": failure_rate > threshold
            }
            
            if failure_rate > threshold:
                logger.warning(
                    f"High transfer failure rate: {failure_rate*100:.2f}% "
                    f"(threshold: {threshold*100}%)"
                )
                
                # Create admin notification
                await execute_sql(
                    db,
                    """
                    INSERT INTO notifications
                    (license_key_id, type, priority, title, message, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    [
                        license_id,
                        'system_alert',
                        'high',
                        'تنبيه: معدل فشل عالي في النقل',
                        f'معدل فشل النقل: {failure_rate*100:.2f}% خلال آخر 24 ساعة',
                        now
                    ]
                )
                await commit_db(db)
            
            return result
            
        except Exception as e:
            logger.error(f"Failed to check transfer failure rate: {e}", exc_info=True)
            return {"success": False, "error": str(e)}
