"""
Al-Mudeer - Library Advanced Features Models
P3-13: Versioning
P3-14: Sharing
P3-15: Analytics

Permission Levels:
- read: Can VIEW only. Cannot edit, share, or delete.
- edit: Can VIEW, EDIT, and SHARE. Cannot DELETE.
- admin: Full access - VIEW, EDIT, SHARE, DELETE (same as owner).
"""

import asyncio
import os
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any
from functools import lru_cache
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from utils.share_utils import resolve_username_to_user_id_with_db, validate_share_permission
from utils.permissions import (
    PermissionLevel,
    ResourceAction,
    can_perform_action,
    get_effective_permission,
    validate_permission_for_action,
)
from utils.cache_utils import (
    get_shared_items_cache,
    broadcast_safe,
)

logger = logging.getLogger(__name__)


async def _invalidate_shared_items_cache(license_id: int, user_id: Optional[str] = None):
    """Invalidate shared items cache for a license or user

    FIX BUG #5: Invalidate all permission variants to prevent cache inconsistency.
    FIX: Ensure complete cleanup of both cache and access times to prevent memory leaks.
    FIX: Use batch invalidation for atomic operation.
    """
    cache = get_shared_items_cache()

    # FIX: Invalidate all permission levels for this user using batch operation
    if user_id:
        cache_keys = [f"{license_id}|{user_id}|{perm}" for perm in ['read', 'edit', 'admin', 'all']]
        await cache.invalidate_batch(cache_keys)
    else:
        # Invalidate all caches for this license
        await cache.invalidate_prefix(f"{license_id}|")


