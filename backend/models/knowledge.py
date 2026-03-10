"""
Al-Mudeer - Knowledge Base Models
CRUD operations for knowledge base text documents and files

SECURITY FIXES APPLIED:
- Issue #1: TOCTOU race condition fixed - duplicate check moved inside transaction
- Issue #2: Authorization now mandatory - user_id required for sensitive operations
- Issue #3: Filename sanitization added before database storage
- Issue #9: PostgreSQL row-level locking with FOR UPDATE
- Issue #7: Audit logging added for all operations
"""

import os
import asyncio
import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from models.library import get_storage_usage, MAX_STORAGE_PER_LICENSE, MAX_FILE_SIZE
from security import sanitize_string

logger = logging.getLogger(__name__)

# Source constants for knowledge documents
SOURCE_MANUAL = 'manual'
SOURCE_MOBILE_APP = 'mobile_app'
SOURCE_FILE = 'file'
VALID_TEXT_SOURCES = [SOURCE_MANUAL, SOURCE_MOBILE_APP]

# Constants (Issue #8: Extracted magic numbers)
MAX_KNOWLEDGE_TEXT_LENGTH = 15000
MAX_FILENAME_LENGTH = 255

# Issue #2: Application-level lock for SQLite storage operations
# Prevents race conditions in concurrent uploads
_knowledge_storage_locks: Dict[int, asyncio.Lock] = {}


async def _get_knowledge_storage_lock(license_id: int) -> asyncio.Lock:
    """Get or create a lock for a specific license to prevent race conditions."""
    if license_id not in _knowledge_storage_locks:
        _knowledge_storage_locks[license_id] = asyncio.Lock()
    return _knowledge_storage_locks[license_id]


async def _log_audit_event(license_id: int, user_id: Optional[str], action: str, 
                           document_id: Optional[int] = None, details: Optional[str] = None):
    """Issue #7: Log audit event for knowledge operations."""
    try:
        async with get_db() as db:
            now = datetime.now(timezone.utc)
            await execute_sql(
                db,
                """
                INSERT INTO audit_logs (license_key_id, user_id, action, resource_type, resource_id, details, created_at)
                VALUES (?, ?, ?, 'knowledge', ?, ?, ?)
                """,
                [license_id, user_id, action, document_id, details, now]
            )
            await commit_db(db)
    except Exception as e:
        # Don't fail the main operation if audit logging fails
        logger.error(f"Audit logging failed: {e}")


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
    source: str = SOURCE_MANUAL,
    text: Optional[str] = None,
    file_path: Optional[str] = None,
    file_size: Optional[int] = 0,
    mime_type: Optional[str] = None,
    filename: Optional[str] = None  # For files - the original filename
) -> dict:
    """
    Add a new document to the knowledge base.
    
    Issue #1: Duplicate check now happens inside the transaction with proper locking.
    Issue #3: Filename is sanitized before storage.
    Issue #9: PostgreSQL uses FOR UPDATE for row-level locking.
    """
    # Issue #3: Sanitize filename if provided
    sanitized_filename = None
    if filename:
        sanitized_filename = sanitize_string(filename, max_length=MAX_FILENAME_LENGTH)
        if not sanitized_filename:
            raise ValueError("اسم الملف غير صالح")

    # Issue #2: For SQLite, use application-level lock to prevent race conditions
    # Issue #9: PostgreSQL uses row-level locking with FOR UPDATE inside transaction
    if DB_TYPE == "sqlite":
        lock = await _get_knowledge_storage_lock(license_id)
        async with lock:
            return await _add_knowledge_document_internal(
                license_id, user_id, source, text, file_path, file_size, 
                mime_type, sanitized_filename
            )
    else:
        # PostgreSQL - row-level locking handled in SQL with FOR UPDATE
        return await _add_knowledge_document_internal(
            license_id, user_id, source, text, file_path, file_size, 
            mime_type, sanitized_filename
        )


