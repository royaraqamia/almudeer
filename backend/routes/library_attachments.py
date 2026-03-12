"""
Al-Mudeer - Library Attachments API Routes
P3-12: Multiple attachments per library item
"""

import os
import logging
from datetime import datetime
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
from fastapi.responses import FileResponse

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user_optional
from models.library_attachments import (
    get_attachments,
    get_attachment,
    add_attachment,
    delete_attachment,
    get_attachment_storage_usage,
    MAX_ATTACHMENT_SIZE
)
from models.library import get_storage_usage
from db_helper import get_db, fetch_one
from services.file_storage_service import get_file_storage
from rate_limiting import limiter

logger = logging.getLogger(__name__)

# Error codes for standardized error responses
class ErrorCode:
    ITEM_NOT_FOUND = "ITEM_NOT_FOUND"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    STORAGE_LIMIT_EXCEEDED = "STORAGE_LIMIT_EXCEEDED"
    FILE_UPLOAD_FAILED = "FILE_UPLOAD_FAILED"
    ATTACHMENT_NOT_FOUND = "ATTACHMENT_NOT_FOUND"
    INTERNAL_ERROR = "INTERNAL_ERROR"

router = APIRouter(prefix="/api/library/items/{item_id}/attachments", tags=["Library Attachments"])
file_storage = get_file_storage()


@router.get("/")
@limiter.limit("60/minute")
async def list_attachments(
    item_id: int,
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Get all attachments for a library item"""
    # Verify parent item exists and belongs to license
    async with get_db() as db:
        item = await fetch_one(
            db,
            "SELECT id FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license["license_id"]]
        )
        
        if not item:
            raise HTTPException(404, detail="Library item not found")
    
    attachments = await get_attachments(item_id, license["license_id"])
    
    return {
        "success": True,
        "attachments": attachments,
        "count": len(attachments)
    }


@router.post("/")
@limiter.limit("20/minute")
async def upload_attachment(
    item_id: int,
    request: Request,
    file: UploadFile = File(...),
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Upload an attachment to a library item
    
    P1-4 FIX: Added filename sanitization to prevent path traversal attacks.
    """
    import re  # P1-4 FIX: For filename sanitization
    
    user_id = user.get("user_id") if user else None

    # Verify parent item exists
    async with get_db() as db:
        item = await fetch_one(
            db,
            "SELECT id FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license["license_id"]]
        )

        if not item:
            raise HTTPException(404, detail="Library item not found")

        # BUG-004 FIX: Verify user has permission to add attachments (edit/admin required)
        if user_id:
            # Check if user is the owner
            owner_check = await fetch_one(
                db,
                "SELECT created_by FROM library_items WHERE id = ? AND license_key_id = ?",
                [item_id, license["license_id"]]
            )
            
            if owner_check and owner_check.get("created_by") != user_id:
                # Not the owner - check share permission
                from models.library import verify_share_permission
                has_permission = await verify_share_permission(
                    db, item_id, user_id, license["license_id"], "edit"
                )
                if not has_permission:
                    raise HTTPException(
                        status_code=403,
                        detail={
                            "code": "FORBIDDEN",
                            "message_ar": "لا تملك صلاحية إضافة مرفقات لهذا العنصر",
                            "message_en": "You don't have permission to add attachments to this item"
                        }
                    )

    # P1-4 FIX: Sanitize filename to prevent path traversal attacks
    original_filename = file.filename or "attachment"
    # Remove path components (prevent ../../../etc/passwd)
    safe_filename = os.path.basename(original_filename)
    # Remove special characters that could cause issues
    safe_filename = re.sub(r'[^\w\-_.\u0600-\u06FF]', '_', safe_filename)  # Allow Arabic chars
    # Ensure filename is not empty after sanitization
    if not safe_filename or safe_filename == '_':
        safe_filename = f"attachment_{datetime.utcnow().timestamp()}"
    
    # Store sanitized filename back to file object
    file.filename = safe_filename

    # Get file size
    try:
        file.file.seek(0, 2)  # Seek to end
        file_size = file.file.tell()
        file.file.seek(0)  # Reset to beginning
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

    # Validate file size
    if file_size > MAX_ATTACHMENT_SIZE:
        raise HTTPException(
            400,
            detail={
                "code": "FILE_TOO_LARGE",
                "message_ar": f"حجم الملف كبير جداً (الحد الأقصى {MAX_ATTACHMENT_SIZE / 1024 / 1024}MB)",
                "message_en": f"File size exceeds maximum limit ({MAX_ATTACHMENT_SIZE / 1024 / 1024}MB)"
            }
        )

    # Check storage quota
    # FIX: Use combined storage calculation - attachments ARE part of library storage
    # The library_items table already includes attachment file_size via library_attachments
    # So we only need to check total storage usage once
    current_usage = await get_storage_usage(license["license_id"])

    from models.library import MAX_STORAGE_PER_LICENSE
    if current_usage + file_size > MAX_STORAGE_PER_LICENSE:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.STORAGE_LIMIT_EXCEEDED,
                "message_ar": "تجاوزت حد التخزين المسموح به",
                "message_en": "Storage limit exceeded"
            }
        )

    # Save file with sanitized filename
    try:
        # Compute file hash BEFORE saving to check for duplicates
        import hashlib
        await file.seek(0)
        hasher = hashlib.sha256()
        # Note: file.file is a SpooledTemporaryFile, not an async stream
        while True:
            chunk = file.file.read(8192)
            if not chunk:
                break
            hasher.update(chunk)
        file_hash = hasher.hexdigest()

        # Check for duplicate attachments BEFORE saving
        async with get_db() as db:
            existing = await fetch_one(
                db,
                """
                SELECT id, filename, file_path FROM library_attachments
                WHERE license_key_id = ? AND file_hash = ? AND deleted_at IS NULL
                """,
                [license["license_id"], file_hash]
            )
            if existing:
                logger.info(
                    f"Duplicate attachment detected: {file.filename} matches {existing['filename']} (ID: {existing['id']})"
                )
                # Return existing attachment instead of uploading duplicate
                return {
                    "success": True,
                    "attachment": dict(existing),
                    "is_duplicate": True,
                    "message": "Attachment already exists"
                }

        # Reset file pointer for saving
        await file.seek(0)

        relative_path, public_url = await file_storage.save_upload_file_async(
            upload_file=file,
            filename=safe_filename,  # P1-4 FIX: Use sanitized filename
            mime_type=file.content_type or "application/octet-stream",
            subfolder="library/attachments"
        )

        # Add to database with file_hash
        attachment = await add_attachment(
            license_id=license["license_id"],
            item_id=item_id,
            file_path=public_url,
            filename=file.filename or "attachment",
            file_size=file_size,
            mime_type=file.content_type or "application/octet-stream",
            file_hash=file_hash,
            created_by=user_id
        )
        
        # FIX: Invalidate storage cache after adding attachment
        from models.library import _invalidate_storage_cache
        await _invalidate_storage_cache(license["license_id"])
        
        return {
            "success": True,
            "attachment": attachment
        }
        
    except ValueError as e:
        raise HTTPException(
            status_code=400,
            detail={
                "code": ErrorCode.FILE_UPLOAD_FAILED,
                "message_ar": str(e),
                "message_en": str(e)
            }
        )
    except Exception as e:
        logger.error(f"Attachment upload failed: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": ErrorCode.INTERNAL_ERROR,
                "message_ar": "فشل رفع المرفق",
                "message_en": "Failed to upload attachment"
            }
        )