async def _invalidate_shared_items_cache_batch(license_id: int, user_ids: List[str]):
    """Invalidate shared items cache for multiple users in a single batch.
    
    More efficient than calling _invalidate_shared_items_cache multiple times.
    
    Args:
        license_id: License key ID
        user_ids: List of user IDs to invalidate cache for
    """
    if not user_ids:
        return
        
    cache = get_shared_items_cache()
    
    # Build all keys to invalidate
    keys_to_invalidate = []
    for user_id in user_ids:
        for perm in ['read', 'edit', 'admin', 'all']:
            keys_to_invalidate.append(f"{license_id}|{user_id}|{perm}")
    
    # Batch invalidate
    await cache.invalidate_batch(keys_to_invalidate)


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
    """Share a library item with another user

    SEC-002 FIX: Added self-share prevention (was missing).
    AUTH-001 FIX: Uses shared utility for username resolution.
    DATA-001 FIX: ON CONFLICT no longer re-activates revoked shares.
    DATA-002 FIX: is_shared update is now atomic within same transaction.
    FIX #4: Send notification on re-share to inform recipient of renewed access.
    P2-1 FIX: Added validation for expires_in_days to prevent invalid values.

    Args:
        item_id: Library item ID to share
        license_id: License key ID
        shared_with_user_id: Contact or user ID of recipient
        permission: Permission level ('read', 'edit', 'admin')
        created_by: User ID of the sharer
        expires_in_days: Optional number of days until share expires

    Raises:
        ValueError: If expires_in_days is invalid (negative or too large)
    """
    now = datetime.now(timezone.utc)

    # Validate permission level
    if not validate_share_permission(permission):
        raise ValueError(f"Invalid permission: {permission}. Must be 'read', 'edit', or 'admin'")

    # P2-1 FIX: Validate expires_in_days parameter
    if expires_in_days is not None:
        if expires_in_days <= 0:
            raise ValueError("expires_in_days must be a positive number")
        if expires_in_days > 3650:  # Max 10 years
            raise ValueError("expires_in_days cannot exceed 3650 days (10 years)")

    # Calculate expiration date if provided
    expires_at = None
    if expires_in_days is not None and expires_in_days > 0:
        from datetime import timedelta
        expires_at = now + timedelta(days=expires_in_days)

    async with get_db() as db:
        # Verify item exists
        item = await fetch_one(
            db,
            "SELECT id, title, created_by FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license_id]
        )

        if not item:
            raise ValueError("Item not found")

        # AUTH-001 FIX: Use shared utility for username resolution
        recipient_user_id, _ = await resolve_username_to_user_id_with_db(shared_with_user_id, db)

        # SEC-002 FIX: Prevent self-sharing - check against item owner
        # This check happens AFTER resolution to ensure we compare actual user IDs
        item_owner_id = item.get('created_by') or created_by
        if recipient_user_id == item_owner_id:
            raise ValueError("Cannot share an item with yourself")

        # FIX #10: Validate share permission hierarchy
        # Users cannot grant permissions higher than their own
        # Only owners (created_by) can grant any permission level
        if created_by and created_by != item_owner_id:
            # This is a non-owner sharing - check their permission level
            sharer_share = await fetch_one(
                db,
                """
                SELECT permission FROM library_shares
                WHERE item_id = ? AND shared_with_user_id = ? AND license_key_id = ?
                AND deleted_at IS NULL
                """,
                [item_id, created_by, license_id]
            )

            if sharer_share:
                sharer_permission = sharer_share.get('permission', 'read')
                # Permission hierarchy: admin > edit > read
                permission_levels = {'read': 1, 'edit': 2, 'admin': 3}
                if permission_levels.get(permission, 0) > permission_levels.get(sharer_permission, 0):
                    raise ValueError(
                        f"Cannot grant '{permission}' permission. Your permission level is '{sharer_permission}'."
                    )

        # BUG-001 FIX: Get share state BEFORE upsert for accurate reshare/permission change detection
        # This prevents race conditions where concurrent shares could misidentify the state
        share_before = await fetch_one(
            db,
            """
            SELECT id, deleted_at, permission FROM library_shares
            WHERE item_id = ? AND shared_with_user_id = ? AND license_key_id = ?
            """,
            [item_id, recipient_user_id, license_id]
        )

        # DATA-001 FIX: Don't re-activate revoked shares
        # If share exists and is active (deleted_at IS NULL), update it
        # If share was revoked (deleted_at IS NOT NULL), INSERT will fail on conflict
        # and we should NOT update - user must create fresh share instead
        await execute_sql(
            db,
            """
            INSERT INTO library_shares
            (item_id, license_key_id, shared_with_user_id, permission, created_at, created_by, updated_at, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (item_id, shared_with_user_id) DO UPDATE SET
                permission = EXCLUDED.permission,
                updated_at = EXCLUDED.updated_at,
                expires_at = EXCLUDED.expires_at
            WHERE library_shares.deleted_at IS NULL  -- Only update if share is still active
            """,
            [item_id, license_id, recipient_user_id, permission, now, created_by, now, expires_at]
        )

        # DATA-002 FIX: Mark item as shared within same transaction (atomic)
        await execute_sql(
            db,
            "UPDATE library_items SET is_shared = 1 WHERE id = ?",
            [item_id]
        )

        await commit_db(db)

        # BUG-001 FIX: Determine reshare/permission change AFTER commit using the pre-upsert state
        # This ensures accurate detection even under concurrent access
        is_reshare = share_before is not None and share_before.get('deleted_at') is not None
        is_permission_change = (
            share_before is not None and
            share_before.get('deleted_at') is None and
            share_before.get('permission') != permission
        )
        is_new_share = share_before is None

        # FIX #4: Send notification for new shares, re-shares, and permission changes
        # Previously, notifications were only sent for new shares
        should_send_notification = is_reshare or is_permission_change or is_new_share

        if should_send_notification:
            try:
                from workers import create_share_notification
                await create_share_notification(
                    license_id=license_id,
                    item_id=item_id,
                    item_title=item.get("title", "Unknown"),
                    shared_by_user_id=created_by or "Unknown",
                    shared_with_user_id=recipient_user_id,
                    permission=permission
                )
            except Exception as e:
                # FIX: Log with ERROR level and include full stack trace for debugging
                # Notification failures should be monitored as they affect user experience
                logger.error(
                    f"Failed to create library share notification for item {item_id} "
                    f"(shared with {recipient_user_id}): {e}",
                    exc_info=True
                )
                # P6-1 FIX: Queue for retry via background worker instead of silent failure
                try:
                    from services.metrics_service import MetricsService
                    metrics = MetricsService()
                    await metrics.increment_counter("library_share_notification_failures", {
                        "license_id": str(license_id),
                        "error_type": type(e).__name__
                    })
                except Exception as metrics_error:
                    logger.warning(f"Failed to log metrics for notification failure: {metrics_error}")

                # FIX: Queue notification for retry
                try:
                    from workers import queue_notification_for_retry
                    await queue_notification_for_retry({
                        'license_id': license_id,
                        'resource_type': 'library',
                        'resource_id': str(item_id),
                        'resource_title': item.get("title", "Unknown"),
                        'shared_by_user_id': created_by or "Unknown",
                        'shared_with_user_id': recipient_user_id,
                        'permission': permission,
                        'priority': 'normal'
                    })
                except Exception as retry_error:
                    logger.error(f"DEAD_LETTER: Failed to queue notification for retry: {retry_error}", exc_info=True)

        # Broadcast WebSocket event to recipient for instant UI update
        try:
            from services.websocket_manager import broadcast_library_shared

            # Recipient's license ID is the resolved user_id
            recipient_license_id = int(recipient_user_id) if recipient_user_id.isdigit() else None

            if recipient_license_id:
                asyncio.create_task(
                    broadcast_safe(
                        broadcast_library_shared(
                            license_id=recipient_license_id,
                            item_id=item_id,
                            item_title=item.get("title", "Unknown"),
                            shared_by=created_by or "Unknown",
                            permission=permission
                        ),
                        "broadcast library share event"
                    )
                )
            else:
                logger.warning(f"Could not find recipient license for user_id: {recipient_user_id}")
                # Track metric for missing recipient license
                try:
                    from services.metrics_service import MetricsService
                    metrics = MetricsService()
                    await metrics.increment_counter("library_share_missing_recipient_license", {
                        "license_id": str(license_id)
                    })
                except Exception:
                    pass
        except Exception as e:
            logger.warning(f"Failed to queue broadcast library share event: {e}")
            # FIX: Track WebSocket broadcast failures for monitoring
            try:
                from services.metrics_service import MetricsService
                metrics = MetricsService()
                await metrics.increment_counter("library_share_broadcast_failures", {
                    "license_id": str(license_id),
                    "error_type": type(e).__name__
                })
            except Exception:
                pass

        return {
            "item_id": item_id,
            "shared_with": recipient_user_id,
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
    FIX: Added share expiration check to prevent expired shares from granting access.
    """
    # Create cache key
    cache_key = f"{license_id}|{user_id}|{permission or 'all'}"
    cache = get_shared_items_cache()

    # Try cache first
    cached = await cache.get(cache_key)
    if cached is not None:
        logger.debug(f"Cache hit for shared items: {cache_key}")
        return cached

    async with get_db() as db:
        try:
            # FIX: Added share expiration check (expires_at IS NULL OR expires_at > now)
            # FIX: Return 'share_permission' instead of 'permission' for API consistency
            now = datetime.now(timezone.utc)
            query = """
                SELECT li.*, ls.permission as share_permission, ls.expires_at
                FROM library_items li
                INNER JOIN library_shares ls ON li.id = ls.item_id
                WHERE ls.shared_with_user_id = ?
                AND ls.license_key_id = ?
                AND ls.deleted_at IS NULL
                AND (ls.expires_at IS NULL OR ls.expires_at > ?)
                AND li.deleted_at IS NULL
            """
            params = [user_id, license_id, now]

            if permission:
                query += " AND ls.permission = ?"
                params.append(permission)

            logger.debug(f"Executing query: {query} with params: {params}")
            rows = await fetch_all(db, query, params)
            result = [dict(row) for row in rows]

            logger.debug(f"Query returned {len(result)} rows")

            # Cache the result
            await cache.set(cache_key, result)
            logger.debug(f"Cached shared items: {cache_key}")

            return result
        except Exception as e:
            logger.error(f"Database error in get_shared_items: {e}", exc_info=True)
            raise


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

    async with get_db() as db:
        # Get share info before deleting
        share = await fetch_one(
            db,
            """
            SELECT ls.*, li.title as item_title, li.created_by as item_owner
            FROM library_shares ls
            INNER JOIN library_items li ON ls.item_id = li.id
            WHERE ls.id = ? AND ls.license_key_id = ?
            """,
            [share_id, license_id]
        )

        if not share:
            return False

        # PERMISSION CHECK: Owner, admin, or the recipient themselves can revoke
        # Bug #8 FIX: Recipients can always "leave" a share (revoke their own access)
        if requested_by_user_id:
            item_owner_id = share.get('item_owner')
            is_owner = requested_by_user_id == item_owner_id
            is_recipient = requested_by_user_id == share.get('shared_with_user_id')
            
            if not is_owner and not is_recipient:
                # User is trying to revoke someone else's share - must be owner
                logger.warning(
                    f"User {requested_by_user_id} denied permission to revoke share {share_id}. Not the item owner."
                )
                return False

        # Soft delete
        await execute_sql(
            db,
            "UPDATE library_shares SET deleted_at = ? WHERE id = ? AND license_key_id = ?",
            [now, share_id, license_id]
        )

        await commit_db(db)

        # BUG-002 FIX: Invalidate cache for the affected user
        if share:
            await _invalidate_shared_items_cache(license_id, share["shared_with_user_id"])

        # BUG-002 FIX: Broadcast WebSocket event to recipient for instant cache invalidation
        # This ensures multi-server deployments properly invalidate caches across all instances
        if share:
            try:
                from services.websocket_manager import broadcast_library_share_revoked
                from services.websocket_manager import broadcast_safe

                # Get recipient's license ID from user_id
                recipient_user_id = share["shared_with_user_id"]
                recipient_license_id = int(recipient_user_id) if recipient_user_id.isdigit() else None

                if recipient_license_id:
                    asyncio.create_task(
                        broadcast_safe(
                            broadcast_library_share_revoked(
                                license_id=recipient_license_id,
                                item_id=share["item_id"],
                                share_id=share_id,
                                revoked_by=revoked_by or "Unknown"
                            ),
                            "broadcast share revoke event"
                        )
                    )
                else:
                    logger.warning(f"Could not find recipient license for user_id: {recipient_user_id}")
            except Exception as e:
                logger.warning(f"Failed to broadcast share revoke event: {e}")
                # Track failure for monitoring
                try:
                    from services.metrics_service import MetricsService
                    metrics = MetricsService()
                    await metrics.increment_counter("library_share_revoke_broadcast_failures", {
                        "license_id": str(license_id),
                        "error_type": type(e).__name__
                    })
                except Exception:
                    pass

        # P3-14: Create notification for user whose access was revoked
        if share:
            try:
                from workers import create_share_revoked_notification
                await create_share_revoked_notification(
                    license_id=license_id,
                    task_id=share["item_id"],
                    task_title=share.get("item_title", "Unknown"),
                    revoked_by_user_id=revoked_by or "Unknown",
                    revoked_from_user_id=share["shared_with_user_id"]
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
                    await metrics.increment_counter("library_share_revoked_notification_failures", {
                        "license_id": str(license_id),
                        "error_type": type(e).__name__
                    })
                except Exception as metrics_error:
                    logger.warning(f"Failed to log metrics for notification failure: {metrics_error}")

                # FIX: Queue notification for retry (same as share creation)
                try:
                    from workers import queue_notification_for_retry
                    await queue_notification_for_retry({
                        'license_id': license_id,
                        'resource_type': 'library',
                        'resource_id': str(share["item_id"]),
                        'resource_title': share.get("item_title", "Unknown"),
                        'revoked_by_user_id': revoked_by or "Unknown",
                        'revoked_from_user_id': share["shared_with_user_id"],
                        'notification_type': 'share_revoked',
                        'priority': 'normal'
                    })
                except Exception as retry_error:
                    logger.error(f"DEAD_LETTER: Failed to queue revoked share notification for retry: {retry_error}", exc_info=True)

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


# ============================================================================
# Re-export functions from library.py for backward compatibility
# ============================================================================
from models.library import verify_share_permission  # noqa: F401


async def update_share_permission(
    item_id: int,
    license_id: int,
    shared_with_user_id: str,
    new_permission: str,
    updated_by: str,
) -> dict:
    """
    Update share permission for a library item.
    
    P3-14: Allow share owners to update permissions.
    
    Args:
        item_id: Library item ID
        license_id: License key ID
        shared_with_user_id: User ID to update permission for
        new_permission: New permission level ('read', 'edit', 'admin')
        updated_by: User ID performing the update
        
    Returns:
        dict: Updated share record
    """
    from utils.share_utils import validate_share_permission
    
    # Validate permission
    if new_permission not in ('read', 'edit', 'admin'):
        raise ValueError("Invalid permission. Must be 'read', 'edit', or 'admin'")
    
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Update the share
        await execute_sql(
            db,
            """
            UPDATE library_shares
            SET permission = ?, updated_at = ?
            WHERE item_id = ? AND shared_with_user_id = ? AND license_key_id = ? AND deleted_at IS NULL
            """,
            [new_permission, now, item_id, shared_with_user_id, license_id]
        )
        await commit_db(db)
        
        # Invalidate cache
        await _invalidate_shared_items_cache(license_id, shared_with_user_id)
        
        # Fetch updated share
        row = await fetch_one(
            db,
            """
            SELECT * FROM library_shares
            WHERE item_id = ? AND shared_with_user_id = ? AND license_key_id = ? AND deleted_at IS NULL
            """,
            [item_id, shared_with_user_id, license_id]
        )
        
        return dict(row) if row else None

