"""
Al-Mudeer - Library API Routes
Handling Notes, Images, Files, Audio, and Video uploads/management

Fixes applied:
- Issue #1: File size validation at route level
- Issue #6: MIME type validation with allowlist
- Issue #9: Pagination limit enforcement
- Issue #10: Content-length validation for notes
- Issue #11: Rate limiting on upload endpoint
- Issue #25: Error code localization
- Issue #27: File content validation (via python-magic) - ENABLED
- Issue #28: Path traversal vulnerability fix
- Issue #30: N+1 query optimization (selective columns)
- Issue #34: Search term length validation
- Issue #35: Customer ID ownership validation
- Issue #36: Improved error handling in file cleanup
"""

import os
import uuid
import shutil
import logging
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query, Request
from pydantic import BaseModel, Field, validator

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user_optional
from models.library import (
    get_library_items,
    add_library_item,
    update_library_item,
    delete_library_item,
    bulk_delete_items,
    get_storage_usage,
    get_storage_usage_detailed,
    MAX_STORAGE_PER_LICENSE,
    MAX_FILE_SIZE,
    _invalidate_storage_cache
)
from db_helper import get_db, fetch_all
from services.file_storage_service import get_file_storage
from security import sanitize_string
from rate_limiting import limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/library", tags=["Library"])

# File storage service instance
file_storage = get_file_storage()

# Constants for validation
MAX_PAGINATION_LIMIT = 100  # Issue #9: Hard cap on page_size
MAX_NOTE_CONTENT_LENGTH = 5000  # Issue #10: Max note content length
MAX_SEARCH_TERM_LENGTH = 100  # Issue #34: Max search term length to prevent DoS

# Issue #6: MIME type allowlist for security
ALLOWED_MIME_TYPES = {
    # Images
    'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/bmp', 'image/svg+xml',
    # Audio
    'audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/aac', 'audio/ogg', 'audio/flac', 'audio/mp4', 'audio/x-m4a',
    # Video
    'video/mp4', 'video/quicktime', 'video/x-msvideo', 'video/x-matroska', 'video/webm', 'video/mpeg',
    # Documents
    'application/pdf', 'text/plain', 'text/csv', 'text/markdown',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',  # .docx
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',  # .xlsx
    'application/msword',  # .doc
    'application/vnd.ms-excel',  # .xls
}

# Issue #6: File extension allowlist (additional security layer)
ALLOWED_EXTENSIONS = {
    # Images
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg',
    # Audio
    '.mp3', '.wav', '.aac', '.ogg', '.flac', '.m4a',
    # Video
    '.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpeg', '.mpg',
    # Documents
    '.pdf', '.txt', '.csv', '.md', '.doc', '.docx', '.xls', '.xlsx'
}

# Issue #25: Error code enum for localization
class ErrorCode:
    STORAGE_LIMIT_EXCEEDED = "STORAGE_LIMIT_EXCEEDED"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    INVALID_FILE_TYPE = "INVALID_FILE_TYPE"
    FILE_UPLOAD_FAILED = "FILE_UPLOAD_FAILED"
    ITEM_NOT_FOUND = "ITEM_NOT_FOUND"
    NOTE_TOO_LONG = "NOTE_TOO_LONG"
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    CUSTOMER_ACCESS_DENIED = "CUSTOMER_ACCESS_DENIED"
    SEARCH_TERM_TOO_LONG = "SEARCH_TERM_TOO_LONG"


class NoteCreate(BaseModel):
    customer_id: Optional[int] = None
    title: str = Field(..., min_length=1, max_length=200)
    content: str = Field(..., min_length=1, max_length=MAX_NOTE_CONTENT_LENGTH)
    
    # Issue #10: Validate content length
    @validator('content')
    def validate_content_length(cls, v):
        if len(v) > MAX_NOTE_CONTENT_LENGTH:
            raise ValueError(f"الملاحظة طويلة جداً (الحد الأقصى {MAX_NOTE_CONTENT_LENGTH} حرف)")
        return v