@router.get("/{attachment_id}")
@limiter.limit("60/minute")  # Rate limiting to prevent abuse
async def get_attachment_file(
    item_id: int,
    attachment_id: int,
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Get/download a specific attachment"""
    attachment = await get_attachment(attachment_id, license["license_id"])

    if not attachment:
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ATTACHMENT_NOT_FOUND,
                "message_ar": "المرفق غير موجود",
                "message_en": "Attachment not found"
            }
        )

    # Verify parent item
    async with get_db() as db:
        item = await fetch_one(
            db,
            "SELECT id FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license["license_id"]]
        )

        if not item:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": ErrorCode.ITEM_NOT_FOUND,
                    "message_ar": "العنصر غير موجود",
                    "message_en": "Library item not found"
                }
            )

    # Get physical path
    physical_path = file_storage.get_physical_path(attachment["file_path"])

    if not os.path.exists(physical_path):
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ITEM_NOT_FOUND,
                "message_ar": "الملف غير موجود",
                "message_en": "File not found"
            }
        )

    # FIX #14: Add Content-Disposition header to force download
    # This ensures browsers download the file instead of displaying it
    filename = attachment.get("filename", "attachment")
    
    return FileResponse(
        path=physical_path,
        filename=filename,
        media_type=attachment.get("mime_type", "application/octet-stream"),
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Content-Transfer-Encoding": "binary",
        }
    )


@router.delete("/{attachment_id}")
@limiter.limit("30/minute")  # Rate limiting to prevent abuse
async def delete_attachment_endpoint(
    item_id: int,
    attachment_id: int,
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Delete an attachment"""
    user_id = user.get("user_id") if user else None

    success = await delete_attachment(attachment_id, license["license_id"], user_id=user_id)

    if not success:
        raise HTTPException(
            status_code=404,
            detail={
                "code": ErrorCode.ATTACHMENT_NOT_FOUND,
                "message_ar": "المرفق غير موجود",
                "message_en": "Attachment not found"
            }
        )

    return {"success": True, "message": "Attachment deleted"}
