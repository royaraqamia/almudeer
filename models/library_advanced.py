"""
Al-Mudeer - Library Advanced Features Models
P3-13: Versioning
P3-14: Sharing
P3-15: Analytics
"""

import os
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any
from functools import lru_cache
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db

logger = logging.getLogger(__name__)

# P6-2: LRU Cache for shared items (max 100 entries, 5 minute TTL)
_shared_items_cache: Dict[str, Dict[str, Any]] = {}
_SHARED_ITEMS_CACHE_TTL = 300  # 5 minutes
_MAX_CACHE_SIZE = 100  # Maximum number of cache entries to prevent memory leak


async def _get_cached_shared_items(cache_key: str) -> Optional[List[dict]]:
    """Get cached shared items if not expired"""
    if cache_key in _shared_items_cache:
        cache_entry = _shared_items_cache[cache_key]
        if datetime.now(timezone.utc).timestamp() - cache_entry["timestamp"] < _SHARED_ITEMS_CACHE_TTL:
            return cache_entry["data"]
    return None


async def _cache_shared_items(cache_key: str, data: List[dict]):
    """Cache shared items with size limit to prevent memory leak"""
    # FIX: Enforce maximum cache size - evict oldest entries if at limit
    if len(_shared_items_cache) >= _MAX_CACHE_SIZE:
        # Find and remove oldest entries (simple eviction strategy)
        oldest_key = None
        oldest_timestamp = float('inf')
        for key, entry in _shared_items_cache.items():
            if entry["timestamp"] < oldest_timestamp:
                oldest_timestamp = entry["timestamp"]
                oldest_key = key
        if oldest_key:
            del _shared_items_cache[oldest_key]
    
    _shared_items_cache[cache_key] = {
        "data": data,
        "timestamp": datetime.now(timezone.utc).timestamp()
    }


async def _invalidate_shared_items_cache(license_id: int, user_id: Optional[str] = None):
    """Invalidate shared items cache for a license or user"""
    keys_to_remove = [
        key for key in _shared_items_cache.keys()
        if key.startswith(f"{license_id}:") and (user_id is None or user_id in key)
    ]
    for key in keys_to_remove:
        del _shared_items_cache[key]


# ============================================================================
# P3-13: VERSIONING
# ============================================================================

async def create_item_version(
    item_id: int,
    license_id: int,
    title: str,
    content: Optional[str] = None,
    created_by: Optional[str] = None,
    change_summary: Optional[str] = None
) -> dict:
    """Create a new version of a library item"""
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Get current version number
        current = await fetch_one(
            db,
            "SELECT version FROM library_items WHERE id = ? AND license_key_id = ?",
            [item_id, license_id]
        )
        
        if not current:
            raise ValueError("Item not found")
        
        new_version = (current["version"] or 1) + 1
        
        # Create version record
        await execute_sql(
            db,
            """
            INSERT INTO library_item_versions
            (item_id, license_key_id, version, title, content, created_at, created_by, change_summary)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [item_id, license_id, new_version, title, content, now, created_by, change_summary]
        )
        
        # Update item version
        await execute_sql(
            db,
            "UPDATE library_items SET version = ?, updated_at = ? WHERE id = ? AND license_key_id = ?",
            [new_version, now, item_id, license_id]
        )
        
        await commit_db(db)
        
        # Return version info
        return {
            "version": new_version,
            "created_at": now,
            "created_by": created_by,
            "change_summary": change_summary
        }


async def get_item_versions(item_id: int, license_id: int, limit: int = 10) -> List[dict]:
    """Get version history for an item"""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT * FROM library_item_versions
            WHERE item_id = ? AND license_key_id = ?
            ORDER BY version DESC
            LIMIT ?
            """,
            [item_id, license_id, limit]
        )
        return [dict(row) for row in rows]


