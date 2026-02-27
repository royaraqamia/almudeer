"""
Al-Mudeer - Library Attachments API Routes
P3-12: Multiple attachments per library item
"""

import os
import logging
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
    """Upload an attachment to a library item"""
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
    
    # Get file size
    try:
        await file.seek(0, 2)
        file_size = file.tell()
        await file.seek(0)
    except Exception as e:
        logger.error(f"Failed to get file size: {e}")
        raise HTTPException(400, detail="Failed to read file size")
    
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
        raise HTTPException(400, detail="Storage limit exceeded")
    
    # Save file
    try:
        relative_path, public_url = await file_storage.save_upload_file_async(
            upload_file=file,
            filename=file.filename,
            mime_type=file.content_type or "application/octet-stream",
            subfolder="library/attachments"
        )
        
        # Compute file hash
        import hashlib
        await file.seek(0)
        hasher = hashlib.sha256()
        async for chunk in file.file.iter_chunks(8192):
            hasher.update(chunk)
        file_hash = hasher.hexdigest()
        
        # Add to database
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
        raise HTTPException(400, detail=str(e))
    except Exception as e:
        logger.error(f"Attachment upload failed: {e}", exc_info=True)
        raise HTTPException(500, detail="Failed to upload attachment")


@router.get("/{attachment_id}")
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
        raise HTTPException(404, detail="Attachment not found")
    
    # Verify parent item
    async with get_db() as db:
        item = await fetch_one(
            db,
            "SELECT id FROM library_items WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL",
            [item_id, license["license_id"]]
        )
        
        if not item:
            raise HTTPException(404, detail="Library item not found")
    
    # Get physical path
    physical_path = file_storage.get_physical_path(attachment["file_path"])
    
    if not os.path.exists(physical_path):
        raise HTTPException(404, detail="File not found")
    
    return FileResponse(
        path=physical_path,
        filename=attachment.get("filename", "attachment"),
        media_type=attachment.get("mime_type", "application/octet-stream")
    )


@router.delete("/{attachment_id}")
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
        raise HTTPException(404, detail="Attachment not found")
    
    return {"success": True, "message": "Attachment deleted"}