class ItemUpdate(BaseModel):
    title: Optional[str] = Field(None, max_length=200)
    content: Optional[str] = Field(None, max_length=MAX_NOTE_CONTENT_LENGTH)
    customer_id: Optional[int] = None


class BulkDeleteRequest(BaseModel):
    item_ids: List[int]

@router.get("/")
@limiter.limit("30/minute")  # P1-7: Rate limiting to prevent scraping/abuse
async def list_items(
    request: Request,  # Required for rate limiter
    customer_id: Optional[int] = None,
    type: Optional[str] = None,
    category: Optional[str] = None,
    search: Optional[str] = Query(None, description="Search term for title or content"),
    page: int = 1,
    page_size: int = 50,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    List library items for the current license.

    Issue #9: Enforces max pagination limit to prevent performance issues.
    Issue #30: Uses selective column fetching in model layer.
    Issue #34: Search term length validation.
    Issue #35: Customer ID ownership validation.
    P1-7: Rate limited to 30 requests/minute to prevent scraping.
    """
    # Issue #9: Enforce pagination limit
    page_size = min(page_size, MAX_PAGINATION_LIMIT)

    # Issue #34: Validate search term length
    if search and len(search) > MAX_SEARCH_TERM_LENGTH:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.SEARCH_TERM_TOO_LONG,
                "message_ar": f"كلمة البحث طويلة جداً (الحد الأقصى {MAX_SEARCH_TERM_LENGTH} حرف)",
                "message_en": f"Search term too long (maximum {MAX_SEARCH_TERM_LENGTH} characters)"
            }
        )

    # Issue #35: Validate customer_id ownership if provided
    if customer_id is not None:
        from models.customers import get_customer
        async with get_db() as db:
            customer = await get_customer(db, customer_id, license["license_id"])
            if not customer:
                raise HTTPException(
                    status_code=403,
                    detail={
                        "code": ErrorCode.CUSTOMER_ACCESS_DENIED,
                        "message_ar": "لا يمكنك الوصول إلى عميل لا يتبع رخصتك",
                        "message_en": "You cannot access a customer that doesn't belong to your license"
                    }
                )

    user_id = user.get("user_id") if user else None
    offset = (page - 1) * page_size

    # Issue #30: Model now uses selective column fetching for list views
    items = await get_library_items(
        license_id=license["license_id"],
        user_id=user_id,
        customer_id=customer_id,
        item_type=type,
        category=category,
        search_term=search,
        limit=page_size,
        offset=offset
    )

    usage = await get_storage_usage(license["license_id"])

    return {
        "success": True,
        "items": items,
        "storage_usage_bytes": usage,
        "page": page,
        "page_size": page_size,
        "max_page_size": MAX_PAGINATION_LIMIT  # Inform client of limit
    }

@router.post("/notes")
async def create_note(
    data: NoteCreate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Create a new text note.
    
    Issue #10: Validates content length before processing.
    Issue #25: Returns localized error codes.
    """
    user_id = user.get("user_id") if user else None
    
    # Issue #10: Additional validation layer (Pydantic already validates)
    if len(data.content) > MAX_NOTE_CONTENT_LENGTH:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.NOTE_TOO_LONG,
                "message_ar": f"الملاحظة طويلة جداً (الحد الأقصى {MAX_NOTE_CONTENT_LENGTH} حرف)",
                "message_en": "Note content exceeds maximum length"
            }
        )
    
    try:
        item = await add_library_item(
            license_id=license["license_id"],
            user_id=user_id,
            item_type="note",
            customer_id=data.customer_id,
            title=sanitize_string(data.title),
            content=sanitize_string(data.content, max_length=MAX_NOTE_CONTENT_LENGTH)
        )
        return {"success": True, "item": item}
    except ValueError as e:
        error_msg = str(e)
        # Issue #25: Return structured error with code
        if "تجاوزت حد التخزين" in error_msg or "storage" in error_msg.lower():
            raise HTTPException(
                status_code=400,
                detail={
                    "code": ErrorCode.STORAGE_LIMIT_EXCEEDED,
                    "message_ar": error_msg,
                    "message_en": "Storage limit exceeded"
                }
            )
        raise HTTPException(status_code=400, detail=error_msg)

