"""
Al-Mudeer - Library Background Jobs
Scheduled tasks for library maintenance:
- Expired share cleanup
- Trash auto-delete (30 days)
- Orphaned file cleanup
- Storage quota warnings
"""

import os
import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing import List, Tuple
from pathlib import Path

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db
from services.file_storage_service import get_file_storage

logger = logging.getLogger(__name__)

# Configuration
TRASH_RETENTION_DAYS = int(os.getenv("TRASH_RETENTION_DAYS", "30"))
SHARE_EXPIRY_CHECK_INTERVAL_HOURS = int(os.getenv("SHARE_EXPIRY_CHECK_INTERVAL_HOURS", "6"))
QUOTA_WARNING_THRESHOLDS = [0.95, 0.90, 0.80]  # 95%, 90%, 80%


async def cleanup_expired_shares() -> int:
    """
    Clean up expired shares (shares past their expires_at timestamp).
    
    This job:
    1. Finds all shares where expires_at < now AND deleted_at IS NULL
    2. Soft deletes them by setting deleted_at
    3. Updates the parent item's is_shared flag if no more active shares
    
    Returns: Number of shares cleaned up
    """
    now = datetime.now(timezone.utc)
    cleaned_count = 0
    
    try:
        async with get_db() as db:
            # Find expired shares
            expired_shares = await fetch_all(
                db,
                """
                SELECT id, item_id, license_key_id, shared_with_user_id
                FROM library_shares
                WHERE expires_at IS NOT NULL 
                AND expires_at < ?
                AND deleted_at IS NULL
                """,
                [now]
            )
            
            if not expired_shares:
                return 0
            
            # Soft delete each expired share
            for share in expired_shares:
                await execute_sql(
                    db,
                    "UPDATE library_shares SET deleted_at = ? WHERE id = ?",
                    [now, share["id"]]
                )
                cleaned_count += 1
                
                # Update parent item's is_shared flag if no more active shares
                remaining_shares = await fetch_one(
                    db,
                    """
                    SELECT COUNT(*) as count FROM library_shares
                    WHERE item_id = ? AND deleted_at IS NULL
                    """,
                    [share["item_id"]]
                )
                
                if remaining_shares and remaining_shares["count"] == 0:
                    await execute_sql(
                        db,
                        "UPDATE library_items SET is_shared = 0 WHERE id = ?",
                        [share["item_id"]]
                    )
            
            await commit_db(db)
            
            logger.info(f"Cleaned up {cleaned_count} expired library shares")
            
            # Invalidate share caches for affected users
            if cleaned_count > 0:
                from models.library_advanced import _invalidate_shared_items_cache_batch
                user_ids = [s["shared_with_user_id"] for s in expired_shares]
                license_ids = set(s["license_key_id"] for s in expired_shares)
                
                for license_id in license_ids:
                    await _invalidate_shared_items_cache_batch(license_id, user_ids)
            
    except Exception as e:
        logger.error(f"Failed to cleanup expired shares: {e}", exc_info=True)
    
    return cleaned_count


async def cleanup_old_trash() -> Tuple[int, int]:
    """
    Permanently delete items in trash older than TRASH_RETENTION_DAYS.

    This job:
    1. Finds all items where deleted_at < (now - TRASH_RETENTION_DAYS)
    2. Deletes the physical files
    3. Permanently removes from database

    BUG-007 FIX: Uses UTC time for consistency across timezones.
    Users should be informed that "30 days" means 30 days UTC time.

    Returns: Tuple of (items_deleted, bytes_freed)
    """
    # BUG-007 FIX: Use UTC for consistent behavior across timezones
    # Note: This is intentional for multi-server deployments
    # UI should clarify "30 days (UTC)" to users
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=TRASH_RETENTION_DAYS)
    items_deleted = 0
    bytes_freed = 0
    
    try:
        async with get_db() as db:
            # Find old trashed items
            old_trash = await fetch_all(
                db,
                """
                SELECT id, license_key_id, file_path, file_size
                FROM library_items
                WHERE deleted_at IS NOT NULL
                AND deleted_at < ?
                """,
                [cutoff_date]
            )
            
            if not old_trash:
                return 0, 0
            
            file_storage = get_file_storage()
            
            # Delete each item
            for item in old_trash:
                # Delete physical file
                if item.get("file_path"):
                    try:
                        file_storage.delete_file(item["file_path"])
                        logger.debug(f"Deleted physical file: {item['file_path']}")
                    except Exception as e:
                        logger.warning(f"Failed to delete physical file {item['file_path']}: {e}")
                
                # Track bytes freed
                if item.get("file_size"):
                    bytes_freed += item["file_size"]
                
                # Also delete attachments
                attachments = await fetch_all(
                    db,
                    """
                    SELECT id, file_path, file_size FROM library_attachments
                    WHERE library_item_id = ? AND deleted_at IS NOT NULL
                    """,
                    [item["id"]]
                )
                
                for attachment in attachments:
                    if attachment.get("file_path"):
                        try:
                            file_storage.delete_file(attachment["file_path"])
                        except Exception as e:
                            logger.warning(f"Failed to delete attachment file {attachment['file_path']}: {e}")
                    
                    if attachment.get("file_size"):
                        bytes_freed += attachment["file_size"]
                    
                    # Delete attachment record
                    await execute_sql(
                        db,
                        "DELETE FROM library_attachments WHERE id = ?",
                        [attachment["id"]]
                    )
                
                # Permanently delete from database
                await execute_sql(
                    db,
                    "DELETE FROM library_items WHERE id = ?",
                    [item["id"]]
                )
                
                items_deleted += 1
            
            await commit_db(db)
            
            logger.info(
                f"Cleaned up {items_deleted} items from trash, "
                f"freed {bytes_freed / 1024 / 1024:.2f} MB"
            )
            
            # Invalidate storage cache for affected licenses
            if items_deleted > 0:
                from models.library import _invalidate_storage_cache
                license_ids = set(item["license_key_id"] for item in old_trash)
                for license_id in license_ids:
                    await _invalidate_storage_cache(license_id)
            
    except Exception as e:
        logger.error(f"Failed to cleanup old trash: {e}", exc_info=True)
    
    return items_deleted, bytes_freed


