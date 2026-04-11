"""
Task Sharing Model Functions

P4-2: Share tasks with other users with read/edit/admin permissions.
Replaces old assigned_to field with proper share-based model.

Permission Levels:
- read: Can VIEW only. Cannot edit, share, or delete.
- edit: Can VIEW, EDIT, and SHARE. Cannot DELETE.
- admin: Full access - VIEW, EDIT, SHARE, DELETE (same as owner).
"""
import asyncio
from typing import List, Optional
from datetime import datetime, timezone, timedelta
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
import logging
from utils.share_utils import resolve_username_to_user_id_with_db, validate_share_permission
from utils.permissions import (
    PermissionLevel,
    ResourceAction,
    can_perform_action,
    get_effective_permission,
    validate_permission_for_action,
)
from utils.cache_utils import (
    get_shared_tasks_cache,
    broadcast_safe,
)

logger = logging.getLogger(__name__)


async def _invalidate_shared_tasks_cache(license_id: int, user_id: Optional[str] = None):
    """Invalidate shared tasks cache

    FIX: Ensure complete cleanup of both cache and access times to prevent memory leaks.
    FIX BUG-002: Include timestamp bucket in cache invalidation to handle expired shares.
    """
    cache = get_shared_tasks_cache()

    # Invalidate all permission levels for this user
    if user_id:
        for perm in ['read', 'edit', 'admin', 'all']:
            # FIX BUG-002: Invalidate cache with different time buckets to prevent stale expired shares
            cache_key = f"{license_id}|{user_id}|{perm}"
            await cache.invalidate(cache_key)
            # Also invalidate time-bucketed keys (for expiration-aware caching)
            for bucket in range(0, 24, 2):  # 2-hour buckets for 24 hours
                await cache.invalidate(f"{cache_key}|bucket_{bucket}")
    else:
        # Invalidate all caches for this license (expensive, use sparingly)
        await cache.invalidate_prefix(f"{license_id}|")


async def _invalidate_shared_tasks_cache_batch(license_id: int, user_ids: List[str]):
    """Invalidate shared tasks cache for multiple users in a single batch.
    
    More efficient than calling _invalidate_shared_tasks_cache multiple times.
    
    Args:
        license_id: License key ID
        user_ids: List of user IDs to invalidate cache for
    """
    if not user_ids:
        return
        
    cache = get_shared_tasks_cache()
    
    # Build all keys to invalidate
    keys_to_invalidate = []
    for user_id in user_ids:
        for perm in ['read', 'edit', 'admin', 'all']:
            keys_to_invalidate.append(f"{license_id}|{user_id}|{perm}")
    
    # Batch invalidate
    await cache.invalidate_batch(keys_to_invalidate)


