"""
Al-Mudeer - Library Models
CRUD operations for notes, images, files, audios, and videos
"""

import os
from datetime import datetime
from typing import List, Optional, Dict, Any

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE

# Default limits (can be configured via env)
MAX_STORAGE_PER_LICENSE = int(os.getenv("MAX_STORAGE_PER_LICENSE", 100 * 1024 * 1024))  # 100MB
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE", 20 * 1024 * 1024))  # 20MB

async def get_library_items(
    license_id: int, 
    user_id: Optional[str] = None,
    customer_id: Optional[int] = None,
    item_type: Optional[str] = None,
    category: Optional[str] = None,
    search_term: Optional[str] = None,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """Get library items for a license + global items (0), optionally filtered by customer, type or category."""
    query = "SELECT * FROM library_items WHERE (license_key_id = ? OR license_key_id = 0) AND deleted_at IS NULL"
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
        elif category == 'tools':
            query += " AND type = 'tool'"
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
    """Get a specific library item (including global)."""
    query = "SELECT * FROM library_items WHERE id = ? AND (license_key_id = ? OR license_key_id = 0) AND deleted_at IS NULL"
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
    """Add a new item to the library."""
    
    # Check storage limit (already checked in route for uploads, but good for other entry points)
    current_usage = await get_storage_usage(license_id)
    if current_usage + (file_size or 0) > MAX_STORAGE_PER_LICENSE:
        raise ValueError("تجاوزت حد التخزين المسموح به")

    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    
    async with get_db() as db:
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
    """Update library item metadata or content."""
    allowed_fields = ['title', 'content', 'customer_id']
    updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
    
    if not updates:
        return False
    
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
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
    """Soft delete a library item."""
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    
    async with get_db() as db:
        check_query = "SELECT file_path FROM library_items WHERE id = ? AND license_key_id = ?"
        check_params = [item_id, license_id]
        if user_id:
            check_query += " AND user_id = ?"
            check_params.append(user_id)
            
        item = await fetch_one(db, check_query, check_params)
        if not item:
            return False
            
        # Physical file deletion
        if item.get("file_path"):
            from services.file_storage_service import get_file_storage
            get_file_storage().delete_file(item["file_path"])

        update_query = "UPDATE library_items SET deleted_at = ? WHERE id = ? AND license_key_id = ?"
        update_params = [ts_value, item_id, license_id]
        if user_id:
            update_query += " AND user_id = ?"
            update_params.append(user_id)

        await execute_sql(db, update_query, update_params)
        await commit_db(db)
        return True

async def bulk_delete_items(license_id: int, item_ids: List[int], user_id: Optional[str] = None) -> int:
    """Bulk soft delete library items."""
    if not item_ids:
        return 0
        
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    
    # SQLite doesn't support multiple ? in IN clause easily, so we build it manually
    id_placeholders = ",".join(["?"] * len(item_ids))
    
    query = f"UPDATE library_items SET deleted_at = ? WHERE license_key_id = ? AND id IN ({id_placeholders})"
    params = [ts_value, license_id] + item_ids
    
    if user_id:
        query += " AND user_id = ?"
        params.append(user_id)
        
    async with get_db() as db:
        await execute_sql(db, query, params)
        await commit_db(db)
        return len(item_ids)

async def get_storage_usage(license_id: int) -> int:
    """Get total storage usage in bytes for a license."""
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT SUM(file_size) as total FROM library_items WHERE license_key_id = ? AND deleted_at IS NULL",
            [license_id]
        )
        return int(row["total"] or 0)