async def cleanup_orphaned_files() -> Tuple[int, int]:
    """
    Clean up orphaned files (files on disk without database records).
    
    This job:
    1. Scans the upload directory for library files
    2. Cross-references with database records
    3. Deletes files without matching database entries
    
    Returns: Tuple of (files_deleted, bytes_freed)
    """
    files_deleted = 0
    bytes_freed = 0
    
    try:
        upload_dir = Path(os.getenv("UPLOAD_DIR", "static/uploads"))
        library_dir = upload_dir / "library"
        
        if not library_dir.exists():
            logger.debug("Library upload directory does not exist")
            return 0, 0
        
        async with get_db() as db:
            # Get all file paths from database
            db_files = await fetch_all(
                db,
                """
                SELECT DISTINCT file_path FROM library_items
                WHERE file_path IS NOT NULL AND deleted_at IS NULL
                """
            )
            db_file_paths = set(f["file_path"] for f in db_files)
            
            # Also get attachment file paths
            attachment_files = await fetch_all(
                db,
                """
                SELECT DISTINCT file_path FROM library_attachments
                WHERE file_path IS NOT NULL AND deleted_at IS NULL
                """
            )
            db_file_paths.update(f["file_path"] for f in attachment_files)
            
            # Scan filesystem
            for file_path in library_dir.rglob("*"):
                if file_path.is_file():
                    # Convert to relative path for comparison
                    relative_path = str(file_path.relative_to(upload_dir))
                    
                    if relative_path not in db_file_paths:
                        # Orphaned file - delete it
                        try:
                            file_size = file_path.stat().st_size
                            file_path.unlink()
                            files_deleted += 1
                            bytes_freed += file_size
                            logger.debug(f"Deleted orphaned file: {relative_path}")
                        except Exception as e:
                            logger.warning(f"Failed to delete orphaned file {relative_path}: {e}")
            
            logger.info(
                f"Cleaned up {files_deleted} orphaned files, "
                f"freed {bytes_freed / 1024 / 1024:.2f} MB"
            )
            
    except Exception as e:
        logger.error(f"Failed to cleanup orphaned files: {e}", exc_info=True)
    
    return files_deleted, bytes_freed