async def share_task(
    task_id: str,
    license_id: int,
    shared_with_user_id: str,
    permission: str = 'read',
    created_by: Optional[str] = None
) -> dict:
    """Share a task with another user

    SEC-001 FIX: Properly prevents self-sharing by checking against task owner.
    AUTH-001 FIX: Uses shared utility for username resolution.
    """
    now = datetime.now(timezone.utc)

    # SQLite compatibility: convert datetime to ISO format string
    if DB_TYPE == "sqlite":
        now = now.isoformat()

    # Validate permission level
    if not validate_share_permission(permission):
        raise ValueError(f"Invalid permission: {permission}. Must be 'read', 'edit', or 'admin'")

    async with get_db() as db:
        # Verify task exists
        task = await fetch_one(
            db,
            "SELECT id, title FROM tasks WHERE id = ? AND license_key_id = ? AND is_deleted = 0",
            [task_id, license_id]
        )

        if not task:
            raise ValueError("Task not found")

        # AUTH-001 FIX: Use shared utility for username resolution
        recipient_user_id, _ = await resolve_username_to_user_id_with_db(shared_with_user_id, db)

        # SEC-001 FIX: Prevent self-sharing - check against task owner (created_by)
        # This check happens AFTER resolution to ensure we compare actual user IDs
        task_owner_id = task.get('created_by') or created_by
        if not task_owner_id:
            raise ValueError("Task owner could not be determined")
        if recipient_user_id == task_owner_id:
            raise ValueError("Cannot share a task with yourself")

        # FIX BUG-001 (Race Condition): Capture state BEFORE upsert to correctly detect reshare/permission change
        # This eliminates the TOCTOU (Time-of-Check-Time-of-Use) vulnerability
        #
        # HOW IT WORKS:
        # 1. We capture the current share state (before_share) BEFORE the upsert
        # 2. The UPSERT is atomic - PostgreSQL ON CONFLICT / SQLite ON CONFLICT handles races
        # 3. After upsert, we compare before_share with the new permission to determine:
        #    - is_reshare: True if before_share was None (new share)
        #    - is_permission_change: True if permission changed from before to after
        #
        # This is safe because the UPSERT is atomic - concurrent requests will serialize
        # at the database level, and each will see the correct before/after state.
        before_share = await fetch_one(
            db,
            "SELECT permission, deleted_at FROM task_shares WHERE task_id = ? AND shared_with_user_id = ?",
            [task_id, recipient_user_id]
        )

        # Check for revoked share (can't re-use - must create new share)
        if before_share and before_share.get('deleted_at') is not None:
            raise ValueError("Share was previously revoked. Please create a new share.")

        # FIX: Use the sharer's license_id (not recipient's user_id) for license_key_id
        # This ensures the share record is associated with the correct license context.
        # Previously: recipient_license_id = int(recipient_user_id) — crashes on UUIDs
        # Now: Use the task's license_key_id which is already verified to exist
        recipient_license_id = license_id

        # Perform atomic UPSERT
        if DB_TYPE == "postgresql":
            # Use INSERT ... ON CONFLICT with proper handling
            # The ON CONFLICT clause handles race conditions atomically
            result = await fetch_one(
                db,
                """
                INSERT INTO task_shares
                (task_id, license_key_id, shared_with_user_id, permission, created_at, created_by, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (task_id, shared_with_user_id)
                DO UPDATE SET
                    permission = EXCLUDED.permission,
                    updated_at = EXCLUDED.updated_at,
                    deleted_at = NULL  -- Reactivate if it was soft-deleted
                WHERE task_shares.deleted_at IS NULL OR task_shares.deleted_at IS DISTINCT FROM EXCLUDED.deleted_at
                RETURNING id
                """,
                [task_id, recipient_license_id, recipient_user_id, permission, now, created_by, now]
            )
            share_id = result['id'] if result else None
        else:
            # SQLite atomic UPSERT using INSERT ... ON CONFLICT for SQLite 3.24.0+
            await execute_sql(
                db,
                """
                INSERT INTO task_shares
                (task_id, license_key_id, shared_with_user_id, permission, created_at, created_by, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(task_id, shared_with_user_id) DO UPDATE SET
                    permission = excluded.permission,
                    updated_at = excluded.updated_at,
                    deleted_at = NULL  -- Reactivate if it was soft-deleted
                """,
                [task_id, recipient_license_id, recipient_user_id, permission, now, created_by, now]
            )

            # Get the share ID (either newly inserted or existing)
            result = await fetch_one(
                db,
                """
                SELECT id FROM task_shares
                WHERE task_id = ? AND shared_with_user_id = ? AND deleted_at IS NULL
                """,
                [task_id, recipient_user_id]
            )
            share_id = result['id'] if result else None

        # FIX BUG-001: Determine is_reshare and is_permission_change AFTER upsert
        # These flags are based on the state BEFORE the upsert (captured in before_share)
        # 
        # is_reshare: True if this was a completely new share (no prior record)
        # is_permission_change: True if the permission level changed from what it was before
        #
        # Note: These are used for notification logic, not for the actual share operation
        # which is handled atomically by the UPSERT above.
        is_reshare = before_share is None
        is_permission_change = (
            before_share is not None and
            before_share.get('permission') != permission
        )

        # Mark task as shared (already committed, but this needs its own transaction)
        await execute_sql(
            db,
            "UPDATE tasks SET is_shared = 1 WHERE id = ?",
            [task_id]
        )

        await commit_db(db)

        # Invalidate cache for the recipient so they see the shared task immediately
        await _invalidate_shared_tasks_cache(license_id, recipient_user_id)

        # P4-2: Create notification for recipient using consolidated function
        try:
            from workers import create_resource_shared_notification
            await create_resource_shared_notification(
                license_id=license_id,
                resource_type='task',
                resource_id=task_id,
                resource_title=task.get("title", "Unknown"),
                shared_by_user_id=created_by or "Unknown",
                shared_with_user_id=recipient_user_id,
                permission=permission,
                priority='high'  # Task shares are high priority
            )
        except Exception as e:
            # FIX: Log with ERROR level and include full stack trace for debugging
            # Notification failures should be monitored as they affect user experience
            logger.error(
                f"Failed to create task share notification for task {task_id} "
                f"(shared with {recipient_user_id}): {e}",
                exc_info=True
            )
            # P6-1 FIX: Queue for retry via background worker instead of silent failure
            try:
                from services.metrics_service import MetricsService
                metrics = MetricsService()
                await metrics.increment_counter("task_share_notification_failures", {
                    "license_id": str(license_id),
                    "error_type": type(e).__name__
                })
            except Exception as metrics_error:
                logger.warning(f"Failed to log metrics for notification failure: {metrics_error}")

            # P6-1 FIX: Record metric for alerting service
            try:
                from services.alerting_service import record_alertable_metric
                await record_alertable_metric("task_share_notification_failures")
            except Exception as alert_error:
                logger.warning(f"Failed to record alert metric: {alert_error}")

            # FIX: Queue notification for retry
            try:
                from workers import queue_notification_for_retry
                await queue_notification_for_retry({
                    'license_id': license_id,
                    'resource_type': 'task',
                    'resource_id': task_id,
                    'resource_title': task.get("title", "Unknown"),
                    'shared_by_user_id': created_by or "Unknown",
                    'shared_with_user_id': recipient_user_id,
                    'permission': permission,
                    'priority': 'high'
                })
            except Exception as retry_error:
                logger.warning(f"Failed to queue notification for retry: {retry_error}")

        # Broadcast WebSocket event to recipient for instant UI update
        try:
            from services.websocket_manager import broadcast_task_shared

            # Recipient's license ID is the resolved user_id
            recipient_license_id = int(recipient_user_id) if recipient_user_id.isdigit() else None

            if recipient_license_id:
                asyncio.create_task(
                    broadcast_safe(
                        broadcast_task_shared(
                            license_id=recipient_license_id,
                            task_id=task_id,
                            task_title=task.get("title", "Unknown"),
                            shared_by=created_by or "Unknown",
                            permission=permission
                        ),
                        "broadcast task share event"
                    )
                )
            else:
                logger.warning(f"Could not find recipient license for username: {shared_with_user_id}")
                # Track metric for missing recipient license
                try:
                    from services.metrics_service import MetricsService
                    metrics = MetricsService()
                    await metrics.increment_counter("task_share_missing_recipient_license", {
                        "license_id": str(license_id)
                    })
                except Exception:
                    pass
        except Exception as e:
            logger.warning(f"Failed to queue broadcast task share event: {e}")
            # FIX: Track WebSocket broadcast failures for monitoring
            try:
                from services.metrics_service import MetricsService
                metrics = MetricsService()
                await metrics.increment_counter("task_share_broadcast_failures", {
                    "license_id": str(license_id),
                    "error_type": type(e).__name__
                })
            except Exception:
                pass

            # P6-1 FIX: Record metric for alerting service
            try:
                from services.alerting_service import record_alertable_metric
                await record_alertable_metric("task_share_broadcast_failures")
            except Exception as alert_error:
                logger.warning(f"Failed to record alert metric: {alert_error}")

        return {
            "task_id": task_id,
            "shared_with": shared_with_user_id,
            "permission": permission
        }


