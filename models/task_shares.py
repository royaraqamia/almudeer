"""
Task Sharing Model Functions

P4-2: Share tasks with other users with read/edit/admin permissions.
Replaces old assigned_to field with proper share-based model.
"""
from typing import List, Optional
from datetime import datetime, timezone, timedelta
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
import logging

logger = logging.getLogger(__name__)


async def _get_cached_shared_tasks(cache_key: str) -> Optional[List[dict]]:
    """Get cached shared tasks (simple in-memory cache)"""
    from services.cache import get_cache
    cache = get_cache()
    return cache.get(cache_key)


async def _cache_shared_tasks(cache_key: str, data: List[dict], ttl: int = 300):
    """Cache shared tasks"""
    from services.cache import get_cache
    cache = get_cache()
    cache.set(cache_key, data, ttl=ttl)


async def _invalidate_shared_tasks_cache(license_id: int, user_id: Optional[str] = None):
    """Invalidate shared tasks cache"""
    from services.cache import get_cache
    cache = get_cache()
    
    # Invalidate all permission levels for this user
    if user_id:
        for perm in ['read', 'edit', 'admin', 'all']:
            cache_key = f"{license_id}:{user_id}:{perm}"
            cache.delete(cache_key)
    else:
        # Invalidate all caches for this license (expensive, use sparingly)
        cache.delete_pattern(f"{license_id}:*")


async def share_task(
    task_id: str,
    license_id: int,
    shared_with_user_id: str,
    permission: str = 'read',
    created_by: Optional[str] = None
) -> dict:
    """Share a task with another user"""
    now = datetime.now(timezone.utc)

    async with get_db() as db:
        # Verify task exists
        task = await fetch_one(
            db,
            "SELECT id, title FROM tasks WHERE id = ? AND license_key_id = ? AND is_deleted = 0",
            [task_id, license_id]
        )

        if not task:
            raise ValueError("Task not found")

        # Check if share already exists (update instead)
        existing = await fetch_one(
            db,
            "SELECT id FROM task_shares WHERE task_id = ? AND shared_with_user_id = ? AND deleted_at IS NULL",
            [task_id, shared_with_user_id]
        )

        if existing:
            # Update existing share
            await execute_sql(
                db,
                """
                UPDATE task_shares
                SET permission = ?, updated_at = ?
                WHERE id = ?
                """,
                [permission, now, existing['id']]
            )
            share_id = existing['id']
        else:
            # Create new share
            if DB_TYPE == "postgresql":
                result = await fetch_one(
                    db,
                    """
                    INSERT INTO task_shares
                    (task_id, license_key_id, shared_with_user_id, permission, created_at, created_by)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    RETURNING id
                    """,
                    [task_id, license_id, shared_with_user_id, permission, now, created_by]
                )
                share_id = result['id'] if result else None
            else:
                await execute_sql(
                    db,
                    """
                    INSERT INTO task_shares
                    (task_id, license_key_id, shared_with_user_id, permission, created_at, created_by)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    [task_id, license_id, shared_with_user_id, permission, now, created_by]
                )
                result = await fetch_one(db, "SELECT last_insert_rowid() as id", [])
                share_id = result['id'] if result else None

        # Mark task as shared
        await execute_sql(
            db,
            "UPDATE tasks SET is_shared = 1 WHERE id = ?",
            [task_id]
        )

        await commit_db(db)

        # P4-2: Create notification for recipient
        try:
            from workers import create_task_share_notification
            await create_task_share_notification(
                license_id=license_id,
                task_id=task_id,
                task_title=task.get("title", "Unknown"),
                shared_by_user_id=created_by or "Unknown",
                shared_with_user_id=shared_with_user_id,
                permission=permission
            )
        except Exception as e:
            logger.warning(f"Failed to create task share notification: {e}")

        # Broadcast WebSocket event to recipient for instant UI update
        try:
            from services.websocket_manager import broadcast_task_shared
            import asyncio
            asyncio.create_task(
                broadcast_task_shared(
                    license_id=license_id,
                    task_id=task_id,
                    task_title=task.get("title", "Unknown"),
                    shared_by=created_by or "Unknown",
                    permission=permission
                )
            )
        except Exception as e:
            logger.warning(f"Failed to broadcast task share event: {e}")

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
    """Get tasks shared with a user"""
    # Create cache key
    cache_key = f"{license_id}:{user_id}:{permission or 'all'}"

    # Try cache first
    cached = await _get_cached_shared_tasks(cache_key)
    if cached is not None:
        logger.debug(f"Cache hit for shared tasks: {cache_key}")
        return cached

    async with get_db() as db:
        query = """
            SELECT t.*, ts.permission, ts.expires_at
            FROM tasks t
            INNER JOIN task_shares ts ON t.id = ts.task_id
            WHERE ts.shared_with_user_id = ?
            AND ts.license_key_id = ?
            AND ts.deleted_at IS NULL
            AND t.is_deleted = 0
        """
        params = [user_id, license_id]

        if permission:
            query += " AND ts.permission = ?"
            params.append(permission)

        rows = await fetch_all(db, query, params)
        result = [dict(row) for row in rows]

        # Cache the result
        await _cache_shared_tasks(cache_key, result)
        logger.debug(f"Cached shared tasks: {cache_key}")

        return result


async def remove_share(share_id: int, license_id: int, revoked_by: Optional[str] = None) -> bool:
    """Remove a share (revoke access)"""
    now = datetime.now(timezone.utc)

    async with get_db() as db:
        # Get share info before deleting
        share = await fetch_one(
            db,
            """
            SELECT ts.*, t.title as task_title
            FROM task_shares ts
            INNER JOIN tasks t ON ts.task_id = t.id
            WHERE ts.id = ? AND ts.license_key_id = ?
            """,
            [share_id, license_id]
        )

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
                logger.warning(f"Failed to create share revoked notification: {e}")

        return True


async def list_task_shares(task_id: int, license_id: int) -> List[dict]:
    """List all active shares for a task (for the owner)"""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT ts.*, u.name as shared_with_name, u.email as shared_with_email
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