async def check_storage_quotas() -> List[dict]:
    """
    Check storage quotas and send warnings to users approaching limits.
    
    This job:
    1. Calculates storage usage for each license
    2. Identifies licenses above warning thresholds (80%, 90%, 95%)
    3. Creates notifications for affected users
    
    Returns: List of licenses with their warning levels
    """
    warnings_sent = []
    
    try:
        async with get_db() as db:
            # Get all active licenses
            licenses = await fetch_all(
                db,
                """
                SELECT id, key_hash, full_name, user_id
                FROM license_keys
                WHERE is_active = 1
                """
            )
            
            from models.library import MAX_STORAGE_PER_LICENSE, get_storage_usage
            
            for license in licenses:
                license_id = license["id"]
                
                # Calculate storage usage
                usage = await get_storage_usage(license_id)
                percentage = usage / MAX_STORAGE_PER_LICENSE
                
                # Determine warning level
                warning_level = None
                if percentage >= 0.95:
                    warning_level = "critical"
                elif percentage >= 0.90:
                    warning_level = "high"
                elif percentage >= 0.80:
                    warning_level = "warning"
                
                if warning_level:
                    # Create notification
                    try:
                        from workers import create_storage_warning_notification
                        await create_storage_warning_notification(
                            license_id=license_id,
                            user_id=license.get("user_id"),
                            usage_bytes=usage,
                            limit_bytes=MAX_STORAGE_PER_LICENSE,
                            warning_level=warning_level
                        )
                        
                        warnings_sent.append({
                            "license_id": license_id,
                            "license_name": license.get("full_name"),
                            "warning_level": warning_level,
                            "percentage": round(percentage * 100, 2)
                        })
                        
                        logger.info(
                            f"Storage warning sent to {license.get('full_name')}: "
                            f"{warning_level} ({percentage*100:.1f}%)"
                        )
                        
                    except Exception as e:
                        logger.error(
                            f"Failed to send storage warning to license {license_id}: {e}"
                        )
                        
    except Exception as e:
        logger.error(f"Failed to check storage quotas: {e}", exc_info=True)
    
    return warnings_sent


async def run_all_library_cleanup_jobs() -> dict:
    """
    Run all library cleanup jobs.
    
    Returns: Summary of cleanup results
    """
    logger.info("Starting library cleanup jobs...")
    
    results = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "expired_shares_cleaned": await cleanup_expired_shares(),
        "trash_items_cleaned": 0,
        "bytes_freed_from_trash": 0,
        "orphaned_files_cleaned": 0,
        "bytes_freed_from_orphans": 0,
        "quota_warnings_sent": []
    }
    
    trash_result = await cleanup_old_trash()
    results["trash_items_cleaned"] = trash_result[0]
    results["bytes_freed_from_trash"] = trash_result[1]
    
    orphan_result = await cleanup_orphaned_files()
    results["orphaned_files_cleaned"] = orphan_result[0]
    results["bytes_freed_from_orphans"] = orphan_result[1]
    
    results["quota_warnings_sent"] = await check_storage_quotas()
    
    logger.info(f"Library cleanup completed: {results}")
    
    return results


# Schedule for running jobs
# ============================================================================
# FIX #15: Integrated scheduler documentation and example implementation
# 
# To enable these cleanup jobs, add the following to your workers.py or
# create a dedicated scheduler using APScheduler or Celery Beat:
#
# Example with APScheduler:
# -------------------------
# from apscheduler.schedulers.asyncio import AsyncIOScheduler
# from apscheduler.triggers.cron import CronTrigger
# from services.library_cleanup_jobs import run_all_library_cleanup_jobs
#
# scheduler = AsyncIOScheduler()
#
# # Cleanup expired shares: Every 6 hours
# scheduler.add_job(
#     run_all_library_cleanup_jobs,
#     CronTrigger(hour='*/6', minute=0),
#     id='library_cleanup_expired_shares'
# )
#
# # Cleanup old trash: Daily at 2 AM
# scheduler.add_job(
#     run_all_library_cleanup_jobs,
#     CronTrigger(hour=2, minute=0),
#     id='library_cleanup_trash'
# )
#
# # Cleanup orphaned files: Weekly on Sunday at 3 AM
# scheduler.add_job(
#     run_all_library_cleanup_jobs,
#     CronTrigger(day_of_week='sun', hour=3, minute=0),
#     id='library_cleanup_orphans'
# )
#
# # Check storage quotas: Daily at 9 AM
# scheduler.add_job(
#     run_all_library_cleanup_jobs,
#     CronTrigger(hour=9, minute=0),
#     id='library_storage_quotas'
# )
#
# scheduler.start()
#
# Example with Celery Beat:
# -------------------------
# from celery.schedules import crontab
#
# app.conf.beat_schedule = {
#     'cleanup-expired-shares': {
#         'task': 'tasks.run_library_cleanup_job',
#         'schedule': crontab(minute=0, hour='*/6'),
#         'kwargs': {'job_type': 'expired_shares'}
#     },
#     'cleanup-old-trash': {
#         'task': 'tasks.run_library_cleanup_job',
#         'schedule': crontab(hour=2, minute=0),
#         'kwargs': {'job_type': 'trash'}
#     },
#     'cleanup-orphaned-files': {
#         'task': 'tasks.run_library_cleanup_job',
#         'schedule': crontab(hour=3, minute=0, day_of_week=0),  # Sunday
#         'kwargs': {'job_type': 'orphans'}
#     },
#     'check-storage-quotas': {
#         'task': 'tasks.run_library_cleanup_job',
#         'schedule': crontab(hour=9, minute=0),
#         'kwargs': {'job_type': 'quotas'}
#     },
# }
# ============================================================================