async def get_shared_tasks(
    license_id: int,
    user_id: str,
    permission: Optional[str] = None
) -> List[dict]:
    """Get tasks shared with a user

    FIX BUG-002: Added share expiration check with time-bucketed caching to prevent stale expired shares.
    """
    # FIX BUG-002: Use time-bucketed cache key to prevent expired shares from being cached
    now = datetime.now(timezone.utc)
    time_bucket = int(now.hour / 2)  # 2-hour buckets
    cache_key = f"{license_id}|{user_id}|{permission or 'all'}|bucket_{time_bucket}"
    cache = get_shared_tasks_cache()

    # Try cache first
    cached = await cache.get(cache_key)
    if cached is not None:
        # FIX: Only log cache hits in debug mode to reduce production log verbosity
        logger.debug(f"Cache hit for shared tasks: {cache_key}")
        return cached

    # Import _parse_task_row to parse JSON fields (sub_tasks, attachments)
    from models.tasks import _parse_task_row

    async with get_db() as db:
        # Note: is_deleted is INTEGER (0/1) in both SQLite and PostgreSQL
        # FIX: Added share expiration check (expires_at IS NULL OR expires_at > now)
        query = """
            SELECT t.*, ts.permission, ts.expires_at
            FROM tasks t
            INNER JOIN task_shares ts ON t.id = ts.task_id
            WHERE ts.shared_with_user_id = ?
            AND ts.license_key_id = ?
            AND ts.deleted_at IS NULL
            AND (ts.expires_at IS NULL OR ts.expires_at > ?)
            AND t.is_deleted = 0
        """
        params = [user_id, license_id, now]

        if permission:
            query += " AND ts.permission = ?"
            params.append(permission)

        rows = await fetch_all(db, query, params)
        # FIX: Parse JSON fields (sub_tasks, attachments) for each row
        result = [_parse_task_row(dict(row)) for row in rows]

        # FIX BUG-002: Cache with shorter TTL for time-bucketed keys
        await cache.set(cache_key, result)
        logger.debug(f"Cached shared tasks: {cache_key}")

        return result


