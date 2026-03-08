"""
Al-Mudeer - Knowledge Base Models
CRUD operations for knowledge base text documents and files
"""

import os
from datetime import datetime
from typing import List, Optional, Dict, Any

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from models.library import get_storage_usage, MAX_STORAGE_PER_LICENSE, MAX_FILE_SIZE
from security import sanitize_string

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

    # Only allow 1 text document per license
    if text:
        async with get_db() as db:
            # Check if a text document already exists for this license
            existing = await fetch_one(
                db,
                """SELECT id FROM knowledge_documents
                   WHERE license_key_id = ? AND source = 'manual' AND text IS NOT NULL AND deleted_at IS NULL""",
                [license_id]
            )
            if existing:
                raise ValueError("يوجد بالفعل مستند نصي واحد فقط مسموح به")

            # Check for duplicate text (same text content)
            existing_text = await fetch_one(
                db,
                """SELECT id FROM knowledge_documents
                   WHERE license_key_id = ? AND text = ? AND deleted_at IS NULL""",
                [license_id, text]
            )
            if existing_text:
                raise ValueError("هذا المستند موجود بالفعل")

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

async def update_knowledge_document(
    license_id: int,
    document_id: int,
    text: str,
    user_id: Optional[str] = None
) -> Optional[dict]:
    """Update a text knowledge document."""
    async with get_db() as db:
        # Fetch the document first
        doc = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE id = ? AND license_key_id = ?",
            [document_id, license_id]
        )

        if not doc:
            return None

        # Check user ownership if user_id is provided
        if user_id and doc.get("user_id") != user_id:
            return None

        # Check if it's a text document (not a file)
        if doc.get("source") != 'manual' or doc.get("file_path"):
            return None

        now = datetime.utcnow()
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

        # Update the document
        await execute_sql(
            db,
            """
            UPDATE knowledge_documents
            SET text = ?, updated_at = ?
            WHERE id = ? AND license_key_id = ?
            """,
            [sanitize_string(text, max_length=15000), ts_value, document_id, license_id]
        )
        await commit_db(db)

        # Fetch the updated document
        updated_doc = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE id = ?",
            [document_id]
        )
        return dict(updated_doc) if updated_doc else None

async def delete_knowledge_document(license_id: int, document_id: int, user_id: Optional[str] = None) -> Optional[dict]:
    """Soft delete a knowledge document. Returns the document data if found for file cleanup."""
    # First, fetch the document to get file_path if it exists
    async with get_db() as db:
        doc = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE id = ? AND license_key_id = ?",
            [document_id, license_id]
        )
        
        if not doc:
            return None
        
        # Check user ownership if user_id is provided
        if user_id and doc.get("user_id") != user_id:
            return None
        
        # Soft delete the document
        now = datetime.utcnow()
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        query = "UPDATE knowledge_documents SET deleted_at = ? WHERE id = ? AND license_key_id = ?"
        params = [ts_value, document_id, license_id]
        
        await execute_sql(db, query, params)
        await commit_db(db)
        
        return dict(doc)
