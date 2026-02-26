"""
Al-Mudeer - Library Attachments Models
CRUD operations for library item attachments

P3-12: Multiple attachments per library item
"""

import os
import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from functools import lru_cache

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db

logger = logging.getLogger(__name__)

# File size limit for attachments (10MB)
MAX_ATTACHMENT_SIZE = int(os.getenv("MAX_ATTACHMENT_SIZE", "10485760"))


async def get_attachments(item_id: int, license_id: int) -> List[dict]:
    """Get all attachments for a library item"""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT * FROM library_attachments
            WHERE library_item_id = ? AND license_key_id = ? AND deleted_at IS NULL
            ORDER BY created_at ASC
            """,
            [item_id, license_id]
        )
        return [dict(row) for row in rows]


async def get_attachment(attachment_id: int, license_id: int) -> Optional[dict]:
    """Get a specific attachment"""
    async with get_db() as db:
        row = await fetch_one(
            db,
            """
            SELECT * FROM library_attachments
            WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL
            """,
            [attachment_id, license_id]
        )
        return dict(row) if row else None


async def add_attachment(
    license_id: int,
    item_id: int,
    file_path: str,
    filename: str,
    file_size: int,
    mime_type: str,
    file_hash: Optional[str] = None,
    created_by: Optional[str] = None
) -> dict:
    """Add an attachment to a library item"""
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Verify parent item exists
        item = await fetch_one(
            db,
            "SELECT id FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license_id]
        )
        
        if not item:
            raise ValueError("Parent library item not found")
        
        # Check storage quota
        usage = await fetch_one(
            db,
            """
            SELECT COALESCE(SUM(file_size), 0) as total FROM library_attachments
            WHERE license_key_id = ? AND deleted_at IS NULL
            """,
            [license_id]
        )
        
        current_usage = int(usage["total"] if usage else 0)
        from models.library import MAX_STORAGE_PER_LICENSE
        
        if current_usage + file_size > MAX_STORAGE_PER_LICENSE:
            raise ValueError("Storage limit exceeded")
        
        await execute_sql(
            db,
            """
            INSERT INTO library_attachments
            (library_item_id, license_key_id, file_path, filename, file_size, mime_type, file_hash, created_at, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [item_id, license_id, file_path, filename, file_size, mime_type, file_hash, now, created_by]
        )
        
        await commit_db(db)
        
        # Fetch created attachment
        row = await fetch_one(
            db,
            "SELECT * FROM library_attachments ORDER BY id DESC LIMIT 1",
            [item_id]
        )
        return dict(row)


async def delete_attachment(attachment_id: int, license_id: int, user_id: Optional[str] = None) -> bool:
    """Soft delete an attachment"""
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Verify attachment exists
        attachment = await fetch_one(
            db,
            "SELECT file_path FROM library_attachments WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [attachment_id, license_id]
        )
        
        if not attachment:
            return False
        
        # Delete physical file
        if attachment.get("file_path"):
            from services.file_storage_service import get_file_storage
            try:
                get_file_storage().delete_file(attachment["file_path"])
            except Exception as e:
                logger.error(f"Failed to delete attachment file: {e}")
        
        # Soft delete
        await execute_sql(
            db,
            "UPDATE library_attachments SET deleted_at = ? WHERE id = ? AND license_key_id = ?",
            [now, attachment_id, license_id]
        )
        
        await commit_db(db)
        return True


async def get_attachment_storage_usage(license_id: int) -> int:
    """Get total storage used by attachments"""
    async with get_db() as db:
        row = await fetch_one(
            db,
            """
            SELECT COALESCE(SUM(file_size), 0) as total FROM library_attachments
            WHERE license_key_id = ? AND deleted_at IS NULL
            """,
            [license_id]
        )
        return int(row["total"] if row else 0)