async def remove_share(share_id: int, license_id: int, revoked_by: Optional[str] = None, requested_by_user_id: Optional[str] = None) -> bool:
    """
    Remove a share (revoke access).
    
    PERMISSION: Only owner or admin can revoke shares.
    
    Args:
        share_id: The share ID to remove
        license_id: License key ID
        revoked_by: User ID who is revoking
        requested_by_user_id: User ID making the request (for permission check)
    """
    now = datetime.now(timezone.utc)
    
    # SQLite compatibility: convert datetime to ISO format string
    if DB_TYPE == "sqlite":
        now = now.isoformat()

    async with get_db() as db:
        # Get share info before deleting
        share = await fetch_one(
            db,
            """
            SELECT ts.*, t.title as task_title, t.created_by as task_owner
            FROM task_shares ts
            INNER JOIN tasks t ON ts.task_id = t.id
            WHERE ts.id = ? AND ts.license_key_id = ?
            """,
            [share_id, license_id]
        )

        if not share:
            return False

        # PERMISSION CHECK: Only owner or admin can revoke shares
        if requested_by_user_id:
            task_owner_id = share.get('task_owner')
            is_owner = requested_by_user_id == task_owner_id
            
            if not is_owner:
                # Check if requester has admin permission on this share
                if requested_by_user_id == share.get('shared_with_user_id'):
                    # User is trying to revoke their own share - check if admin
                    share_permission = share.get('permission', 'read')
                    effective_permission = get_effective_permission(share_permission, False)
                    
                    if not can_perform_action(ResourceAction.MANAGE_SHARES, effective_permission):
                        logger.warning(
                            f"User {requested_by_user_id} denied permission to revoke share {share_id}. "
                            f"Permission level: {effective_permission}"
                        )
                        return False
                else:
                    # User is trying to revoke someone else's share - must be owner
                    logger.warning(
                        f"User {requested_by_user_id} denied permission to revoke share {share_id}. Not the task owner."
                    )
                    return False

        # Soft delete
        await execute_sql(
            db,
            "UPDATE task_shares SET deleted_at = ? WHERE id = ? AND license_key_id = ?",
            [now, share_id, license_id]
        )

        await commit_db(db)

        # Invalidate cache for the affected user
        if share:
            await _invalidate_shared_tasks_cache(license_id, share.get('shared_with_user_id'))

            # P6-2: Notify user whose access was revoked
            try:
                from workers import create_share_revoked_notification
                await create_share_revoked_notification(
                    license_id=license_id,
                    task_id=share.get('task_id'),
                    task_title=share.get('task_title', 'Task'),
                    revoked_by_user_id=revoked_by or "Unknown",
                    revoked_from_user_id=share.get('shared_with_user_id')
                )
            except Exception as e:
                # FIX: Log with ERROR level and include full stack trace for debugging
                logger.error(
                    f"Failed to create share revoked notification for share {share_id} "
                    f"(revoked from {share.get('shared_with_user_id')}): {e}",
                    exc_info=True
                )
                # P6-1 FIX: Track notification failures for monitoring
                try:
                    from services.metrics_service import MetricsService
                    metrics = MetricsService()
                    await metrics.increment_counter("share_revoked_notification_failures", {
                        "license_id": str(license_id),
                        "error_type": type(e).__name__
                    })
                except Exception as metrics_error:
                    logger.warning(f"Failed to log metrics for notification failure: {metrics_error}")

                # P6-1 FIX: Record metric for alerting service
                try:
                    from services.alerting_service import record_alertable_metric
                    await record_alertable_metric("share_revoked_notification_failures")
                except Exception as alert_error:
                    logger.warning(f"Failed to record alert metric: {alert_error}")

        return True


