"""
Al-Mudeer - Global Assets Management
Admin-only routes to manage tasks and library items for all users (license_id 0)

Fixes applied:
- Issue #12: Added audit trail (created_by tracking via admin key)
- Issue #29: Rate limiting on global routes
"""

from fastapi import APIRouter, HTTPException, Depends, Header, BackgroundTasks, Request
from pydantic import BaseModel, Field
from typing import Optional, List
import os
import uuid
import logging

from models.tasks import create_task, get_tasks, delete_task
from models.library import add_library_item, get_library_items, delete_library_item, update_library_item
from routes.notifications import verify_admin
from services.websocket_manager import broadcast_global_sync
from rate_limiting import limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin/global-assets", tags=["Admin - Global Assets"])

class GlobalTaskCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    priority: str = Field(default="medium")
    category: Optional[str] = None

class GlobalNoteCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    content: str = Field(..., min_length=1, max_length=5000)
    item_type: str = Field(default="note")


class GlobalNoteUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    content: Optional[str] = Field(None, min_length=1, max_length=5000)
    customer_id: Optional[int] = None


# Issue #29: Rate limiting for admin routes (stricter than API default)
ADMIN_RATE_LIMIT = "5/minute"  # Prevent accidental mass modifications


# --- Tasks ---

@router.get("/tasks")
async def list_global_tasks(_: None = Depends(verify_admin)):
    """List all global tasks (license_id 0)"""
    try:
        tasks = await get_tasks(0)
        return {"success": True, "tasks": tasks}
    except Exception as e:
        logger.error(f"Failed to list global tasks: {e}")
        raise HTTPException(status_code=500, detail="فشل جلب المهام العالمية")


@router.post("/tasks")
@limiter.limit(ADMIN_RATE_LIMIT)  # Issue #29: Rate limiting
async def add_global_task(
    request: Request,
    data: GlobalTaskCreate,
    background_tasks: BackgroundTasks,
    admin_key: str = Depends(verify_admin)
):
    """
    Add a global task visible to everyone (license_id 0)
    
    Issue #12: Tracks created_by via admin_key
    """
    try:
        task_data = data.model_dump()
        task_data["id"] = uuid.uuid4().hex
        # Issue #12: Add audit trail
        task_data["created_by"] = admin_key

        result = await create_task(0, task_data)

        # Trigger real-time sync across all clients
        background_tasks.add_task(broadcast_global_sync, "task_sync")

        return {"success": True, "task": result}
    except Exception as e:
        logger.error(f"Failed to create global task: {e}")
        raise HTTPException(status_code=500, detail="فشل إنشاء المهمة العالمية")


@router.delete("/tasks/{task_id}")
@limiter.limit(ADMIN_RATE_LIMIT)  # Issue #29: Rate limiting
async def remove_global_task(
    request: Request,
    task_id: str,
    background_tasks: BackgroundTasks,
    admin_key: str = Depends(verify_admin)
):
    """Delete a global task"""
    try:
        success = await delete_task(0, task_id)
        if not success:
            raise HTTPException(status_code=404, detail="المهمة غير موجودة")

        # Issue #12: Log deletion for audit
        logger.info(f"Global task {task_id} deleted by admin {admin_key}")

        # Trigger real-time sync across all clients
        background_tasks.add_task(broadcast_global_sync, "task_sync")

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete global task: {e}")
        raise HTTPException(status_code=500, detail="فشل حذف المهمة العالمية")


# --- Library Items / Notes ---

@router.get("/library")
async def list_global_library_items(_: None = Depends(verify_admin)):
    """List all global library items (license_id 0)"""
    try:
        items = await get_library_items(0)
        return {"success": True, "items": items}
    except Exception as e:
        logger.error(f"Failed to list global library items: {e}")
        raise HTTPException(status_code=500, detail="فشل جلب عناصر المكتبة العالمية")


@router.post("/library")
@limiter.limit(ADMIN_RATE_LIMIT)  # Issue #29: Rate limiting
async def add_global_library_item(
    request: Request,
    data: GlobalNoteCreate,
    background_tasks: BackgroundTasks,
    admin_key: str = Depends(verify_admin)
):
    """
    Add a global library item (note, link, etc.) visible to everyone
    
    Issue #12: Tracks created_by via admin_key
    """
    try:
        result = await add_library_item(
            license_id=0,
            item_type=data.item_type,
            title=data.title,
            content=data.content,
            user_id=f"admin:{admin_key}"  # Issue #12: Audit trail
        )

        # Trigger real-time sync across all clients
        background_tasks.add_task(broadcast_global_sync, "library_sync")

        return {"success": True, "item": result}
    except Exception as e:
        logger.error(f"Failed to create global library item: {e}")
        raise HTTPException(status_code=500, detail="فشل إنشاء عنصر المكتبة العالمي")


@router.delete("/library/{item_id}")
@limiter.limit(ADMIN_RATE_LIMIT)  # Issue #29: Rate limiting
async def remove_global_library_item(
    request: Request,
    item_id: int,
    background_tasks: BackgroundTasks,
    admin_key: str = Depends(verify_admin)
):
    """Delete a global library item"""
    try:
        success = await delete_library_item(0, item_id)
        if not success:
            raise HTTPException(status_code=404, detail="عنصر المكتبة غير موجود")

        # Issue #12: Log deletion for audit
        logger.info(f"Global library item {item_id} deleted by admin {admin_key}")

        # Trigger real-time sync across all clients
        background_tasks.add_task(broadcast_global_sync, "library_sync")

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete global library item: {e}")
        raise HTTPException(status_code=500, detail="فشل حذف عنصر المكتبة العالمي")


@router.put("/library/{item_id}")
@router.patch("/library/{item_id}")
@limiter.limit(ADMIN_RATE_LIMIT)  # Issue #29: Rate limiting
async def update_global_library_item(
    request: Request,
    item_id: int,
    data: GlobalNoteUpdate,
    background_tasks: BackgroundTasks,
    admin_key: str = Depends(verify_admin)
):
    """
    Update a global library item (note, link, etc.)

    Supports both PUT (full update) and PATCH (partial update).
    Only provided fields will be updated.

    Issue #12: Tracks updated_by via admin_key
    """
    try:
        # Build update data from provided fields only
        update_data = {}
        if data.title is not None:
            update_data['title'] = data.title
        if data.content is not None:
            update_data['content'] = data.content
        if data.customer_id is not None:
            update_data['customer_id'] = data.customer_id

        if not update_data:
            raise HTTPException(status_code=400, detail="لا توجد حقول للتحديث")

        # First verify the item exists
        existing_item = await get_library_items(0)
        item_exists = any(item['id'] == item_id for item in existing_item)
        
        if not item_exists:
            raise HTTPException(status_code=404, detail="عنصر المكتبة غير موجود")

        success = await update_library_item(
            license_id=0,
            item_id=item_id,
            user_id=f"admin:{admin_key}",  # Issue #12: Audit trail
            **update_data
        )

        if not success:
            raise HTTPException(status_code=500, detail="فشل تحديث عنصر المكتبة")

        # Issue #12: Log update for audit
        logger.info(f"Global library item {item_id} updated by admin {admin_key}")

        # Trigger real-time sync across all clients
        background_tasks.add_task(broadcast_global_sync, "library_sync")

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update global library item: {e}")
        raise HTTPException(status_code=500, detail="فشل تحديث عنصر المكتبة العالمي")