@router.post("/upload")
@limiter.limit("10/minute")  # Issue #11: Stricter rate limiting for uploads
async def upload_file(
    request: Request,
    file: UploadFile = File(...),
    customer_id: Optional[int] = Form(None),
    title: Optional[str] = Form(None),
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Upload a media or file item.
    
    Fixes applied:
    - Issue #1: File size validation BEFORE reading file
    - Issue #3: Transaction rollback with file cleanup
    - Issue #6: MIME type and extension validation
    - Issue #11: Rate limiting (decorator above)
    - Issue #25: Localized error codes
    - Issue #27: File content validation (python-magic)
    - Issue #28: Path traversal prevention
    """
    user_id = user.get("user_id") if user else None
    relative_path = None  # Track for cleanup on failure
    
    # Get file size FIRST before any processing (Issue #1)
    try:
        await file.seek(0, 2)
        file_size = file.tell()
        await file.seek(0)
    except Exception as e:
        logger.error(f"Failed to get file size: {e}")
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.FILE_UPLOAD_FAILED,
                "message_ar": "فشل قراءة حجم الملف",
                "message_en": "Failed to read file size"
            }
        )
    
    # Issue #1: Validate file size BEFORE processing
    if file_size > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.FILE_TOO_LARGE,
                "message_ar": f"حجم الملف كبير جداً (الحد الأقصى {MAX_FILE_SIZE / 1024 / 1024}MB)",
                "message_en": f"File size exceeds maximum limit ({MAX_FILE_SIZE / 1024 / 1024}MB)"
            }
        )
    
    # Check storage limit BEFORE upload (Issue #2 - partial fix, full fix in model)
    try:
        current_usage = await get_storage_usage(license["license_id"])
        if current_usage + file_size > MAX_STORAGE_PER_LICENSE:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": ErrorCode.STORAGE_LIMIT_EXCEEDED,
                    "message_ar": "تجاوزت حد التخزين المسموح به",
                    "message_en": "Storage limit exceeded"
                }
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Storage check failed: {e}")
        raise HTTPException(
            status_code=500,
            detail={
                "code": ErrorCode.INTERNAL_ERROR,
                "message_ar": "فشل التحقق من مساحة التخزين",
                "message_en": "Failed to check storage"
            }
        )
    
    # Determine type from mime_type
    content_type = file.content_type or "application/octet-stream"
    
    # Issue #6: Validate MIME type
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.INVALID_FILE_TYPE,
                "message_ar": f"نوع الملف غير مدعوم: {content_type}",
                "message_en": f"Unsupported file type: {content_type}"
            }
        )
    
    # Issue #6: Validate file extension
    file_ext = os.path.splitext(file.filename or "").lower()[1]
    if file_ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.INVALID_FILE_TYPE,
                "message_ar": f"امتداد الملف غير مدعوم: {file_ext}",
                "message_en": f"Unsupported file extension: {file_ext}"
            }
        )
    
    # Determine item type
    item_type = "file"
    if content_type.startswith("image/"):
        item_type = "image"
    elif content_type.startswith("audio/"):
        item_type = "audio"
    elif content_type.startswith("video/"):
        item_type = "video"

    # P0-1 & P0-2: Compute hash FIRST and check for duplicate BEFORE saving
    # This prevents wasted I/O and storage on duplicate files
    file_hash = None
    actual_mime = content_type
    try:
        # Read file ONCE for both hash computation and magic validation
        import hashlib
        import magic
        
        hasher = hashlib.sha256()
        file_sample = None
        
        # Read file in chunks, compute hash, and capture sample for magic
        async for chunk in file.file.iter_chunks(8192):
            if file_sample is None:
                file_sample = chunk[:2048]
            hasher.update(chunk)
        
        file_hash = hasher.hexdigest()
        
        # Check for duplicate BEFORE any file I/O
        from db_helper import fetch_one, get_db
        async with get_db() as db:
            existing = await fetch_one(
                db,
                """
                SELECT id, title, file_path FROM library_items
                WHERE license_key_id = ? AND file_hash = ? AND deleted_at IS NULL
                """,
                [license["license_id"], file_hash]
            )
            if existing:
                logger.info(
                    f"Duplicate file detected: {file.filename} matches {existing['title']} (ID: {existing['id']})"
                )
                # Return existing item instead of uploading duplicate
                return {
                    "success": True,
                    "item": dict(existing),
                    "is_duplicate": True,
                    "message": "File already exists in library"
                }
        
        # Validate actual file content with python-magic (from the sample we already read)
        if file_sample:
            actual_mime = magic.from_buffer(file_sample, mime=True)
            
            # Allow some flexibility for compatible MIME types
            if actual_mime not in ALLOWED_MIME_TYPES:
                base_type = actual_mime.split('/')[0] if '/' in actual_mime else actual_mime
                declared_base = content_type.split('/')[0] if '/' in content_type else content_type
                
                # If base types don't match at all, reject
                if base_type != declared_base:
                    logger.warning(
                        f"File content mismatch: declared={content_type}, actual={actual_mime}"
                    )
                    raise HTTPException(
                        status_code=400,
                        detail={
                            "code": ErrorCode.INVALID_FILE_TYPE,
                            "message_ar": f"محتوى الملف لا يتطابق مع النوع المعلن: {actual_mime}",
                            "message_en": f"File content doesn't match declared type: {actual_mime}"
                        }
                    )
            
            # Update item_type based on ACTUAL content, not declared type
            if actual_mime.startswith("image/"):
                item_type = "image"
            elif actual_mime.startswith("audio/"):
                item_type = "audio"
            elif actual_mime.startswith("video/"):
                item_type = "video"
                
    except ImportError as e:
        # python-magic not installed - log warning but continue (graceful degradation)
        logger.warning(f"python-magic not installed, skipping content validation: {e}")
        # Still compute hash even without magic
        try:
            import hashlib
            hasher = hashlib.sha256()
            async for chunk in file.file.iter_chunks(8192):
                hasher.update(chunk)
            file_hash = hasher.hexdigest()
        except Exception as hash_error:
            logger.warning(f"Failed to compute file hash: {hash_error}")
    except HTTPException:
        # Re-raise HTTP exceptions (like content mismatch)
        raise
    except Exception as e:
        logger.warning(f"Failed to compute file hash or validate content: {e}")
    
    # Reset file pointer for saving
    await file.seek(0)

    # Issue #3: Transaction with rollback on failure
    try:
        # Save file asynchronously (only after duplicate check passes)
        relative_path, public_url = await file_storage.save_upload_file_async(
            upload_file=file,
            filename=file.filename,
            mime_type=actual_mime,  # Use actual MIME type from content analysis
            subfolder="library"
        )

        # Add to DB with file_hash and actual_mime
        item = await add_library_item(
            license_id=license["license_id"],
            user_id=user_id,
            item_type=item_type,
            customer_id=customer_id,
            title=sanitize_string(title or file.filename),
            file_path=public_url,
            file_size=file_size,
            mime_type=actual_mime,  # Store actual MIME type
            file_hash=file_hash
        )

        return {"success": True, "item": item}

    except HTTPException:
        # Issue #36: Improved cleanup with proper error chaining
        if relative_path:
            try:
                file_storage.delete_file(relative_path)
                logger.info(f"Cleaned up orphaned file: {relative_path}")
            except Exception as cleanup_error:
                # Log cleanup error but preserve original exception
                logger.error(f"Failed to cleanup orphaned file: {cleanup_error}", exc_info=True)
        raise
    except ValueError as e:
        # Issue #3: Cleanup on storage limit error
        if relative_path:
            file_storage.delete_file(relative_path)
        error_msg = str(e)
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.STORAGE_LIMIT_EXCEEDED if "تجاوزت" in error_msg else ErrorCode.FILE_UPLOAD_FAILED,
                "message_ar": error_msg,
                "message_en": "Storage limit exceeded" if "تجاوزت" in error_msg else "Upload failed"
            }
        )
    except Exception as e:
        # Issue #3: Cleanup on any unexpected error
        if relative_path:
            try:
                file_storage.delete_file(relative_path)
                logger.info(f"Cleaned up orphaned file after error: {relative_path}")
            except Exception as cleanup_error:
                logger.error(f"Failed to cleanup orphaned file: {cleanup_error}")
        
        logger.error(f"Upload failed: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": ErrorCode.FILE_UPLOAD_FAILED,
                "message_ar": f"حدث خطأ أثناء الرفع: {str(e)}",
                "message_en": "File upload failed"
            }
        )

@router.patch("/{item_id}")
async def update_item(
    item_id: int,
    data: ItemUpdate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Update item metadata.
    
    Issue #25: Returns localized error codes.
    """
    user_id = user.get("user_id") if user else None
    
    # Validate input
    if data.title is None and data.content is None and data.customer_id is None:
        return {"success": True, "message": "No updates provided"}
    
    success = await update_library_item(
        license_id=license["license_id"],
        item_id=item_id,
        user_id=user_id,
        **data.dict(exclude_none=True)
    )
    if not success:
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ITEM_NOT_FOUND,
                "message_ar": "العنصر غير موجود",
                "message_en": "Item not found"
            }
        )
    return {"success": True}


