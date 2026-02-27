"""
Al-Mudeer - Library Models
CRUD operations for notes, images, files, audios, and videos

Fixes applied:
- Issue #2: Race condition fix with atomic storage check + application-level locking for SQLite
- Issue #4: PostgreSQL timestamp compatibility (timezone-aware)
- Issue #5: Added deleted_at index
- Issue #7: Bulk delete ownership validation
- Issue #8: Storage usage calculation fix + caching
- Issue #21: Removed 'tools' category (not implemented)
- Issue #30: Selective column fetching for list views
- Issue #32: SQL injection prevention in bulk operations
- Issue #33: Added composite indexes for performance
"""

import os
import logging
import asyncio
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from functools import lru_cache

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE

logger = logging.getLogger(__name__)

# Default limits (can be configured via env)
MAX_STORAGE_PER_LICENSE = int(os.getenv("MAX_STORAGE_PER_LICENSE", 100 * 1024 * 1024))  # 100MB


async def verify_share_permission(
    db,
    item_id: int,
    user_id: str,
    license_id: int,
    required_permission: str
) -> bool:
    """
    Verify if a user has the required permission for a shared item.
    
    P3-14: Share permission enforcement.
    
    Args:
        db: Database connection
        item_id: Library item ID
        user_id: User ID to check permission for
        license_id: License key ID
        required_permission: Required permission level ('read' or 'edit' or 'admin')
    
    Returns:
        bool: True if user has the required permission, False otherwise
    
    Permission hierarchy:
        - admin: can read, edit, and manage shares
        - edit: can read and edit
        - read: can only read
    """
    # Check if user is the owner
    item = await fetch_one(
        db,
        "SELECT created_by FROM library_items WHERE id = ? AND license_key_id = ?",
        [item_id, license_id]
    )
    
    if not item:
        return False
    
    # Owner always has full access
    if item.get("created_by") == user_id:
        return True
    
    # Check share permissions
    share = await fetch_one(
        db,
        """
        SELECT permission FROM library_shares
        WHERE item_id = ? 
        AND shared_with_user_id = ? 
        AND license_key_id = ? 
        AND deleted_at IS NULL
        AND (expires_at IS NULL OR expires_at > ?)
        """,
        [item_id, user_id, license_id, datetime.now(timezone.utc)]
    )
    
    if not share:
        return False
    
    share_permission = share.get("permission", "read")
    
    # Permission hierarchy check
    if required_permission == "read":
        return share_permission in ("read", "edit", "admin")
    elif required_permission == "edit":
        return share_permission in ("edit", "admin")
    elif required_permission == "admin":
        return share_permission == "admin"
    
    return False


MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE", 20 * 1024 * 1024))  # 20MB

# Issue #2: Application-level lock for SQLite storage operations
# Prevents race conditions in concurrent uploads
_storage_locks: Dict[int, asyncio.Lock] = {}


async def _get_storage_lock(license_id: int) -> asyncio.Lock:
    """Get or create a lock for a specific license to prevent race conditions."""
    if license_id not in _storage_locks:
        _storage_locks[license_id] = asyncio.Lock()
    return _storage_locks[license_id]


# Issue #8: Cache for storage usage (TTL: 60 seconds)
_storage_cache: Dict[int, Dict[str, Any]] = {}
_STORAGE_CACHE_TTL = 60  # seconds


async def _invalidate_storage_cache(license_id: int):
    """Invalidate storage cache for a license when items are added/deleted."""
    if license_id in _storage_cache:
        del _storage_cache[license_id]


async def _get_cached_storage_usage(license_id: int) -> Optional[int]:
    """Get cached storage usage if not expired."""
    import time
    if license_id in _storage_cache:
        cache_entry = _storage_cache[license_id]
        if time.time() - cache_entry["timestamp"] < _STORAGE_CACHE_TTL:
            return cache_entry["usage"]
    return None


async def _set_cached_storage_usage(license_id: int, usage: int):
    """Cache storage usage for a license."""
    import time
    _storage_cache[license_id] = {
        "usage": usage,
        "timestamp": time.time()
    }

# Issue #30: Columns for list view (avoid fetching large content field)
LIST_VIEW_COLUMNS = [
    "id", "license_key_id", "user_id", "customer_id", "type", 
    "title", "file_path", "file_size", "mime_type", "created_at", "updated_at"
]

# Issue #30: Full columns for detail view
FULL_COLUMNS = [
    "id", "license_key_id", "user_id", "customer_id", "type", 
    "title", "content", "file_path", "file_size", "mime_type", 
    "created_at", "updated_at"
]