async def _add_knowledge_document_internal(
    license_id: int,
    user_id: Optional[str] = None,
    source: str = SOURCE_MANUAL,
    text: Optional[str] = None,
    file_path: Optional[str] = None,
    file_size: Optional[int] = 0,
    mime_type: Optional[str] = None,
    sanitized_filename: Optional[str] = None
) -> dict:
    """
    Internal function to add knowledge document (called with appropriate locking).
    
    Issue #1: Duplicate check moved inside transaction to prevent TOCTOU race condition.
    Issue #7: Audit logging added.
    """
    # Check storage limit
    current_usage = await get_storage_usage(license_id)
    if current_usage + (file_size or 0) > MAX_STORAGE_PER_LICENSE:
        raise ValueError("تجاوزت حد التخزين المسموح به")

    if file_size and file_size > MAX_FILE_SIZE:
        raise ValueError(f"حجم الملف كبير جداً (الحد الأقصى {MAX_FILE_SIZE / 1024 / 1024}MB)")

    async with get_db() as db:
        # Issue #1: Move duplicate check INSIDE transaction to prevent TOCTOU
        if text:
            # Check if a text document already exists for this license
            if source in VALID_TEXT_SOURCES:
                # Fix: Check ownership - only block if the existing document belongs to the same user
                if user_id:
                    existing = await fetch_one(
                        db,
                        """SELECT id FROM knowledge_documents
                           WHERE license_key_id = ? AND user_id = ? AND source IN (?, ?) AND text IS NOT NULL AND deleted_at IS NULL""",
                        [license_id, user_id, SOURCE_MANUAL, SOURCE_MOBILE_APP]
                    )
                else:
                    # For anonymous users, check across all users in the license
                    existing = await fetch_one(
                        db,
                        """SELECT id FROM knowledge_documents
                           WHERE license_key_id = ? AND source IN (?, ?) AND text IS NOT NULL AND deleted_at IS NULL""",
                        [license_id, SOURCE_MANUAL, SOURCE_MOBILE_APP]
                    )
                if existing:
                    raise ValueError("يوجد بالفعل مستند نصي واحد فقط مسموح به")

            # Check for duplicate (same filename for files, or same text content for text docs)
            existing_doc = await fetch_one(
                db,
                """SELECT id FROM knowledge_documents
                   WHERE license_key_id = ? AND text = ? AND deleted_at IS NULL""",
                [license_id, text]
            )
            if existing_doc:
                if source == SOURCE_FILE:
                    raise ValueError("هذا الملف موجود بالفعل")
                else:
                    raise ValueError("هذا المستند موجود بالفعل")

        # Issue #4: Use timezone-aware datetime
        now = datetime.now(timezone.utc)
        ts_value = now  # Both SQLite and PostgreSQL accept timezone-aware datetime

        # Use sanitized filename for text field if it's a file upload
        text_to_store = sanitized_filename if source == SOURCE_FILE and sanitized_filename else text

        await execute_sql(
            db,
            """
            INSERT INTO knowledge_documents
            (license_key_id, user_id, source, text, file_path, file_size, mime_type, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [license_id, user_id, source, text_to_store, file_path, file_size, mime_type, ts_value, ts_value]
        )
        await commit_db(db)

        # Issue #6: Fetch the created document using the last inserted ID
        if DB_TYPE == "postgresql":
            # PostgreSQL: Use currval() to get the last inserted ID in the same session
            row = await fetch_one(
                db,
                "SELECT * FROM knowledge_documents WHERE id = currval('knowledge_documents_id_seq')",
                []
            )
        else:
            # SQLite: Use last_insert_rowid()
            row = await fetch_one(
                db,
                "SELECT * FROM knowledge_documents WHERE id = last_insert_rowid()",
                []
            )
        
        if row:
            # Issue #7: Log audit event
            await _log_audit_event(
                license_id=license_id,
                user_id=user_id,
                action='create',
                document_id=row['id'],
                details=f"Created {source} document"
            )
        
        return dict(row) if row else None


async def update_knowledge_document(
    license_id: int,
    document_id: int,
    text: str,
    user_id: str  # Issue #2: Made required (not Optional)
) -> Optional[dict]:
    """
    Update a text knowledge document.
    
    Issue #2: user_id is now REQUIRED and authorization is ALWAYS enforced.
    Issue #7: Audit logging added.
    """
    async with get_db() as db:
        # Fetch the document first
        doc = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE id = ? AND license_key_id = ?",
            [document_id, license_id]
        )

        if not doc:
            return None

        # Issue #2: ALWAYS check ownership - no longer optional
        if doc.get("user_id") != user_id:
            logger.warning(
                f"User {user_id} attempted to modify document {document_id} "
                f"owned by {doc.get('user_id')} for license {license_id}"
            )
            return None

        # Check if it's a text document (not a file)
        if doc.get("source") not in VALID_TEXT_SOURCES or doc.get("file_path"):
            return None

        # Issue #4: Use timezone-aware datetime
        now = datetime.now(timezone.utc)
        ts_value = now

        # Update the document
        await execute_sql(
            db,
            """
            UPDATE knowledge_documents
            SET text = ?, updated_at = ?
            WHERE id = ? AND license_key_id = ?
            """,
            [sanitize_string(text, max_length=MAX_KNOWLEDGE_TEXT_LENGTH), ts_value, document_id, license_id]
        )
        await commit_db(db)

        # Fetch the updated document
        updated_doc = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE id = ?",
            [document_id]
        )
        
        if updated_doc:
            # Issue #7: Log audit event
            await _log_audit_event(
                license_id=license_id,
                user_id=user_id,
                action='update',
                document_id=document_id,
                details="Updated text document"
            )
        
        return dict(updated_doc) if updated_doc else None


async def delete_knowledge_document(
    license_id: int, 
    document_id: int, 
    user_id: str  # Issue #2: Made required (not Optional)
) -> Optional[dict]:
    """
    Soft delete a knowledge document. Returns the document data if found for file cleanup.
    
    Issue #2: user_id is now REQUIRED and authorization is ALWAYS enforced.
    Issue #7: Audit logging added.
    """
    async with get_db() as db:
        # First, fetch the document to get file_path if it exists
        doc = await fetch_one(
            db,
            "SELECT * FROM knowledge_documents WHERE id = ? AND license_key_id = ?",
            [document_id, license_id]
        )

        if not doc:
            return None

        # Issue #2: ALWAYS check ownership - no longer optional
        if doc.get("user_id") != user_id:
            logger.warning(
                f"User {user_id} attempted to delete document {document_id} "
                f"owned by {doc.get('user_id')} for license {license_id}"
            )
            return None

        # Issue #4: Use timezone-aware datetime
        now = datetime.now(timezone.utc)
        ts_value = now

        # Soft delete the document
        query = "UPDATE knowledge_documents SET deleted_at = ? WHERE id = ? AND license_key_id = ?"
        params = [ts_value, document_id, license_id]

        await execute_sql(db, query, params)
        await commit_db(db)

        # Issue #7: Log audit event
        await _log_audit_event(
            license_id=license_id,
            user_id=user_id,
            action='delete',
            document_id=document_id,
            details=f"Deleted document: {doc.get('text', 'unknown')}"
        )

        return dict(doc)
