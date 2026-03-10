"""
Al-Mudeer - Knowledge Base API Routes
Handling text and file uploads for user knowledge base storage

SECURITY FIXES APPLIED:
- Issue #1: TOCTOU race condition fixed - duplicate check moved to model (inside transaction)
- Issue #3: Filename sanitization added before database storage
- Issue #4: File size validation BEFORE reading (Content-Length check)
- Issue #5: Error handling improved - no internal details exposed
- Issue #6: Rate limiting added on upload endpoints
- Issue #7: Audit logging enabled for all operations
- Issue #8: Magic numbers extracted to constants
- Issue #10: Response formats standardized
"""

import os
import logging
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query, Request
from pydantic import BaseModel

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user_optional
from models.knowledge import (
    get_knowledge_documents,
    add_knowledge_document,
    update_knowledge_document,
    delete_knowledge_document,
    SOURCE_FILE,
    VALID_TEXT_SOURCES,
    MAX_KNOWLEDGE_TEXT_LENGTH,  # Issue #8: Imported constant
    MAX_FILENAME_LENGTH
)
from models.library import MAX_FILE_SIZE
from services.file_storage_service import get_file_storage, validate_file_upload, is_allowed_file_type
from security import sanitize_string
from db_helper import get_db, fetch_one

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/knowledge", tags=["Knowledge Base"])

# File storage service instance
file_storage = get_file_storage()

# Issue #6: Rate limiting configuration
UPLOAD_RATE_LIMIT = 10  # requests per minute
UPLOAD_RATE_WINDOW = 60  # seconds


class DocumentMetadata(BaseModel):
    source: Optional[str] = 'manual'
    created_at: Optional[str] = None


class DocumentCreate(BaseModel):
    text: str
    metadata: Optional[DocumentMetadata] = None


# Issue #10: Standardized response format
def _standard_response(data: dict, success: bool = True) -> dict:
    """Return standardized API response format."""
    return {
        "success": success,
        "data": data,
        "error": None
    }


def _error_response(detail: str, success: bool = False) -> dict:
    """Return standardized error response format."""
    return {
        "success": success,
        "data": None,
        "error": detail
    }