@router.delete("/{item_id}")
async def delete_item(
    item_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Delete an item.
    
    Issue #25: Returns localized error codes.
    """
    user_id = user.get("user_id") if user else None
    success = await delete_library_item(license["license_id"], item_id, user_id=user_id)
    if not success:
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ITEM_NOT_FOUND,
                "message_ar": "العنصر غير موجود",
                "message_en": "Item not found"
            }
        )
    return {"success": True}


@router.post("/bulk-delete")
async def bulk_delete(
    data: BulkDeleteRequest,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Bulk delete items.

    Issue #7: Validates user ownership when user_id is provided.
    Issue #25: Returns localized error codes.
    P0-4: Returns detailed result with deleted and failed IDs.
    """
    user_id = user.get("user_id") if user else None

    # Filter valid IDs (prevent integer overflow)
    valid_ids = [id for id in data.item_ids if id <= 2147483647]
    if not valid_ids:
        return {"success": True, "deleted_count": 0, "deleted_ids": [], "failed_ids": []}

    try:
        # Issue #7: Pass user_id for ownership validation
        # P0-4: Now returns dict with detailed results
        result = await bulk_delete_items(license["license_id"], valid_ids, user_id=user_id)
        return {
            "success": True,
            "deleted_count": result["deleted_count"],
            "deleted_ids": result["deleted_ids"],
            "failed_ids": result.get("failed_ids", [])
        }
    except Exception as e:
        logger.error(f"Bulk delete failed: {e}")
        raise HTTPException(
            status_code=500,
            detail={
                "code": ErrorCode.INTERNAL_ERROR,
                "message_ar": "فشل الحذف الجماعي",
                "message_en": "Bulk delete failed"
            }
        )


@router.get("/{item_id}/download")
async def download_item(
    item_id: int,
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Download a library item file with proper access control.

    Issue #37: New endpoint for secure file downloads.
    FIX: Added download audit logging for compliance.
    ISSUE-001: Now tracks analytics in library_analytics table.
    """
    from fastapi.responses import FileResponse
    from models.library import get_library_item
    from models.library_advanced import track_item_access
    import os

    user_id = user.get("user_id") if user else None

    # Get the item with ownership validation
    item = await get_library_item(license["license_id"], item_id, user_id=user_id)

    if not item:
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ITEM_NOT_FOUND,
                "message_ar": "العنصر غير موجود",
                "message_en": "Item not found"
            }
        )

    # Only files can be downloaded (not notes)
    if item["type"] == "note":
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.INVALID_FILE_TYPE,
                "message_ar": "الملاحظات لا يمكن تحميلها",
                "message_en": "Notes cannot be downloaded"
            }
        )

    file_path = item.get("file_path")
    if not file_path:
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ITEM_NOT_FOUND,
                "message_ar": "الملف غير موجود",
                "message_en": "File not found"
            }
        )

    # Get the physical file path
    physical_path = file_storage.get_physical_path(file_path)

    if not os.path.exists(physical_path):
        logger.error(f"Physical file not found: {physical_path}")
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ITEM_NOT_FOUND,
                "message_ar": "الملف الفعلي غير موجود",
                "message_en": "Physical file not found"
            }
        )

    # FIX: Log download for audit trail
    try:
        from db_helper import execute_sql, get_db
        client_ip = request.client.host if request.client else "unknown"
        user_agent = request.headers.get("user-agent", "unknown")[:255]

        async with get_db() as db:
            await execute_sql(
                db,
                """
                INSERT INTO library_download_logs
                (item_id, license_key_id, user_id, downloaded_at, client_ip, user_agent)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP, ?, ?)
                """,
                [item_id, license["license_id"], user_id, client_ip, user_agent]
            )
            await commit_db(db)
    except Exception as e:
        # Don't fail the download if logging fails
        logger.warning(f"Failed to log download audit for item {item_id}: {e}")

    # ISSUE-001: Track download in analytics table
    try:
        client_ip = request.client.host if request.client else "unknown"
        user_agent = request.headers.get("user-agent", "unknown")[:255]
        
        await track_item_access(
            item_id=item_id,
            license_id=license["license_id"],
            user_id=user_id,
            action='download',
            client_ip=client_ip,
            user_agent=user_agent,
            metadata={
                'file_size': item.get('file_size'),
                'mime_type': item.get('mime_type'),
                'item_type': item.get('type')
            }
        )
    except Exception as e:
        # Don't fail download if analytics tracking fails
        logger.warning(f"Failed to track download analytics for item {item_id}: {e}")

    # Return file with proper headers
    response = FileResponse(
        path=physical_path,
        filename=item.get("title", "download"),
        media_type=item.get("mime_type", "application/octet-stream")
    )
    
    # SEC-001: Add Content Security Policy headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'"
    response.headers["X-Frame-Options"] = "DENY"
    
    return response


@router.get("/usage/statistics")
async def get_library_statistics(
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Get detailed library statistics including storage breakdown.
    
    Issue #38: New endpoint for library statistics.
    """
    user_id = user.get("user_id") if user else None
    
    # Get detailed storage usage
    storage_detail = await get_storage_usage_detailed(license["license_id"])
    
    # Get item counts by type
    async with get_db() as db:
        count_rows = await fetch_all(
            db,
            """
            SELECT type, COUNT(*) as count
            FROM library_items
            WHERE license_key_id = ? AND deleted_at IS NULL
            GROUP BY type
            """,
            [license["license_id"]]
        )

        # Get recent items (last 7 days)
        from datetime import timedelta
        from datetime import datetime, timezone
        seven_days_ago = datetime.now(timezone.utc) - timedelta(days=7)

        recent_count_row = await fetch_one(
            db,
            """
            SELECT COUNT(*) as count
            FROM library_items
            WHERE license_key_id = ? AND deleted_at IS NULL AND created_at >= ?
            """,
            [license["license_id"], seven_days_ago]
        )

    return {
        "success": True,
        "statistics": {
            "storage": storage_detail,
            "items_by_type": {row["type"]: row["count"] for row in count_rows},
            "recent_items_count": recent_count_row["count"] if recent_count_row else 0,
            "recent_period_days": 7
        }
    }


@router.get("/trash")
async def list_trash(
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    List soft-deleted items in the trash (recoverable).
    
    Issue #26: Trash feature - list deleted items.
    """
    from models.library import get_library_items
    
    user_id = user.get("user_id") if user else None
    
    # Get deleted items (including global items with license_key_id=0)
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT * FROM library_items 
            WHERE license_key_id = ? AND deleted_at IS NOT NULL
            ORDER BY deleted_at DESC
            LIMIT 100
            """,
            [license["license_id"]]
        )
        
        items = [dict(row) for row in rows]
    
    return {
        "success": True,
        "items": items,
        "auto_delete_days": 30  # Inform UI of auto-delete policy
    }


@router.post("/trash/{item_id}/restore")
async def restore_item(
    item_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Restore a soft-deleted item from the trash.
    
    Issue #26: Trash feature - restore deleted items.
    """
    user_id = user.get("user_id") if user else None
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Verify item exists and belongs to license
        item = await fetch_one(
            db,
            """
            SELECT * FROM library_items 
            WHERE id = ? AND license_key_id = ? AND deleted_at IS NOT NULL
            """,
            [item_id, license["license_id"]]
        )
        
        if not item:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": ErrorCode.ITEM_NOT_FOUND,
                    "message_ar": "العنصر غير موجود في سلة المهملات",
                    "message_en": "Item not found in trash"
                }
            )
        
        # Restore by clearing deleted_at
        await execute_sql(
            db,
            """
            UPDATE library_items 
            SET deleted_at = NULL, updated_at = ?
            WHERE id = ? AND license_key_id = ?
            """,
            [now, item_id, license["license_id"]]
        )
        await commit_db(db)
        
        # Invalidate storage cache
        await _invalidate_storage_cache(license["license_id"])
    
    return {"success": True, "message": "Item restored successfully"}


@router.post("/trash/{item_id}/delete-permanently")
async def delete_item_permanently(
    item_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Permanently delete an item from the trash (cannot be undone).
    
    Issue #26: Trash feature - permanent deletion.
    """
    user_id = user.get("user_id") if user else None
    
    async with get_db() as db:
        # Verify item exists and belongs to license
        item = await fetch_one(
            db,
            """
            SELECT file_path FROM library_items 
            WHERE id = ? AND license_key_id = ? AND deleted_at IS NOT NULL
            """,
            [item_id, license["license_id"]]
        )
        
        if not item:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": ErrorCode.ITEM_NOT_FOUND,
                    "message_ar": "العنصر غير موجود في سلة المهملات",
                    "message_en": "Item not found in trash"
                }
            )
        
        # Delete physical file if exists
        if item.get("file_path"):
            try:
                file_storage.delete_file(item["file_path"])
                logger.info(f"Permanently deleted physical file: {item['file_path']}")
            except Exception as e:
                logger.error(f"Failed to delete physical file: {e}")
        
        # Permanently delete from database
        await execute_sql(
            db,
            "DELETE FROM library_items WHERE id = ? AND license_key_id = ?",
            [item_id, license["license_id"]]
        )
        await commit_db(db)
        
        # Invalidate storage cache
        await _invalidate_storage_cache(license["license_id"])
    
    return {"success": True, "message": "Item permanently deleted"}


@router.post("/trash/empty")
async def empty_trash(
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Empty the entire trash (permanently delete all soft-deleted items).
    
    Issue #26: Trash feature - empty all trash.
    """
    user_id = user.get("user_id") if user else None
    
    async with get_db() as db:
        # Get all deleted items for this license
        items = await fetch_all(
            db,
            """
            SELECT id, file_path FROM library_items 
            WHERE license_key_id = ? AND deleted_at IS NOT NULL
            """,
            [license["license_id"]]
        )
        
        # Delete physical files
        for item in items:
            if item.get("file_path"):
                try:
                    file_storage.delete_file(item["file_path"])
                except Exception as e:
                    logger.error(f"Failed to delete physical file: {e}")
        
        # Permanently delete all from database
        await execute_sql(
            db,
            "DELETE FROM library_items WHERE license_key_id = ? AND deleted_at IS NOT NULL",
            [license["license_id"]]
        )
        await commit_db(db)
        
        # Invalidate storage cache
        await _invalidate_storage_cache(license["license_id"])
    
    return {"success": True, "message": "Trash emptied successfully"}
