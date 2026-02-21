"""
Al-Mudeer - Knowledge Base Models
CRUD operations for knowledge base text documents and files
"""

import os
from datetime import datetime
from typing import List, Optional, Dict, Any

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from models.library import get_storage_usage, MAX_STORAGE_PER_LICENSE, MAX_FILE_SIZE

async def get_knowledge_documents(
    license_id: int, 
    user_id: Optional[str] = None,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """Get knowledge documents for a license."""
    query = "SELECT * FROM knowledge_documents WHERE license_key_id = ? AND deleted_at IS NULL"
    params = [license_id]
        
    if user_id:
        query += " AND user_id = ?"
        params.append(user_id)
        
    query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])
    
    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        return [dict(row) for row in rows]

async def add_knowledge_document(
    license_id: int,
    user_id: Optional[str] = None,
    source: str = 'manual',
    text: Optional[str] = None,
    file_path: Optional[str] = None,
    file_size: Optional[int] = 0,
    mime_type: Optional[str] = None
) -> dict:
    """Add a new document to the knowledge base."""
    
    # Check storage limit
    current_usage = await get_storage_usage(license_id)
    if current_usage + (file_size or 0) > MAX_STORAGE_PER_LICENSE:
        raise ValueError("تجاوزت حد التخزين المسموح به")

    if file_size and file_size > MAX_FILE_SIZE:
        raise ValueError(f"حجم الملف كبير جداً (الحد الأقصى {MAX_FILE_SIZE / 1024 / 1024}MB)")

    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    
    async with get_db() as db:
        await execute_sql(
            db,
            """
            INSERT INTO knowledge_documents 
            (license_key_id, user_id, source, text, file_path, file_size, mime_type, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [license_id, user_id, source, text, file_path, file_size, mime_type, ts_value, ts_value]
        )
        await commit_db(db)
        
        # Fetch the created document
        row = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE license_key_id = ? ORDER BY id DESC LIMIT 1",
            [license_id]
        )
        return dict(row)

async def delete_knowledge_document(license_id: int, document_id: int, user_id: Optional[str] = None) -> bool:
    """Soft delete a knowledge document."""
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    
    query = "UPDATE knowledge_documents SET deleted_at = ? WHERE id = ? AND license_key_id = ?"
    params = [ts_value, document_id, license_id]
    
    if user_id:
        query += " AND user_id = ?"
        params.append(user_id)
        
    async with get_db() as db:
        await execute_sql(db, query, params)
        await commit_db(db)
        return True