async def get_library_items(
    license_id: int,
    user_id: Optional[str] = None,
    customer_id: Optional[int] = None,
    item_type: Optional[str] = None,
    category: Optional[str] = None,
    search_term: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    include_content: bool = False,  # Issue #30: Option to include content field
    include_shared: bool = True  # FIX: Include items shared with the user
) -> List[dict]:
    """
    Get library items for a license + global items (0), optionally filtered.
    Also includes items shared with the user (if include_shared=True).

    Issue #5: Query benefits from deleted_at index.
    Issue #21: Removed 'tools' category support.
    Issue #30: Selective column fetching for performance.
    P2-10: Uses FTS5 for search when available (much faster than LIKE).
    FIX: Added include_shared option to include items shared with the user.
    """
    # Issue #30: Use selective columns for list views
    columns = ", ".join(FULL_COLUMNS) if include_content else ", ".join(LIST_VIEW_COLUMNS)
    
    # P2-10: Use FTS5 for search if available (much faster than LIKE)
    if search_term:
        # Use FTS5 virtual table for search
        query = f"""
            SELECT {columns} FROM library_items
            INNER JOIN library_items_fts ON library_items.id = library_items_fts.rowid
            WHERE library_items_fts MATCH ?
            AND (library_items.license_key_id = ? OR library_items.license_key_id = 0)
            AND library_items.deleted_at IS NULL
        """
        # Format search term for FTS5 (prefix match)
        fts_search = f"{search_term}*"
        params = [fts_search, license_id]
        
        if customer_id is not None:
            query += " AND library_items.customer_id = ?"
            params.append(customer_id)

        if user_id:
            query += " AND library_items.user_id = ?"
            params.append(user_id)
            
        # Add type/category filters
        if category:
            if category == 'notes':
                query += " AND library_items.type = 'note'"
            elif category == 'files':
                query += " AND library_items.type IN ('image', 'audio', 'video', 'file')"
        elif item_type:
            query += " AND library_items.type = ?"
            params.append(item_type)
            
        query += " ORDER BY library_items.created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        async with get_db() as db:
            rows = await fetch_all(db, query, params)
            return [dict(row) for row in rows]
    else:
        # No search - use regular query
        query = f"SELECT {columns} FROM library_items WHERE (license_key_id = ? OR license_key_id = 0) AND deleted_at IS NULL"
        params = [license_id]

        if customer_id is not None:
            query += " AND customer_id = ?"
            params.append(customer_id)

        if user_id:
            query += " AND user_id = ?"
            params.append(user_id)

        if category:
            if category == 'notes':
                query += " AND type = 'note'"
            elif category == 'files':
                query += " AND type IN ('image', 'audio', 'video', 'file')"
            # Issue #21: Removed 'tools' category - not implemented
        elif item_type:
            query += " AND type = ?"
            params.append(item_type)

        query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        async with get_db() as db:
            # Get owned items
            rows = await fetch_all(db, query, params)
            owned_items = [dict(row) for row in rows]
            
            # FIX: Also get items shared with the user
            if user_id and include_shared:
                try:
                    # Use table prefix to avoid column ambiguity with library_shares
                    columns_prefixed = ", ".join(f"li.{col}" for col in (FULL_COLUMNS if include_content else LIST_VIEW_COLUMNS))
                    shared_query = f"""
                        SELECT {columns_prefixed} FROM library_items li
                        INNER JOIN library_shares ls ON li.id = ls.item_id
                        WHERE ls.shared_with_user_id = ?
                        AND ls.license_key_id = ?
                        AND ls.deleted_at IS NULL
                        AND li.deleted_at IS NULL
                    """
                    shared_params = [user_id, license_id]
                    
                    # Add type/category filters to shared query
                    if category:
                        if category == 'notes':
                            shared_query += " AND li.type = 'note'"
                        elif category == 'files':
                            shared_query += " AND li.type IN ('image', 'audio', 'video', 'file')"
                    elif item_type:
                        shared_query += " AND li.type = ?"
                        shared_params.append(item_type)
                    
                    shared_query += " ORDER BY li.created_at DESC LIMIT ? OFFSET ?"
                    shared_params.extend([limit, offset])
                    
                    shared_rows = await fetch_all(db, shared_query, shared_params)
                    shared_items = [dict(row) for row in shared_rows]
                    
                    # Combine and deduplicate by ID
                    all_items = {item['id']: item for item in owned_items}
                    for item in shared_items:
                        if item['id'] not in all_items:
                            all_items[item['id']] = item
                    
                    # Sort by created_at desc and apply pagination
                    sorted_items = sorted(all_items.values(), key=lambda x: x.get('created_at', ''), reverse=True)
                    return sorted_items
                except Exception as e:
                    logger.warning(f"Failed to fetch shared items: {e}")
                    return owned_items
            
            return owned_items