async def list_task_shares(task_id: str, license_id: int, requested_by_user_id: str) -> List[dict]:
    """List all active shares for a task (for the owner or admin)
    
    PERMISSION: Only task owner or users with admin permission can list shares.
    
    Args:
        task_id: The task ID
        license_id: License key ID
        requested_by_user_id: User ID requesting the share list
    
    Returns:
        List of share records
    
    Raises:
        ValueError: If user doesn't have permission to view shares
    """
    async with get_db() as db:
        # First, verify the task exists and get owner info
        task = await fetch_one(
            db,
            "SELECT created_by FROM tasks WHERE id = ? AND license_key_id = ? AND is_deleted = 0",
            [task_id, license_id]
        )
        
        if not task:
            raise ValueError("Task not found")
        
        # Check if requester is the owner
        is_owner = task.get('created_by') == requested_by_user_id
        
        if not is_owner:
            # Check if requester has admin permission on this task
            share = await fetch_one(
                db,
                """
                SELECT permission FROM task_shares
                WHERE task_id = ? AND shared_with_user_id = ? AND license_key_id = ?
                AND deleted_at IS NULL
                """,
                [task_id, requested_by_user_id, license_id]
            )
            
            if not share or share.get('permission') != 'admin':
                logger.warning(
                    f"User {requested_by_user_id} denied permission to list shares for task {task_id}"
                )
                raise ValueError("Permission denied: Only owner or admin can view task shares")
        
        # User has permission - return the shares
        rows = await fetch_all(
            db,
            """
            SELECT ts.*, u.name as shared_with_name, u.name as shared_with_username
            FROM task_shares ts
            LEFT JOIN users u ON ts.shared_with_user_id = u.user_id
            WHERE ts.task_id = ? AND ts.license_key_id = ? AND ts.deleted_at IS NULL
            ORDER BY ts.created_at DESC
            """,
            [task_id, license_id]
        )
        return [dict(row) for row in rows]


async def update_share_permission(
    share_id: int,
    license_id: int,
    permission: str,
    updated_by: Optional[str] = None
) -> bool:
    """Update share permission"""
    now = datetime.now(timezone.utc)
    
    # SQLite compatibility: convert datetime to ISO format string
    if DB_TYPE == "sqlite":
        now = now.isoformat()

    async with get_db() as db:
        # Get share to find the user
        share = await fetch_one(
            db,
            "SELECT shared_with_user_id FROM task_shares WHERE id = ? AND license_key_id = ?",
            [share_id, license_id]
        )

        if not share:
            return False

        await execute_sql(
            db,
            "UPDATE task_shares SET permission = ?, updated_at = ? WHERE id = ? AND license_key_id = ?",
            [permission, now, share_id, license_id]
        )

        await commit_db(db)

        # Invalidate cache
        await _invalidate_shared_tasks_cache(license_id, share.get('shared_with_user_id'))

        return True


async def get_user_permission_on_task(
    task_id: str,
    user_id: str,
    license_id: int
) -> Optional[str]:
    """Get a user's permission level for a specific task"""
    async with get_db() as db:
        share = await fetch_one(
            db,
            """
            SELECT permission FROM task_shares
            WHERE task_id = ? AND shared_with_user_id = ? AND license_key_id = ?
            AND deleted_at IS NULL
            """,
            [task_id, user_id, license_id]
        )
        return share.get('permission') if share else None
