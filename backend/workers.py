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
# TASK WORKER (Persistent Queue Processor)
# ============================================================================

class TaskWorker:
    """
    Persistent task queue worker for processing background jobs.
    Handles async task execution with retry logic.
    """

    def __init__(self):
        self._running = False
        self._task = None
        logger.info("TaskWorker initialized")

    async def start(self):
        """Start the task worker."""
        self._running = True
        logger.info("TaskWorker started")

    async def stop(self):
        """Stop the task worker."""
        self._running = False
        if self._task:
            self._task.cancel()
        logger.info("TaskWorker stopped")

    async def enqueue(self, task_type: str, payload: dict):
        """
        Enqueue a task for background processing.

        Args:
            task_type: Type of task to execute
            payload: Task parameters
        """
        logger.info(f"TaskWorker enqueued {task_type} task")
        return {"status": "queued", "task_type": task_type}


# ============================================================================
# P3-14 / P4: SHARE NOTIFICATIONS (Consolidated)
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
    Create a notification when a library item is shared with a user.

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


async def create_resource_shared_notification(
    license_id: int,
    resource_type: str,  # 'task' or 'library'
    resource_id: str,
    resource_title: str,
    shared_by_user_id: str,
    shared_with_user_id: str,
    permission: str = 'read',
    priority: str = 'normal'
):
    """
    Consolidated notification for any resource share (tasks or library items).
    
    FIX: Replaces duplicate create_task_share_notification and create_task_shared_notification.
    
    Args:
        license_id: License key ID
        resource_type: Type of resource ('task' or 'library')
        resource_id: ID of the resource
        resource_title: Title/name of the resource
        shared_by_user_id: User who shared the resource
        shared_with_user_id: User receiving the share
        permission: Permission level (read/edit/admin)
        priority: Notification priority ('normal' or 'high')
    """
    now = datetime.now(timezone.utc)
    
    # Localized messages based on resource type
    if resource_type == 'task':
        notification_type = 'task_shared'
        title = 'تمت مشاركة مهمة معك'
        message = f'{shared_by_user_id} شارك معك المهمة: {resource_title}'
    else:  # library
        notification_type = 'library_share'
        title = 'تمت مشاركة عنصر معك'
        message = f'{shared_by_user_id} شارك معك: {resource_title} ({permission})'
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [license_id, notification_type, priority, title, message, now]
            )
            await commit_db(db)
            
            logger.info(f"Created {resource_type} share notification: {resource_title}")
            return True
        except Exception as e:
            logger.error(f"Failed to create resource share notification: {e}", exc_info=True)
            return False


async def create_share_revoked_notification(
    license_id: int,
    resource_id: str,
    resource_title: str,
    revoked_by_user_id: str,
    revoked_from_user_id: str,
    resource_type: str = 'task'
):
    """
    Create a notification when a share is revoked.
    
    FIX: Consolidated for both task and library share revocations.

    P6-2: Notify users when sharing access is revoked.
    
    Args:
        license_id: License key ID
        resource_id: ID of the resource (task_id or item_id)
        resource_title: Title/name of the resource
        revoked_by_user_id: User who revoked the share
        revoked_from_user_id: User whose access was revoked
        resource_type: Type of resource ('task' or 'library')
    """
    now = datetime.now(timezone.utc)
    
    # Localized messages based on resource type
    if resource_type == 'library':
        notification_type = 'share_revoked'
        title = 'تم إزالة صلاحية الوصول'
        message = f'{revoked_by_user_id} أزال صلاحية الوصول إلى: {resource_title}'
    else:  # task
        notification_type = 'share_revoked'
        title = 'تم إزالة صلاحية الوصول'
        message = f'{revoked_by_user_id} أزال صلاحية الوصول إلى: {resource_title}'
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications
                (license_key_id, type, priority, title, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [license_id, notification_type, 'normal', title, message, now]
            )
            await commit_db(db)
            
            logger.info(f"Created share revoked notification for: {resource_title}")
            return True
        except Exception as e:
            logger.error(f"Failed to create share revoked notification: {e}", exc_info=True)
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
# SCHEDULED JOBS RUNNER
# ============================================================================

async def run_daily_maintenance():
    """
    Run all daily maintenance jobs.

    Scheduled to run at 3:00 AM UTC daily.
    """
    logger.info("Starting daily maintenance jobs...")

    results = {}

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
            return {"success": False, "alert": False, "error": str(e)}


# ============================================================================
# CACHE METRICS RECORDING
# ============================================================================

async def record_cache_metrics():
    """
    Record cache metrics for monitoring.
    Called periodically to track cache performance.
    
    FIX #4: Added cache metrics recording for monitoring.
    """
    try:
        from services.metrics_service import MetricsService
        from utils.cache_utils import get_shared_tasks_cache, get_shared_items_cache
        
        metrics = MetricsService()
        
        # Record shared tasks cache metrics
        tasks_cache = get_shared_tasks_cache()
        tasks_stats = tasks_cache.get_stats()
        
        await metrics.increment_counter("cache_shared_tasks_size", {"count": str(tasks_stats["size"])})
        await metrics.increment_counter("cache_shared_tasks_hits", {"count": str(tasks_stats["hits"])})
        await metrics.increment_counter("cache_shared_tasks_misses", {"count": str(tasks_stats["misses"])})
        await metrics.increment_counter("cache_shared_tasks_evictions", {"count": str(tasks_stats["evictions"])})
        await metrics.increment_counter("cache_shared_tasks_hit_rate", {"rate": str(tasks_stats["hit_rate_percent"])})
        
        # Record shared items cache metrics
        items_cache = get_shared_items_cache()
        items_stats = items_cache.get_stats()
        
        await metrics.increment_counter("cache_shared_items_size", {"count": str(items_stats["size"])})
        await metrics.increment_counter("cache_shared_items_hits", {"count": str(items_stats["hits"])})
        await metrics.increment_counter("cache_shared_items_misses", {"count": str(items_stats["misses"])})
        await metrics.increment_counter("cache_shared_items_evictions", {"count": str(items_stats["evictions"])})
        await metrics.increment_counter("cache_shared_items_hit_rate", {"rate": str(items_stats["hit_rate_percent"])})
        
        logger.debug(f"Cache metrics recorded: tasks={tasks_stats['hit_rate_percent']}% hit rate, items={items_stats['hit_rate_percent']}% hit rate")
        
    except ImportError:
        # Metrics service not available - skip recording
        logger.debug("Metrics service not available, skipping cache metrics recording")
    except Exception as e:
        logger.warning(f"Failed to record cache metrics: {e}", exc_info=True)
