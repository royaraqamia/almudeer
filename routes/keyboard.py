"""
Al-Mudeer - Keyboard API Routes
Endpoints for keyboard macros and optimized keyboard data
"""

import logging
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user_optional
from models.keyboard_macros import (
    get_keyboard_macros,
    get_keyboard_macro,
    create_keyboard_macro,
    update_keyboard_macro,
    delete_keyboard_macro,
    bulk_delete_keyboard_macros,
)
from security import sanitize_string
from rate_limiting import limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/keyboard", tags=["Keyboard"])


# ============ Request/Response Models ============

class MacroCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    content: str = Field(..., min_length=1, max_length=5000)


class MacroUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    content: Optional[str] = Field(None, min_length=1, max_length=5000)


class MacroResponse(BaseModel):
    id: int
    title: str
    content: str
    created_at: str
    updated_at: str


class MacrosListResponse(BaseModel):
    success: bool
    data: List[MacroResponse]
    total: int


# ============ Keyboard Macros Endpoints ============

@router.get("/macros", response_model=MacrosListResponse)
@limiter.limit("30/minute")
async def get_macros(
    request: Request,
    license_info=Depends(get_license_from_header),
    user_id: Optional[str] = Depends(get_current_user_optional),
    limit: int = Query(100, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """
    Get keyboard macros for the current license.
    Includes both user-specific and global macros.
    Optimized for keyboard usage with minimal data transfer.
    """
    try:
        license_id = license_info["id"]
        
        macros = get_keyboard_macros(
            license_id=license_id,
            user_id=user_id,
            limit=limit,
            offset=offset,
        )
        
        # Get total count for pagination
        from database import get_db_connection
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT COUNT(*) as count FROM keyboard_macros 
            WHERE (license_key_id = ? OR license_key_id = 0) 
            AND deleted_at IS NULL
            """,
            (license_id,),
        )
        total = cursor.fetchone()["count"]
        conn.close()
        
        return MacrosListResponse(
            success=True,
            data=[MacroResponse(**macro) for macro in macros],
            total=total,
        )
    except Exception as e:
        logger.error(f"Error getting keyboard macros: {e}")
        raise HTTPException(status_code=500, detail="Failed to get macros")


@router.post("/macros", response_model=MacroResponse)
@limiter.limit("20/minute")
async def create_macro(
    request: Request,
    macro_data: MacroCreate,
    license_info=Depends(get_license_from_header),
    user_id: Optional[str] = Depends(get_current_user_optional),
):
    """
    Create a new keyboard macro.
    Macros are synced across all devices for this license.
    """
    try:
        license_id = license_info["id"]
        
        # Sanitize inputs
        title = sanitize_string(macro_data.title)
        content = sanitize_string(macro_data.content)
        
        macro = create_keyboard_macro(
            license_id=license_id,
            title=title,
            content=content,
            user_id=user_id,
        )
        
        if not macro:
            raise HTTPException(status_code=500, detail="Failed to create macro")
        
        return MacroResponse(**macro)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating keyboard macro: {e}")
        raise HTTPException(status_code=500, detail="Failed to create macro")


@router.put("/macros/{macro_id}", response_model=MacroResponse)
@limiter.limit("20/minute")
async def update_macro(
    request: Request,
    macro_id: int,
    macro_data: MacroUpdate,
    license_info=Depends(get_license_from_header),
    user_id: Optional[str] = Depends(get_current_user_optional),
):
    """
    Update an existing keyboard macro.
    Only updates provided fields.
    """
    try:
        license_id = license_info["id"]
        
        # Sanitize inputs
        title = sanitize_string(macro_data.title) if macro_data.title else None
        content = sanitize_string(macro_data.content) if macro_data.content else None
        
        macro = update_keyboard_macro(
            license_id=license_id,
            macro_id=macro_id,
            title=title,
            content=content,
            user_id=user_id,
        )
        
        if not macro:
            raise HTTPException(status_code=404, detail="Macro not found")
        
        return MacroResponse(**macro)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating keyboard macro: {e}")
        raise HTTPException(status_code=500, detail="Failed to update macro")


@router.delete("/macros/{macro_id}")
@limiter.limit("20/minute")
async def delete_macro(
    request: Request,
    macro_id: int,
    license_info=Depends(get_license_from_header),
    user_id: Optional[str] = Depends(get_current_user_optional),
):
    """
    Delete a keyboard macro (soft delete).
    Macro will be removed from all synced devices.
    """
    try:
        license_id = license_info["id"]
        
        success = delete_keyboard_macro(
            license_id=license_id,
            macro_id=macro_id,
            user_id=user_id,
        )
        
        if not success:
            raise HTTPException(status_code=404, detail="Macro not found")
        
        return {"success": True, "message": "Macro deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting keyboard macro: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete macro")


@router.post("/macros/bulk-delete")
@limiter.limit("10/minute")
async def bulk_delete_macros(
    request: Request,
    macro_ids: List[int],
    license_info=Depends(get_license_from_header),
    user_id: Optional[str] = Depends(get_current_user_optional),
):
    """
    Bulk delete keyboard macros.
    Maximum 50 macros per request.
    """
    try:
        if len(macro_ids) > 50:
            raise HTTPException(
                status_code=400, 
                detail="Cannot delete more than 50 macros at once"
            )
        
        license_id = license_info["id"]
        
        deleted_count = bulk_delete_keyboard_macros(
            license_id=license_id,
            macro_ids=macro_ids,
            user_id=user_id,
        )
        
        return {
            "success": True, 
            "message": f"Deleted {deleted_count} macros",
            "deleted_count": deleted_count,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error bulk deleting keyboard macros: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete macros")


# ============ Keyboard-Optimized Library Endpoint ============

@router.get("/library")
@limiter.limit("60/minute")
async def get_keyboard_library(
    request: Request,
    license_info=Depends(get_license_from_header),
    user_id: Optional[str] = Depends(get_current_user_optional),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    query: Optional[str] = None,
):
    """
    Get library items optimized for keyboard usage.
    Returns minimal data needed for keyboard display.
    Supports search query parameter.
    """
    try:
        license_id = license_info["id"]

        from models.library import get_library_items

        # FIX: Added await - get_library_items is async
        items = await get_library_items(
            license_id=license_id,
            user_id=user_id,
            limit=limit,
            offset=offset,
            query=query,
        )
        
        # Return only essential fields for keyboard display
        simplified_items = [
            {
                "id": item["id"],
                "title": item["title"],
                "type": item["type"],
                "content_preview": item.get("content", "")[:200] if item.get("content") else None,
            }
            for item in items
        ]
        
        return {
            "success": True,
            "data": simplified_items,
            "total": len(items),
        }
    except Exception as e:
        logger.error(f"Error getting keyboard library: {e}")
        raise HTTPException(status_code=500, detail="Failed to get library items")


# ============ Sync Trigger Endpoint ============

@router.post("/sync/trigger")
@limiter.limit("10/minute")
async def trigger_sync(
    request: Request,
    license_info=Depends(get_license_from_header),
):
    """
    Trigger a sync to update keyboard cache.
    Called by main app when data changes.
    """
    try:
        license_id = license_info["id"]
        
        # In a full implementation, this would:
        # 1. Send push notification to keyboard service
        # 2. Update a sync timestamp in database
        # 3. Invalidate any server-side caches
        
        logger.info(f"Sync triggered for license {license_id}")
        
        return {
            "success": True,
            "message": "Sync triggered successfully",
            "timestamp": __import__('datetime').datetime.utcnow().isoformat(),
        }
    except Exception as e:
        logger.error(f"Error triggering sync: {e}")
        raise HTTPException(status_code=500, detail="Failed to trigger sync")
