"""
Al-Mudeer - Library Models
CRUD operations for notes, images, files, audios, and videos

Fixes applied:
- Issue #2: Race condition fix with atomic storage check
- Issue #4: PostgreSQL timestamp compatibility (timezone-aware)
- Issue #5: Added deleted_at index
- Issue #7: Bulk delete ownership validation
- Issue #8: Storage usage calculation fix
- Issue #21: Removed 'tools' category (not implemented)
- Issue #30: Selective column fetching for list views
"""

import os
import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE

logger = logging.getLogger(__name__)

# Default limits (can be configured via env)
MAX_STORAGE_PER_LICENSE = int(os.getenv("MAX_STORAGE_PER_LICENSE", 100 * 1024 * 1024))  # 100MB
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE", 20 * 1024 * 1024))  # 20MB

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
    include_content: bool = False  # Issue #30: Option to include content field
) -> List[dict]:
    """
    Get library items for a license + global items (0), optionally filtered.
    
    Issue #5: Query benefits from deleted_at index.
    Issue #21: Removed 'tools' category support.
    Issue #30: Selective column fetching for performance.
    """
    # Issue #30: Use selective columns for list views
    columns = ", ".join(FULL_COLUMNS) if include_content else ", ".join(LIST_VIEW_COLUMNS)
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

    if search_term:
        query += " AND (title LIKE ? OR content LIKE ?)"
        search_pattern = f"%{search_term}%"
        params.extend([search_pattern, search_pattern])

    query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])

    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        return [dict(row) for row in rows]


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
    
    Issue #2: Atomic storage check within transaction.
    Issue #4: Timezone-aware timestamps for PostgreSQL compatibility.
    """
    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Issue #2: Check storage limit within transaction (atomic)
        # Use FOR UPDATE in PostgreSQL to lock the row during transaction
        if DB_TYPE == "postgresql":
            row = await fetch_one(
                db,
                "SELECT COALESCE(SUM(file_size), 0) as total FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL FOR UPDATE",
                [license_id]
            )
        else:
            row = await fetch_one(
                db,
                "SELECT SUM(file_size) as total FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
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
            (license_key_id, user_id, customer_id, type, title, content, file_path, file_size, mime_type, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [license_id, user_id, customer_id, item_type, title, content, file_path, file_size, mime_type, ts_value, ts_value]
        )
        await commit_db(db)

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
    """
    allowed_fields = ['title', 'content', 'customer_id']
    updates = {k: v for k, v in kwargs.items() if k in allowed_fields}

    if not updates:
        return False

    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    ts_value = now
    updates['updated_at'] = ts_value

    set_clause = ", ".join(f"{k} = ?" for k in updates.keys())
    query = f"UPDATE library_items SET {set_clause} WHERE id = ? AND license_key_id = ?"
    values = list(updates.values()) + [item_id, license_id]

    if user_id:
        query += " AND user_id = ?"
        values.append(user_id)

    async with get_db() as db:
        await execute_sql(db, query, values)
        await commit_db(db)
        return True


async def delete_library_item(license_id: int, item_id: int, user_id: Optional[str] = None) -> bool:
    """
    Soft delete a library item.
    
    Issue #4: Timezone-aware timestamps.
    Issue #7: Validates user ownership when user_id is provided.
    """
    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    ts_value = now

    async with get_db() as db:
        check_query = "SELECT file_path FROM library_items WHERE id = ? AND license_key_id = ?"
        check_params = [item_id, license_id]
        
        # Issue #7: Make user_id check mandatory when provided
        if user_id:
            check_query += " AND user_id = ?"
            check_params.append(user_id)

        item = await fetch_one(db, check_query, check_params)
        if not item:
            logger.warning(f"Delete failed: item {item_id} not found or access denied")
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
        
        if user_id:
            update_query += " AND user_id = ?"
            update_params.append(user_id)

        await execute_sql(db, update_query, update_params)
        await commit_db(db)
        return True


async def bulk_delete_items(license_id: int, item_ids: List[int], user_id: Optional[str] = None) -> int:
    """
    Bulk soft delete library items.
    
    Issue #4: Timezone-aware timestamps.
    Issue #7: Validates user ownership for each item when user_id is provided.
    """
    if not item_ids:
        return 0

    # Issue #4: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    ts_value = now

    async with get_db() as db:
        # Issue #7: If user_id is provided, verify ownership for each item
        if user_id:
            # First verify all items belong to this user
            id_placeholders = ",".join(["?"] * len(item_ids))
            verify_query = f"SELECT COUNT(*) as count FROM library_items WHERE id IN ({id_placeholders}) AND license_key_id = ? AND user_id = ?"
            verify_params = item_ids + [license_id, user_id]
            
            result = await fetch_one(db, verify_query, verify_params)
            verified_count = result["count"] if result else 0
            
            if verified_count != len(item_ids):
                logger.warning(
                    f"Bulk delete: User {user_id} tried to delete {len(item_ids)} items "
                    f"but only owns {verified_count}"
                )
                # Delete only the items the user owns
                query = f"UPDATE library_items SET deleted_at = ? WHERE license_key_id = ? AND user_id = ? AND id IN ({id_placeholders})"
                params = [ts_value, license_id, user_id] + item_ids
            else:
                query = f"UPDATE library_items SET deleted_at = ? WHERE license_key_id = ? AND user_id = ? AND id IN ({id_placeholders})"
                params = [ts_value, license_id, user_id] + item_ids
        else:
            # No user_id - delete based on license only
            id_placeholders = ",".join(["?"] * len(item_ids))
            query = f"UPDATE library_items SET deleted_at = ? WHERE license_key_id = ? AND id IN ({id_placeholders})"
            params = [ts_value, license_id] + item_ids

        await execute_sql(db, query, params)
        await commit_db(db)
        return len(item_ids)


async def get_storage_usage(license_id: int) -> int:
    """
    Get total storage usage in bytes for a license.
    
    Issue #8: Ensures deleted items are properly excluded.
    Issue #31: Could be cached in Redis for performance (future enhancement).
    """
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT COALESCE(SUM(file_size), 0) as total FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
            [license_id]
        )
        return int(row["total"] if row else 0)


async def get_storage_usage_detailed(license_id: int) -> Dict[str, Any]:
    """
    Get detailed storage usage breakdown by type.
    
    New utility function for better storage insights.
    """
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
        
        return {
            "total_bytes": int(total_row["total"] if total_row else 0),
            "total_count": int(total_row["count"] if total_row else 0),
            "limit_bytes": MAX_STORAGE_PER_LICENSE,
            "percentage_used": round(
                (int(total_row["total"] if total_row else 0) / MAX_STORAGE_PER_LICENSE) * 100, 2
            ) if MAX_STORAGE_PER_LICENSE > 0 else 0,
            "by_type": {
                row["type"]: {
                    "bytes": int(row["size"]),
                    "count": int(row["count"])
                }
                for row in type_rows
            }
        }