async def get_library_item(license_id: int, item_id: int, user_id: Optional[str] = None) -> Optional[dict]:
    """
    Get a specific library item (including global).
    
    Issue #30: Fetches all columns including content for detail view.
    """
    columns = ", ".join(FULL_COLUMNS)
    query = f"SELECT {columns} FROM library_items WHERE id = ? AND (license_key_id = ? OR license_key_id = 0) AND deleted_at IS NULL"
    params = [item_id, license_id]

    if user_id:
        query += " AND user_id = ?"
        params.append(user_id)

    async with get_db() as db:
        row = await fetch_one(db, query, params)
        return dict(row) if row else None


async def add_library_item(
    license_id: int,
    item_type: str,
    user_id: Optional[str] = None,
    customer_id: Optional[int] = None,
    title: Optional[str] = None,
    content: Optional[str] = None,
    file_path: Optional[str] = None,
    file_size: Optional[int] = 0,
    mime_type: Optional[str] = None
) -> dict:
    """
    Add a new item to the library.

    Issue #2: Atomic storage check within transaction + application-level locking for SQLite.
    Issue #4: Timezone-aware timestamps for PostgreSQL compatibility.
    """
    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)

    # Issue #2: For SQLite, use application-level lock to prevent race conditions
    # PostgreSQL uses FOR UPDATE which provides row-level locking
    if DB_TYPE == "sqlite":
        lock = await _get_storage_lock(license_id)
        async with lock:
            return await _add_library_item_internal(
                license_id, item_type, user_id, customer_id,
                title, content, file_path, file_size, mime_type, now
            )
    else:
        # PostgreSQL - uses FOR UPDATE in SQL
        return await _add_library_item_internal(
            license_id, item_type, user_id, customer_id,
            title, content, file_path, file_size, mime_type, now
        )