@router.get("/documents")
async def list_documents(
    page: int = 1,
    page_size: int = 50,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """List knowledge documents for the current license to display in the mobile app."""
    user_id = user.get("user_id") if user else None
    offset = (page - 1) * page_size

    items = await get_knowledge_documents(
        license_id=license["license_id"],
        user_id=user_id,
        limit=page_size,
        offset=offset
    )

    # Get total count for pagination
    async with get_db() as db:
        count_query = "SELECT COUNT(*) as count FROM knowledge_documents WHERE license_key_id = ? AND deleted_at IS NULL"
        count_params = [license["license_id"]]
        if user_id:
            count_query += " AND user_id = ?"
            count_params.append(user_id)
        count_result = await fetch_one(db, count_query, count_params)
        total = count_result["count"] if count_result else 0

    # Format according to what the mobile app expects
    formatted_docs = []
    for item in items:
        # Reconstruct exactly what the app's `KnowledgeDocument.fromJson` needs
        formatted_docs.append({
            "id": str(item["id"]),
            "text": item["text"] or item["file_path"],
            "file_path": item["file_path"],
            "metadata": {
                "source": item["source"],
                "created_at": str(item["created_at"])
            }
        })

    # Issue #10: Standardized response format
    return _standard_response({
        "documents": formatted_docs,
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": (total + page_size - 1) // page_size
    })


@router.post("/documents")
async def create_text_document(
    data: DocumentCreate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Create a new text knowledge document."""
    user_id = user.get("user_id") if user else None
    source = data.metadata.source if data.metadata else 'manual'

    try:
        item = await add_knowledge_document(
            license_id=license["license_id"],
            user_id=user_id,
            source=source,
            text=sanitize_string(data.text, max_length=MAX_KNOWLEDGE_TEXT_LENGTH)
        )
        return _standard_response({
            "document": {
                "id": str(item["id"]),
                "text": item["text"],
                "metadata": {
                    "source": item["source"],
                    "created_at": str(item["created_at"])
                }
            }
        })
    except ValueError as e:
        logger.info(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception(f"Unexpected error creating document")
        raise HTTPException(status_code=500, detail="حدث خطأ داخلي أثناء الإنشاء")


@router.put("/documents/{document_id}")
async def update_text_document(
    document_id: int,
    data: DocumentCreate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Update an existing text knowledge document."""
    user_id = user.get("user_id") if user else None

    # Issue #2: user_id is required for authorization
    if not user_id:
        raise HTTPException(status_code=401, detail="يجب تسجيل الدخول لتعديل المستندات")

    try:
        item = await update_knowledge_document(
            license_id=license["license_id"],
            document_id=document_id,
            text=data.text,
            user_id=user_id  # Now required
        )

        if not item:
            raise HTTPException(status_code=404, detail="المستند غير موجود أو لا يمكن تعديله")

        return _standard_response({
            "document": {
                "id": str(item["id"]),
                "text": item["text"],
                "metadata": {
                    "source": item["source"],
                    "created_at": str(item["created_at"])
                }
            }
        })
    except ValueError as e:
        logger.info(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception(f"Unexpected error updating document")
        raise HTTPException(status_code=500, detail="حدث خطأ داخلي أثناء التعديل")


@router.post("/upload")
async def upload_knowledge_file(
    request: Request,
    file: UploadFile = File(...),
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Upload a file document to the knowledge base."""
    user_id = user.get("user_id") if user else None
    content_type = file.content_type or "application/octet-stream"

    # Issue #6: Rate limiting check
    try:
        from services.rate_limiting import check_rate_limit, RateLimitExceeded
        await check_rate_limit(
            identifier=f"knowledge:{license['license_id']}",
            action="upload",
            max_requests=UPLOAD_RATE_LIMIT,
            window_seconds=UPLOAD_RATE_WINDOW
        )
    except RateLimitExceeded as e:
        logger.warning(f"Rate limit exceeded for license {license['license_id']}: {e.message}")
        raise HTTPException(
            status_code=429,
            detail=f"تم تجاوز حد الرفع المسموح به. حاول مرة أخرى خلال {e.retry_after} ثانية"
        )
    except Exception as e:
        logger.warning(f"Rate limit check failed: {e}")
        # Don't block the request if rate limiting service is unavailable

    try:
        # Issue #4: SECURITY - Check file size from Content-Length header BEFORE reading
        content_length = file.size
        if content_length and content_length > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=400,
                detail=f"حجم الملف كبير جداً (الحد الأقصى {MAX_FILE_SIZE / 1024 / 1024}MB)"
            )

        # SECURITY: Validate file type before processing
        is_valid, error_message = validate_file_upload(
            filename=file.filename or "",
            mime_type=content_type,
            file_size=content_length or 0,
            file_type="file"
        )
        if not is_valid:
            raise HTTPException(status_code=400, detail=f"نوع الملف غير مدعوم: {error_message}")

        # Issue #3: Sanitize filename before any processing
        sanitized_filename = sanitize_string(file.filename or "", max_length=MAX_FILENAME_LENGTH)
        if not sanitized_filename:
            raise HTTPException(status_code=400, detail="اسم الملف غير صالح")

        # Issue #4: Read file content with size validation
        content = await file.read()
        file_size = len(content)

        # Double-check file size after reading (defense in depth)
        if file_size > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=400,
                detail=f"حجم الملف كبير جداً (الحد الأقصى {MAX_FILE_SIZE / 1024 / 1024}MB)"
            )

        # Issue #1: Duplicate check moved INSIDE add_knowledge_document (inside transaction)
        # This prevents TOCTOU race condition

        # Upload the file
        relative_path, public_url = file_storage.save_file(
            content=content,
            filename=file.filename,  # Keep original for file system
            mime_type=content_type,
            subfolder="knowledge"
        )

        # Save the sanitized filename in the 'text' column
        item = await add_knowledge_document(
            license_id=license["license_id"],
            user_id=user_id,
            source=SOURCE_FILE,
            text=sanitized_filename,  # Use sanitized filename
            file_path=public_url,
            file_size=file_size,
            mime_type=content_type,
            filename=sanitized_filename  # Pass for duplicate check
        )

        return _standard_response({
            "document": {
                "id": str(item["id"]),
                "text": item["text"],
                "metadata": {
                    "source": item["source"],
                    "created_at": str(item["created_at"])
                }
            }
        })
    except HTTPException:
        # Re-raise HTTP exceptions (including validation errors)
        raise
    except ValueError as e:
        # DB level errors (e.g. limit reached, duplicate)
        logger.info(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        # Issue #5: Don't expose internal error details
        logger.exception(f"Upload failed with unexpected error")
        raise HTTPException(status_code=500, detail="حدث خطأ داخلي أثناء الرفع")


@router.delete("/documents/{document_id}")
async def delete_document(
    document_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Delete a knowledge document and its associated file if exists."""
    user_id = user.get("user_id") if user else None

    # Issue #2: user_id is required for authorization
    if not user_id:
        raise HTTPException(status_code=401, detail="يجب تسجيل الدخول لحذف المستندات")

    # Delete from database and get document data
    deleted_doc = await delete_knowledge_document(
        license_id=license["license_id"],
        document_id=document_id,
        user_id=user_id  # Now required
    )

    if not deleted_doc:
        raise HTTPException(status_code=404, detail="المستند غير موجود")

    # Delete physical file if it exists
    file_path = deleted_doc.get("file_path")
    if file_path:
        try:
            file_storage.delete_file(file_path)
            logger.info(f"Deleted knowledge file: {file_path}")
        except Exception as e:
            logger.error(f"Failed to delete knowledge file {file_path}: {e}")
            # Don't fail the request - document is already deleted from DB
            # File will be cleaned up by cleanup script

    return _standard_response({"deleted": True})