async def restore_version(
    item_id: int,
    version_id: int,
    license_id: int,
    user_id: Optional[str] = None
) -> bool:
    """Restore an item to a previous version"""
    from models.library import verify_share_permission  # Local import to avoid circular import
    
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # FIX: Verify user has permission to restore (owner or admin share)
        if user_id:
            # Check if user owns the item
            owner_check = await fetch_one(
                db,
                "SELECT created_by FROM library_items WHERE id = ? AND license_key_id = ?",
                [item_id, license_id]
            )
            
            if not owner_check:
                return False
            
            # If not owner, check share permission
            if owner_check.get("created_by") != user_id:
                has_permission = await verify_share_permission(
                    db, item_id, user_id, license_id, "admin"
                )
                if not has_permission:
                    logger.warning(f"User {user_id} denied restore permission for item {item_id}")
                    return False
        
        # Get version
        version = await fetch_one(
            db,
            "SELECT * FROM library_item_versions WHERE id = ? AND license_key_id = ?",
            [version_id, license_id]
        )
        
        if not version:
            return False
        
        # Restore item
        await execute_sql(
            db,
            """
            UPDATE library_items
            SET title = ?, content = ?, version = version + 1, updated_at = ?, updated_by = ?
            WHERE id = ? AND license_key_id = ?
            """,
            [version["title"], version["content"], now, user_id, item_id, license_id]
        )
        
        await commit_db(db)
        return True


# ============================================================================
# P3-14: SHARING
# ============================================================================