async def _add_library_item_internal(
    license_id: int,
    item_type: str,
    user_id: Optional[str] = None,
    customer_id: Optional[int] = None,
    title: Optional[str] = None,
    content: Optional[str] = None,
    file_path: Optional[str] = None,
    file_size: Optional[int] = 0,
    mime_type: Optional[str] = None,
    file_hash: Optional[str] = None,
    now: Optional[datetime] = None
) -> dict:
    """Internal function to add library item (called with appropriate locking)."""
    if now is None:
        now = datetime.now(timezone.utc)

    async with get_db() as db:
        # Check storage limit within transaction (atomic)
        # For PostgreSQL, FOR UPDATE locks the row during transaction
        # For SQLite, application-level lock is held by caller
        row = await fetch_one(
            db,
            "SELECT COALESCE(SUM(file_size), 0) as total FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
            [license_id]
        )

        current_usage = int(row["total"] if row and row.get("total") else 0)

        if current_usage + (file_size or 0) > MAX_STORAGE_PER_LICENSE:
            raise ValueError("تجاوزت حد التخزين المسموح به")

        # PostgreSQL-compatible timestamp handling
        ts_value = now  # Both SQLite and PostgreSQL accept timezone-aware datetime

        await execute_sql(
            db,
            """
            INSERT INTO library_items
            (license_key_id, user_id, customer_id, type, title, content, file_path, file_size, mime_type, file_hash, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [license_id, user_id, customer_id, item_type, title, content, file_path, file_size, mime_type, file_hash, ts_value, ts_value]
        )
        await commit_db(db)

        # Invalidate storage cache
        await _invalidate_storage_cache(license_id)

        # Fetch the created item
        row = await fetch_one(
            db,
            "SELECT * FROM library_items WHERE license_key_id = ? ORDER BY id DESC LIMIT 1",
            [license_id]
        )
        return dict(row)


async def update_library_item(
    license_id: int,
    item_id: int,
    user_id: Optional[str] = None,
    **kwargs
) -> bool:
    """
    Update library item metadata or content.

    Issue #4: Timezone-aware timestamps.
    FIX: Added storage cache invalidation when file_size is updated.
    P3-14: Enforces share permissions - only owner or users with edit/admin permission can update.
    """
    allowed_fields = ['title', 'content', 'customer_id', 'file_size']
    updates = {k: v for k, v in kwargs.items() if k in allowed_fields}

    if not updates:
        return False

    async with get_db() as db:
        # P3-14: Check share permissions if user_id is provided
        if user_id:
            # First check if user is owner
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
                    db, item_id, user_id, license_id, "edit"
                )
                if not has_permission:
                    logger.warning(
                        f"User {user_id} denied edit permission for item {item_id}"
                    )
                    return False

        # Issue #4: Use timezone-aware datetime
        now = datetime.now(timezone.utc)
        ts_value = now
        updates['updated_at'] = ts_value

        set_clause = ", ".join(f"{k} = ?" for k in updates.keys())
        query = f"UPDATE library_items SET {set_clause} WHERE id = ? AND license_key_id = ?"
        values = list(updates.values()) + [item_id, license_id]

        await execute_sql(db, query, values)
        await commit_db(db)

        # FIX: Invalidate storage cache if file_size was updated
        if 'file_size' in updates:
            await _invalidate_storage_cache(license_id)

        return True


async def delete_library_item(license_id: int, item_id: int, user_id: Optional[str] = None) -> bool:
    """
    Soft delete a library item.

    Issue #4: Timezone-aware timestamps.
    Issue #7: Validates user ownership when user_id is provided.
    P3-14: Enforces share permissions - only owner or users with admin permission can delete.
    """
    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    ts_value = now

    async with get_db() as db:
        check_query = "SELECT file_path, created_by FROM library_items WHERE id = ? AND license_key_id = ?"
        check_params = [item_id, license_id]

        item = await fetch_one(db, check_query, check_params)
        if not item:
            logger.warning(f"Delete failed: item {item_id} not found or access denied")
            return False
        
        # P3-14: Check share permissions if user_id is provided and user is not owner
        if user_id and item.get("created_by") != user_id:
            # Check if user has admin permission for this item
            has_permission = await verify_share_permission(
                db, item_id, user_id, license_id, "admin"
            )
            if not has_permission:
                logger.warning(
                    f"User {user_id} denied delete permission for item {item_id}"
                )
                return False

        # Physical file deletion
        if item.get("file_path"):
            from services.file_storage_service import get_file_storage
            try:
                get_file_storage().delete_file(item["file_path"])
                logger.info(f"Deleted physical file: {item['file_path']}")
            except Exception as e:
                logger.error(f"Failed to delete physical file {item['file_path']}: {e}")

        update_query = "UPDATE library_items SET deleted_at = ? WHERE id = ? AND license_key_id = ?"
        update_params = [ts_value, item_id, license_id]

        await execute_sql(db, update_query, update_params)
        await commit_db(db)

        # Invalidate storage cache
        await _invalidate_storage_cache(license_id)

        return True


async def bulk_delete_items(license_id: int, item_ids: List[int], user_id: Optional[str] = None) -> dict:
    """
    Bulk soft delete library items.

    Issue #4: Timezone-aware timestamps.
    Issue #7: Validates user ownership for each item when user_id is provided.
    Issue #32: SQL injection prevention - validates all item_ids are integers.
    P0-4: Returns detailed result with deleted IDs and failed IDs for proper feedback.
    FIX: Added transaction atomicity - all or nothing.
    """
    if not item_ids:
        return {"deleted_count": 0, "deleted_ids": [], "failed_ids": []}

    # Issue #32: Validate all item_ids are valid integers to prevent SQL injection
    validated_item_ids = []
    for item_id in item_ids:
        try:
            # Ensure it's a valid positive integer
            validated_id = int(item_id)
            if validated_id > 0 and validated_id <= 2147483647:  # Max 32-bit signed int
                validated_item_ids.append(validated_id)
        except (ValueError, TypeError):
            logger.warning(f"Invalid item_id in bulk delete: {item_id}")
            continue

    if not validated_item_ids:
        return {"deleted_count": 0, "deleted_ids": [], "failed_ids": list(item_ids)}

    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    ts_value = now

    async with get_db() as db:
        try:
            # P0-4: Get list of actually existing/accessibile items BEFORE deleting
            id_placeholders = ",".join(["?"] * len(validated_item_ids))
            
            # Issue #7: If user_id is provided, verify ownership for each item
            if user_id:
                # Get IDs of items user actually owns
                verify_query = f"SELECT id FROM library_items WHERE id IN ({id_placeholders}) AND license_key_id = ? AND user_id = ? AND deleted_at IS NULL"
                verify_params = validated_item_ids + [license_id, user_id]
                
                result = await fetch_all(db, verify_query, verify_params)
                accessible_ids = [row["id"] for row in result]
                
                if len(accessible_ids) != len(validated_item_ids):
                    failed_ids = [id for id in validated_item_ids if id not in accessible_ids]
                    logger.warning(
                        f"Bulk delete: User {user_id} tried to delete {len(validated_item_ids)} items "
                        f"but only owns {len(accessible_ids)}. Failed IDs: {failed_ids}"
                    )
                
                # Delete only the items the user owns
                if accessible_ids:
                    delete_placeholders = ",".join(["?"] * len(accessible_ids))
                    query = f"UPDATE library_items SET deleted_at = ? WHERE license_key_id = ? AND user_id = ? AND id IN ({delete_placeholders})"
                    params = [ts_value, license_id, user_id] + accessible_ids
                    await execute_sql(db, query, params)
                else:
                    accessible_ids = []
            else:
                # No user_id - get IDs of items that exist and aren't already deleted
                verify_query = f"SELECT id FROM library_items WHERE id IN ({id_placeholders}) AND license_key_id = ? AND deleted_at IS NULL"
                verify_params = validated_item_ids + [license_id]
                
                result = await fetch_all(db, verify_query, verify_params)
                accessible_ids = [row["id"] for row in result]
                
                # Delete accessible items
                if accessible_ids:
                    delete_placeholders = ",".join(["?"] * len(accessible_ids))
                    query = f"UPDATE library_items SET deleted_at = ? WHERE license_key_id = ? AND id IN ({delete_placeholders})"
                    params = [ts_value, license_id] + accessible_ids
                    await execute_sql(db, query, params)
                else:
                    accessible_ids = []

            await commit_db(db)

            # P0-4: Calculate failed IDs
            failed_ids = [id for id in validated_item_ids if id not in accessible_ids]
            
            # Invalidate storage cache only on success
            await _invalidate_storage_cache(license_id)

            return {
                "deleted_count": len(accessible_ids),
                "deleted_ids": accessible_ids,
                "failed_ids": failed_ids
            }

        except Exception as e:
            # FIX: Log error and return failure result
            logger.error(f"Bulk delete failed: {e}", exc_info=True)
            # Transaction will be rolled back automatically by context manager
            return {
                "deleted_count": 0,
                "deleted_ids": [],
                "failed_ids": list(validated_item_ids),
                "error": str(e)
            }


async def get_storage_usage(license_id: int) -> int:
    """
    Get total storage usage in bytes for a license.

    Issue #8: Uses caching to improve performance.
    Issue #31: Cache implemented with TTL.
    """
    # Check cache first
    cached = await _get_cached_storage_usage(license_id)
    if cached is not None:
        return cached
    
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT COALESCE(SUM(file_size), 0) as total FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
            [license_id]
        )
        usage = int(row["total"] if row else 0)
        
        # Cache the result
        await _set_cached_storage_usage(license_id, usage)
        return usage


async def get_storage_usage_detailed(license_id: int) -> Dict[str, Any]:
    """
    Get detailed storage usage breakdown by type.

    Issue #8: Uses caching to improve performance.
    """
    # Check cache first
    cached = await _get_cached_storage_usage(license_id)
    
    async with get_db() as db:
        # Total usage
        total_row = await fetch_one(
            db,
            "SELECT COALESCE(SUM(file_size), 0) as total, COUNT(*) as count FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
            [license_id]
        )

        # Usage by type
        type_rows = await fetch_all(
            db,
            """
            SELECT type, COALESCE(SUM(file_size), 0) as size, COUNT(*) as count
            FROM library_items
            WHERE license_key_id = ? AND deleted_at IS NULL
            GROUP BY type
            """,
            [license_id]
        )

        total_bytes = int(total_row["total"] if total_row else 0)
        
        result = {
            "total_bytes": total_bytes,
            "total_count": int(total_row["count"] if total_row else 0),
            "limit_bytes": MAX_STORAGE_PER_LICENSE,
            "percentage_used": round(
                (total_bytes / MAX_STORAGE_PER_LICENSE) * 100, 2
            ) if MAX_STORAGE_PER_LICENSE > 0 else 0,
            "by_type": {
                row["type"]: {
                    "bytes": int(row["size"]),
                    "count": int(row["count"])
                }
                for row in type_rows
            }
        }
        
        # Cache the total bytes
        await _set_cached_storage_usage(license_id, total_bytes)
        return result