async def share_item(
    item_id: int,
    license_id: int,
    shared_with_user_id: str,
    permission: str = 'read',
    created_by: Optional[str] = None,
    expires_in_days: Optional[int] = None
) -> dict:
    """Share a library item with another user"""
    now = datetime.now(timezone.utc)
    expires_at = None

    if expires_in_days:
        expires_at = now + timedelta(days=expires_in_days)

    async with get_db() as db:
        # Verify item exists
        item = await fetch_one(
            db,
            "SELECT id, title FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license_id]
        )

        if not item:
            raise ValueError("Item not found")

        # Create share
        await execute_sql(
            db,
            """
            INSERT INTO library_shares
            (item_id, license_key_id, shared_with_user_id, permission, created_at, created_by, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [item_id, license_id, shared_with_user_id, permission, now, created_by, expires_at]
        )

        # Mark item as shared
        await execute_sql(
            db,
            "UPDATE library_items SET is_shared = 1 WHERE id = ?",
            [item_id]
        )

        await commit_db(db)

        # P3-14: Create notification for recipient
        try:
            from workers import create_share_notification
            await create_share_notification(
                license_id=license_id,
                item_id=item_id,
                item_title=item.get("title", "Unknown"),
                shared_by_user_id=created_by or "Unknown",
                shared_with_user_id=shared_with_user_id,
                permission=permission
            )
        except Exception as e:
            logger.warning(f"Failed to create share notification: {e}")

        return {
            "item_id": item_id,
            "shared_with": shared_with_user_id,
            "permission": permission,
            "expires_at": expires_at
        }


async def get_shared_items(
    license_id: int,
    user_id: str,
    permission: Optional[str] = None
) -> List[dict]:
    """Get items shared with a user
    
    P6-2: Implements caching for better performance.
    """
    # Create cache key
    cache_key = f"{license_id}:{user_id}:{permission or 'all'}"
    
    # Try cache first
    cached = await _get_cached_shared_items(cache_key)
    if cached is not None:
        logger.debug(f"Cache hit for shared items: {cache_key}")
        return cached
    
    async with get_db() as db:
        query = """
            SELECT li.*, ls.permission, ls.expires_at
            FROM library_items li
            INNER JOIN library_shares ls ON li.id = ls.item_id
            WHERE ls.shared_with_user_id = ?
            AND ls.license_key_id = ?
            AND ls.deleted_at IS NULL
            AND li.deleted_at IS NULL
        """
        params = [user_id, license_id]

        if permission:
            query += " AND ls.permission = ?"
            params.append(permission)

        # Check expiration
        query += " AND (ls.expires_at IS NULL OR ls.expires_at > ?)"
        params.append(datetime.now(timezone.utc))

        rows = await fetch_all(db, query, params)
        result = [dict(row) for row in rows]
        
        # Cache the result
        await _cache_shared_items(cache_key, result)
        logger.debug(f"Cached shared items: {cache_key}")
        
        return result


async def remove_share(share_id: int, license_id: int, revoked_by: Optional[str] = None) -> bool:
    """Remove a share (revoke access)"""
    now = datetime.now(timezone.utc)

    async with get_db() as db:
        # Get share info before deleting
        share = await fetch_one(
            db,
            """
            SELECT ls.*, li.title as item_title
            FROM library_shares ls
            INNER JOIN library_items li ON ls.item_id = li.id
            WHERE ls.id = ? AND ls.license_key_id = ?
            """,
            [share_id, license_id]
        )
        
        # Soft delete
        await execute_sql(
            db,
            "UPDATE library_shares SET deleted_at = ? WHERE id = ? AND license_key_id = ?",
            [now, share_id, license_id]
        )

        await commit_db(db)
        
        # P6-2: Invalidate cache for the affected user
        if share:
            await _invalidate_shared_items_cache(license_id, share["shared_with_user_id"])
        
        # P3-14: Create notification for user whose access was revoked
        if share:
            try:
                from workers import create_share_revoked_notification
                await create_share_revoked_notification(
                    license_id=license_id,
                    item_id=share["item_id"],
                    item_title=share.get("item_title", "Unknown"),
                    revoked_by_user_id=revoked_by or "Unknown",
                    user_id=share["shared_with_user_id"]
                )
            except Exception as e:
                logger.warning(f"Failed to create share revoked notification: {e}")
        
        return True


# ============================================================================
# P3-15: ANALYTICS
# ============================================================================

async def track_item_access(
    item_id: int,
    license_id: int,
    user_id: Optional[str],
    action: str,
    client_ip: Optional[str] = None,
    user_agent: Optional[str] = None,
    metadata: Optional[Dict] = None
):
    """Track access to a library item"""
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Log analytics
        await execute_sql(
            db,
            """
            INSERT INTO library_analytics
            (item_id, license_key_id, user_id, action, timestamp, client_ip, user_agent, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [item_id, license_id, user_id, action, now, client_ip, user_agent,
             json.dumps(metadata) if metadata else None]
        )
        
        # Update item counters
        if action == 'view':
            await execute_sql(
                db,
                """
                UPDATE library_items
                SET access_count = COALESCE(access_count, 0) + 1, last_accessed_at = ?
                WHERE id = ? AND license_key_id = ?
                """,
                [now, item_id, license_id]
            )
        elif action == 'download':
            await execute_sql(
                db,
                """
                UPDATE library_items
                SET download_count = COALESCE(download_count, 0) + 1,
                    access_count = COALESCE(access_count, 0) + 1,
                    last_accessed_at = ?
                WHERE id = ? AND license_key_id = ?
                """,
                [now, item_id, license_id]
            )
        
        await commit_db(db)


async def get_item_analytics(
    item_id: int,
    license_id: int,
    days: int = 30
) -> Dict[str, Any]:
    """Get analytics for a specific item"""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    
    async with get_db() as db:
        # Get item info
        item = await fetch_one(
            db,
            "SELECT access_count, download_count, last_accessed_at FROM library_items WHERE id = ? AND license_key_id = ?",
            [item_id, license_id]
        )
        
        if not item:
            return {}
        
        # Get action breakdown
        actions = await fetch_all(
            db,
            """
            SELECT action, COUNT(*) as count
            FROM library_analytics
            WHERE item_id = ? AND license_key_id = ? AND timestamp >= ?
            GROUP BY action
            """,
            [item_id, license_id, cutoff]
        )
        
        # Get recent activity
        recent = await fetch_all(
            db,
            """
            SELECT * FROM library_analytics
            WHERE item_id = ? AND license_key_id = ? AND timestamp >= ?
            ORDER BY timestamp DESC
            LIMIT 50
            """,
            [item_id, license_id, cutoff]
        )
        
        return {
            "item_id": item_id,
            "total_accesses": item.get("access_count", 0),
            "total_downloads": item.get("download_count", 0),
            "last_accessed": item.get("last_accessed_at"),
            "actions_last_30_days": {row["action"]: row["count"] for row in actions},
            "recent_activity": [dict(row) for row in recent]
        }


async def get_library_statistics(license_id: int, days: int = 30) -> Dict[str, Any]:
    """Get overall library statistics"""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    
    async with get_db() as db:
        # Total items
        total = await fetch_one(
            db,
            "SELECT COUNT(*) as count FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
            [license_id]
        )
        
        # Most accessed items
        popular = await fetch_all(
            db,
            """
            SELECT id, title, type, access_count, download_count
            FROM library_items
            WHERE license_key_id = ? AND deleted_at IS NULL
            ORDER BY access_count DESC
            LIMIT 10
            """,
            [license_id]
        )
        
        # Recent activity summary
        activity = await fetch_all(
            db,
            """
            SELECT action, COUNT(*) as count
            FROM library_analytics
            WHERE license_key_id = ? AND timestamp >= ?
            GROUP BY action
            """,
            [license_id, cutoff]
        )
        
        return {
            "total_items": total["count"] if total else 0,
            "most_accessed": [dict(row) for row in popular],
            "activity_summary": {row["action"]: row["count"] for row in activity},
            "period_days": days
        }
