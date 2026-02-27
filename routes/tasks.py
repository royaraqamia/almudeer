from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks, Request, Form, File, UploadFile
import json
from typing import List, Optional
from datetime import datetime
from schemas.tasks import TaskCreate, TaskResponse, TaskUpdate, TaskCommentCreate, TaskCommentResponse
from models.tasks import get_tasks, create_task, update_task, delete_task, get_task, get_task_comments, add_task_comment
from dependencies import get_license_from_header
from services.jwt_auth import get_current_user
from errors import NotFoundError
from services.websocket_manager import broadcast_task_sync, broadcast_notification
from services.fcm_mobile_service import send_fcm_to_user
from rate_limiting import limiter, RateLimits
from pydantic import BaseModel
from constants.tasks import MAX_FILE_SIZE

router = APIRouter(prefix="/api/tasks", tags=["Tasks"])
 
async def notify_assignment(license_id: int, task_id: str, title: str, assignee: str, sender_name: str):
    """Send push notification to assignee"""
    import logging
    try:
        await send_fcm_to_user(
            license_id=license_id,
            user_id=assignee,
            title="مهمة جديدة مسندة إليك",
            body=f"قام {sender_name} بإسناد المهمة: {title}",
            data={
                "type": "task_assigned",
                "task_id": task_id,
            },
            link=f"/tasks/{task_id}"
        )
    except Exception as e:
        import traceback
        logging.error(f"Failed to send assignment notification to {assignee} for task {task_id}: {e}\n{traceback.format_exc()}")

@router.get("/collaborators", response_model=List[dict])
async def list_collaborators(
    user: dict = Depends(get_current_user)
):
    """Get all users sharing the same license key"""
    license_id = user["license_id"]
    from db_helper import get_db, fetch_all
    async with get_db() as db:
        rows = await fetch_all(db, "SELECT email, name, role FROM users WHERE license_key_id = ?", (license_id,))
        return [dict(row) for row in rows]

@router.get("/", response_model=List[TaskResponse])
async def list_tasks(
    since: Optional[datetime] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = 0,
    cursor: Optional[str] = None,  # Cursor for pagination
    user: dict = Depends(get_current_user)
):
    """Get tasks. Private tasks only visible to creator.
    
    Supports cursor-based pagination for better performance with large datasets.
    Use the 'created_at' of the last task as the cursor for next page.
    """
    tasks = await get_tasks(user["license_id"], user["user_id"], since=since, limit=limit, offset=offset, cursor=cursor)
    return tasks

@router.post("/", response_model=TaskResponse)
@limiter.limit(RateLimits.API)
async def create_new_task(
    request: Request,
    background_tasks: BackgroundTasks,
    task_json: str = Form(...),
    files: Optional[List[UploadFile]] = File(None),
    user: dict = Depends(get_current_user)
):
    """Create or sync a task (atomic upsert) with support for file attachments"""
    license_id = user["license_id"]

    try:
        data = json.loads(task_json)
        task = TaskCreate(**data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid task data: {str(e)}")

    # SECURITY: Sanitize text inputs
    from utils.sanitization import sanitize_title, sanitize_description, sanitize_rich_text
    task_dict = task.model_dump()
    task_dict['title'] = sanitize_title(task_dict.get('title', ''))
    if task_dict.get('description'):
        task_dict['description'] = sanitize_description(task_dict['description'])
    if task_dict.get('category'):
        from utils.sanitization import validate_category
        task_dict['category'] = validate_category(task_dict['category'])

    # Process Attachments
    processed_attachments = task.attachments or []
    if files:
        from services.file_storage_service import get_file_storage, validate_file_upload
        import uuid
        storage = get_file_storage()
        for file in files:
            # FIX SEC-003: Stream file with size limit to prevent memory exhaustion
            # Use centralized constant from constants/tasks.py
            file_content = b''
            chunk_size = 8192
            
            while True:
                chunk = await file.read(chunk_size)
                if not chunk:
                    break
                file_content += chunk
                # FIX: Check size early and reject immediately to save memory
                if len(file_content) > MAX_FILE_SIZE:
                    raise HTTPException(
                        status_code=400,
                        detail=f"File size exceeds maximum allowed ({MAX_FILE_SIZE // (1024*1024)}MB)"
                    )
            
            file_size = len(file_content)
            
            # FIX SEC-003: Validate file type using magic bytes, not just MIME
            mime_type = file.content_type or "application/octet-stream"
            is_valid, error_msg = validate_file_upload(
                filename=file.filename or "unnamed",
                mime_type=mime_type,
                file_size=file_size,
                file_type="image" if mime_type.startswith("image/") else "file"
            )
            
            if not is_valid:
                raise HTTPException(status_code=400, detail=f"File validation failed: {error_msg}")
            
            # FIX SEC-003: Validate magic bytes for images
            if mime_type.startswith("image/"):
                # Check PNG magic bytes
                if mime_type == "image/png" and not file_content.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise HTTPException(status_code=400, detail="Invalid PNG file (magic bytes mismatch)")
                # Check JPEG magic bytes
                elif mime_type == "image/jpeg" and not file_content.startswith(b'\xff\xd8\xff'):
                    raise HTTPException(status_code=400, detail="Invalid JPEG file (magic bytes mismatch)")
                # Check GIF magic bytes
                elif mime_type == "image/gif" and not file_content.startswith(b'GIF87a') and not file_content.startswith(b'GIF89a'):
                    raise HTTPException(status_code=400, detail="Invalid GIF file (magic bytes mismatch)")

            # Reset file pointer for saving
            from io import BytesIO
            file.file = BytesIO(file_content)

            # FIX SEC-003: Use UUID for stored filename to prevent any path traversal
            file_extension = file.filename.split('.')[-1] if '.' in (file.filename or '') else 'bin'
            secure_file_id = f"{uuid.uuid4().hex}.{file_extension}"

            rel_path, url = await storage.save_upload_file_async(
                file, secure_file_id, mime_type, subfolder="tasks"
            )
            processed_attachments.append({
                "url": url,
                "type": "file" if not mime_type.startswith("image/") else "image",
                "file_name": file.filename or "unnamed",  # Keep original for display
                "mime_type": mime_type,
                "file_size": file_size
            })
    
    # Set created_by if not present
    task_dict = task.model_dump()
    task_dict["attachments"] = processed_attachments
    if not task_dict.get("created_by"):
        task_dict["created_by"] = user["user_id"]
        
    try:
        result = await create_task(license_id, task_dict)
        if not result:
            raise HTTPException(status_code=500, detail="Failed to create/sync task")

        # Trigger real-time sync across other devices
        background_tasks.add_task(broadcast_task_sync, license_id, task_id=result["id"], change_type="create", target_user_id=user["user_id"])

        # If assigned, notify assignee
        if task_dict.get("assigned_to") and task_dict["assigned_to"] != user["user_id"]:
            background_tasks.add_task(
                notify_assignment,
                license_id,
                result["id"],
                result["title"],
                task_dict["assigned_to"],
                user.get("name") or user["user_id"]
            )

        return result
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        import logging
        logging.error(f"Task creation failed: {e}")
        
        # Sanitize error messages - don't expose internal details
        if "unique constraint" in str(e).lower():
            raise HTTPException(
                status_code=409,
                detail="تعذر إنشاء المهمة. يرجى المحاولة مرة أخرى."
            )
        
        raise HTTPException(
            status_code=500,
            detail="حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى."
        )

@router.put("/{task_id}", response_model=TaskResponse)
async def update_existing_task(
    task_id: str,
    background_tasks: BackgroundTasks,
    task_json: Optional[str] = Form(None),
    files: Optional[List[UploadFile]] = File(None),
    user: dict = Depends(get_current_user)
):
    """Update a task with optional file attachments"""
    license_id = user["license_id"]
    
    # Get current task (with visibility check)
    current_task = await get_task(license_id, task_id, user["user_id"])
    if not current_task:
        raise HTTPException(status_code=404, detail="Task not found")

    # RBAC: Check edit permissions
    from models.tasks import can_edit_task
    if not can_edit_task(current_task, user["user_id"]):
        raise HTTPException(
            status_code=403,
            detail="ليس لديك صلاحية تعديل هذه المهمة"
        )
        
    update_data = {}
    if task_json:
        try:
            update_data = json.loads(task_json)
            # Validate with TaskUpdate schema
            TaskUpdate(**update_data)
            
            # SECURITY: Sanitize text inputs
            from utils.sanitization import sanitize_title, sanitize_description, validate_category
            if 'title' in update_data and update_data['title']:
                update_data['title'] = sanitize_title(update_data['title'])
            if 'description' in update_data and update_data['description']:
                update_data['description'] = sanitize_description(update_data['description'])
            if 'category' in update_data and update_data['category']:
                update_data['category'] = validate_category(update_data['category'])
            
            # FIX: Handle attachment removal - extract removed URLs before processing
            removed_attachments = update_data.pop('removed_attachments', None)
            if removed_attachments and isinstance(removed_attachments, list):
                # Get current attachments (from DB if not in update_data)
                current_attachments = update_data.get("attachments", current_task.get("attachments", []))
                # Filter out removed URLs
                kept_attachments = [
                    att for att in current_attachments 
                    if att.get("url") not in removed_attachments
                ]
                update_data["attachments"] = kept_attachments
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid update data: {str(e)}")

    # Process New Files
    if files:
        from services.file_storage_service import get_file_storage
        import uuid
        storage = get_file_storage()
        processed_attachments = update_data.get("attachments", current_task.get("attachments", []))

        for file in files:
            # FIX SEC-003: Stream file with size limit - use centralized constant
            file_content = b''
            chunk_size = 8192
            
            while True:
                chunk = await file.read(chunk_size)
                if not chunk:
                    break
                file_content += chunk
                # Check size early to reject immediately
                if len(file_content) > MAX_FILE_SIZE:
                    raise HTTPException(
                        status_code=400,
                        detail=f"File size exceeds maximum allowed ({MAX_FILE_SIZE // (1024*1024)}MB)"
                    )
            
            file_size = len(file_content)
            mime_type = file.content_type or "application/octet-stream"
            
            # FIX SEC-003: Validate magic bytes for images
            if mime_type.startswith("image/"):
                if mime_type == "image/png" and not file_content.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise HTTPException(status_code=400, detail="Invalid PNG file")
                elif mime_type == "image/jpeg" and not file_content.startswith(b'\xff\xd8\xff'):
                    raise HTTPException(status_code=400, detail="Invalid JPEG file")
                elif mime_type == "image/gif" and not file_content.startswith(b'GIF87a') and not file_content.startswith(b'GIF89a'):
                    raise HTTPException(status_code=400, detail="Invalid GIF file")

            # FIX SEC-003: Use UUID for stored filename
            file_extension = file.filename.split('.')[-1] if '.' in (file.filename or '') else 'bin'
            secure_file_id = f"{uuid.uuid4().hex}.{file_extension}"

            from io import BytesIO
            file.file = BytesIO(file_content)
            
            rel_path, url = await storage.save_upload_file_async(
                file, secure_file_id, mime_type, subfolder="tasks"
            )
            processed_attachments.append({
                "url": url,
                "type": "file" if not mime_type.startswith("image/") else "image",
                "file_name": file.filename or "unnamed",
                "mime_type": mime_type,
                "file_size": file_size
            })
        update_data["attachments"] = processed_attachments
    result = await update_task(license_id, task_id, update_data)
    if not result:
        raise HTTPException(status_code=404, detail="Task not found")

    # P4-2: Send notification if visibility changed
    if update_data.get("visibility") and update_data["visibility"] != current_task.get("visibility"):
        from workers import create_task_visibility_changed_notification
        background_tasks.add_task(
            create_task_visibility_changed_notification,
            license_id,
            task_id,
            current_task.get("title", "Task"),
            user.get("name") or user["user_id"],
            current_task.get("assigned_to") or current_task.get("created_by"),
            update_data["visibility"]
        )

    # Trigger real-time sync across other devices
    background_tasks.add_task(broadcast_task_sync, license_id, task_id=task_id, change_type="update")
    
    # If assigned_to changed, notify new assignee
    if "assigned_to" in update_data:
        new_assignee = update_data["assigned_to"]
        old_assignee = current_task.get("assigned_to")
        
        if new_assignee and new_assignee != old_assignee and new_assignee != user["user_id"]:
            background_tasks.add_task(
                notify_assignment, 
                license_id, 
                task_id, 
                result["title"], 
                new_assignee,
                user.get("name") or user["user_id"]
            )
            
    # Handle Recurrence: If the task is being marked as completed and has a recurrence
    if update_data.get("is_completed") is True and current_task.get("is_completed") is False:
        if current_task.get("recurrence") and current_task.get("due_date"):
            # Calculate next due date
            import datetime as dt
            from dateutil.relativedelta import relativedelta
            from utils.timestamps import generate_stable_id

            old_due: dt.datetime = current_task["due_date"]
            if isinstance(old_due, str):
                old_due = dt.datetime.fromisoformat(old_due.replace('Z', '+00:00'))

            next_due = old_due
            rec = current_task["recurrence"].lower()
            if rec == "daily":
                next_due = old_due + relativedelta(days=1)
            elif rec == "weekly":
                next_due = old_due + relativedelta(weeks=1)
            elif rec == "monthly":
                # Handle month-end edge cases (e.g., Jan 31 -> Feb 28)
                next_due = old_due + relativedelta(months=1)
                # Preserve day if possible, otherwise use last day of month
                if next_due.day != old_due.day:
                    # Use the last day of the target month
                    next_due = next_due.replace(day=1) + relativedelta(days=-1)

            if next_due != old_due:
                # Spawn a cloned task for the next occurrence
                import uuid
                new_task_id = str(uuid.uuid4())

                # FIX BUG-001: Properly reset ALL subtasks to incomplete state
                def reset_subtask(subtask):
                    """Ensure subtask is a dict with is_completed=False"""
                    if isinstance(subtask, dict):
                        # Explicitly reset completion status - CRITICAL FIX
                        return {
                            "id": subtask.get("id", generate_stable_id(subtask.get("title", ""))),
                            "title": subtask.get("title", ""),
                            "is_completed": False  # ALWAYS reset to False
                        }
                    elif isinstance(subtask, str):
                        # Handle JSON string subtasks (edge case)
                        try:
                            import json
                            st_dict = json.loads(subtask)
                            return {
                                "id": st_dict.get("id", generate_stable_id(st_dict.get("title", ""))),
                                "title": st_dict.get("title", ""),
                                "is_completed": False  # ALWAYS reset to False
                            }
                        except:
                            stable_id = generate_stable_id(subtask)
                            return {"id": stable_id, "title": str(subtask), "is_completed": False}
                    else:
                        # Fallback for any other type
                        stable_id = generate_stable_id(str(subtask))
                        return {"id": stable_id, "title": str(subtask), "is_completed": False}

                # Clone parameters - FIX: preserve visibility
                cloned_task = {
                    "id": new_task_id,
                    "title": current_task["title"],
                    "description": current_task.get("description"),
                    "is_completed": False, # Explicitly reset
                    "due_date": next_due,
                    "priority": current_task.get("priority", "medium"),
                    "color": current_task.get("color"),
                    "sub_tasks": [
                        reset_subtask(st)
                        for st in current_task.get("sub_tasks", [])
                    ],
                    "alarm_enabled": current_task.get("alarm_enabled", False),
                    "alarm_time": None, # Reset alarm time for new occurrence
                    "recurrence": current_task.get("recurrence"),
                    "category": current_task.get("category"),
                    "order_index": current_task.get("order_index", 0.0),
                    "created_by": current_task.get("created_by"),
                    "assigned_to": current_task.get("assigned_to"),
                    "visibility": current_task.get("visibility", "shared"),  # FIX: preserve visibility
                }

                # Try to map alarm time if present
                if current_task.get("alarm_time"):
                    old_alarm = current_task["alarm_time"]
                    if isinstance(old_alarm, str):
                        old_alarm = dt.datetime.fromisoformat(old_alarm.replace('Z', '+00:00'))

                    if rec == "daily":
                        cloned_task["alarm_time"] = old_alarm + relativedelta(days=1)
                    elif rec == "weekly":
                        cloned_task["alarm_time"] = old_alarm + relativedelta(weeks=1)
                    elif rec == "monthly":
                        cloned_task["alarm_time"] = old_alarm + relativedelta(months=1)

                # Create the spawned task
                from models.tasks import create_task
                await create_task(license_id, cloned_task)

                # Broadcaster: Notify all clients to pull the newly spawned task
                background_tasks.add_task(broadcast_task_sync, license_id, task_id=new_task_id, change_type="create")
                
    return result

@router.delete("/{task_id}")
async def delete_existing_task(
    task_id: str,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """Delete a task"""
    license_id = user["license_id"]

    current_task = await get_task(license_id, task_id, user["user_id"])
    if not current_task:
        raise NotFoundError(resource="Task", resource_id=task_id)

    # RBAC: Only owners can delete tasks
    from models.tasks import can_delete_task
    if not can_delete_task(current_task, user["user_id"]):
        raise HTTPException(
            status_code=403,
            detail="ليس لديك صلاحية حذف هذه المهمة"
        )
        
    success = await delete_task(license_id, task_id)
    if not success:
        raise NotFoundError(resource="Task", resource_id=task_id)
    
    # Trigger real-time sync across other devices
    background_tasks.add_task(broadcast_task_sync, license_id, task_id=task_id, change_type="delete")
    
    return {"success": True}

@router.post("/{task_id}/comments", response_model=TaskCommentResponse)
@limiter.limit(RateLimits.API)
async def create_comment(
    task_id: str,
    request: Request,
    background_tasks: BackgroundTasks,
    comment_json: str = Form(...),
    files: Optional[List[UploadFile]] = File(None),
    user: dict = Depends(get_current_user)
):
    """Add a comment to a task with optional file attachments"""
    license_id = user["license_id"]

    try:
        data = json.loads(comment_json)
        comment = TaskCommentCreate(**data)
        
        # SECURITY: Sanitize comment content
        from utils.sanitization import sanitize_comment
        comment.content = sanitize_comment(comment.content)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid comment data: {str(e)}")

    # Check if task exists (with visibility check)
    task_obj = await get_task(license_id, task_id, user["user_id"])
    if not task_obj:
        raise HTTPException(status_code=404, detail="Task not found")

    # RBAC: Check comment permissions
    from models.tasks import can_comment_on_task
    if not can_comment_on_task(task_obj, user["user_id"]):
        raise HTTPException(
            status_code=403,
            detail="ليس لديك صلاحية التعليق على هذه المهمة"
        )

    # Process Attachments
    processed_attachments = comment.attachments or []
    if files:
        from services.file_storage_service import get_file_storage
        import uuid
        storage = get_file_storage()
        for file in files:
            # FIX SEC-003: Stream file with size limit - use centralized constant
            file_content = b''
            chunk_size = 8192
            
            while True:
                chunk = await file.read(chunk_size)
                if not chunk:
                    break
                file_content += chunk
                # Check size early to reject immediately
                if len(file_content) > MAX_FILE_SIZE:
                    raise HTTPException(
                        status_code=400,
                        detail=f"File size exceeds maximum allowed ({MAX_FILE_SIZE // (1024*1024)}MB)"
                    )
            
            file_size = len(file_content)
            mime_type = file.content_type or "application/octet-stream"
            
            # FIX SEC-003: Validate magic bytes for images
            if mime_type.startswith("image/"):
                if mime_type == "image/png" and not file_content.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise HTTPException(status_code=400, detail="Invalid PNG file")
                elif mime_type == "image/jpeg" and not file_content.startswith(b'\xff\xd8\xff'):
                    raise HTTPException(status_code=400, detail="Invalid JPEG file")
                elif mime_type == "image/gif" and not file_content.startswith(b'GIF87a') and not file_content.startswith(b'GIF89a'):
                    raise HTTPException(status_code=400, detail="Invalid GIF file")

            # FIX SEC-003: Use UUID for stored filename
            file_extension = file.filename.split('.')[-1] if '.' in (file.filename or '') else 'bin'
            secure_file_id = f"{uuid.uuid4().hex}.{file_extension}"
            
            from io import BytesIO
            file.file = BytesIO(file_content)

            rel_path, url = await storage.save_upload_file_async(
                file, secure_file_id, mime_type, subfolder="task_comments"
            )
            processed_attachments.append({
                "url": url,
                "type": "file" if not mime_type.startswith("image/") else "image",
                "file_name": file.filename or "unnamed",
                "mime_type": mime_type,
                "file_size": file_size
            })
        
    comment_data = {
        "user_id": user["user_id"],
        "user_name": user.get("name") or user["user_id"],
        "content": comment.content,
        "attachments": processed_attachments
    }
    
    result = await add_task_comment(license_id, task_id, comment_data)
    
    # Trigger real-time sync (comments fall under task_sync for now)
    background_tasks.add_task(broadcast_task_sync, license_id, task_id=task_id, change_type="comment")
    
    # If there's an assignee, notify them about the new comment
    if task_obj.get("assigned_to") and task_obj["assigned_to"] != user["user_id"]:
        background_tasks.add_task(
            broadcast_notification,
            license_id,
            {
                "type": "task_comment",
                "task_id": task_id,
                "title": "تعليق جديد",
                "body": f"{comment_data['user_name']}: {comment.content[:50]}...",
                "user_id": task_obj["assigned_to"]
            }
        )
        
    return result

@router.get("/{task_id}/comments", response_model=List[TaskCommentResponse])
async def list_comments(
    task_id: str,
    user: dict = Depends(get_current_user)
):
    """List comments for a task"""
    license_id = user["license_id"]
    
    # FIX: Check task visibility before returning comments
    task_obj = await get_task(license_id, task_id, user["user_id"])
    if not task_obj:
        raise HTTPException(status_code=404, detail="Task not found")
    
    return await get_task_comments(license_id, task_id)

@router.post("/{task_id}/typing")
async def send_typing_indicator(
    task_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Broadcast typing status for a task"""
    from services.websocket_manager import broadcast_task_typing_indicator
    license_id = user["license_id"]
    
    # FIX: Check task visibility before broadcasting typing indicator
    task_obj = await get_task(license_id, task_id, user["user_id"])
    if not task_obj:
        raise HTTPException(status_code=404, detail="Task not found")

    data = await request.json()
    is_typing = data.get("is_typing", False)

    await broadcast_task_typing_indicator(
        license_id=license_id,
        task_id=task_id,
        user_id=user["user_id"],
        user_name=user.get("name") or user["user_id"],
        is_typing=is_typing
    )
    return {"success": True}


# ============ Batch Operations ============

class BatchTaskUpdate(BaseModel):
    """Schema for batch task updates"""
    task_ids: List[str]
    updates: dict  # Fields to update (title, description, priority, category, assigned_to, etc.)


@router.post("/batch/update", response_model=List[TaskResponse])
@limiter.limit(RateLimits.API)
async def batch_update_tasks(
    request: Request,
    background_tasks: BackgroundTasks,
    batch_data: BatchTaskUpdate,
    user: dict = Depends(get_current_user)
):
    """
    Batch update multiple tasks at once.
    Useful for: bulk assign, bulk priority change, bulk category change, etc.
    
    FIX SEC-002: Added authorization logging and rate limiting.
    """
    import logging
    logger = logging.getLogger(__name__)
    
    license_id = user["license_id"]
    user_id = user["user_id"]
    updated_tasks = []
    skipped_tasks = []
    auth_failures = []

    for task_id in batch_data.task_ids:
        try:
            # Get current task (with visibility check)
            current_task = await get_task(license_id, task_id, user_id)
            if not current_task:
                skipped_tasks.append(task_id)
                continue  # Skip tasks user can't access

            # RBAC: Check edit permissions
            from models.tasks import can_edit_task
            if not can_edit_task(current_task, user_id):
                auth_failures.append(task_id)
                # FIX SEC-002: Log authorization failures for security monitoring
                logger.warning(
                    f"SECURITY: User {user_id} attempted to edit task {task_id} without permission",
                    extra={
                        "user_id": user_id,
                        "license_id": license_id,
                        "task_id": task_id,
                        "action": "batch_update_unauthorized"
                    }
                )
                continue

            # Update task
            updated_task = await update_task(license_id, task_id, batch_data.updates)
            if updated_task:
                updated_tasks.append(updated_task)

                # Broadcast sync event
                background_tasks.add_task(
                    broadcast_task_sync,
                    license_id,
                    task_id=task_id,
                    change_type="update"
                )
        except Exception as e:
            # Log error but continue with other tasks
            logger.error(f"Batch update failed for task {task_id}: {e}")

    # FIX SEC-002: Log batch operation summary
    logger.info(
        f"Batch update completed: {len(updated_tasks)} updated, {len(auth_failures)} auth failures, {len(skipped_tasks)} skipped",
        extra={
            "user_id": user_id,
            "license_id": license_id,
            "updated_count": len(updated_tasks),
            "auth_failures": len(auth_failures),
            "skipped_count": len(skipped_tasks)
        }
    )

    if not updated_tasks:
        raise HTTPException(status_code=400, detail="No tasks were updated")

    return updated_tasks


@router.post("/batch/delete")
@limiter.limit(RateLimits.API)
async def batch_delete_tasks(
    request: Request,
    background_tasks: BackgroundTasks,
    task_ids: List[str],
    user: dict = Depends(get_current_user)
):
    """
    Batch delete multiple tasks at once.
    Only owners can delete tasks.
    
    FIX SEC-002: Added authorization logging and rate limiting.
    """
    import logging
    logger = logging.getLogger(__name__)
    
    license_id = user["license_id"]
    user_id = user["user_id"]
    deleted_count = 0
    auth_failures = []
    skipped_tasks = []

    for task_id in task_ids:
        try:
            # Get current task (with visibility check)
            current_task = await get_task(license_id, task_id, user_id)
            if not current_task:
                skipped_tasks.append(task_id)
                continue  # Skip tasks user can't access

            # RBAC: Only owners can delete tasks
            from models.tasks import can_delete_task
            if not can_delete_task(current_task, user_id):
                auth_failures.append(task_id)
                # FIX SEC-002: Log authorization failures for security monitoring
                logger.warning(
                    f"SECURITY: User {user_id} attempted to delete task {task_id} without permission",
                    extra={
                        "user_id": user_id,
                        "license_id": license_id,
                        "task_id": task_id,
                        "action": "batch_delete_unauthorized"
                    }
                )
                continue

            # Delete task
            await delete_task(license_id, task_id)
            deleted_count += 1

            # Broadcast sync event
            background_tasks.add_task(
                broadcast_task_sync,
                license_id,
                task_id=task_id,
                change_type="delete"
            )
        except Exception as e:
            # Log error but continue with other tasks
            logger.error(f"Batch delete failed for task {task_id}: {e}")

    # FIX SEC-002: Log batch operation summary
    logger.info(
        f"Batch delete completed: {deleted_count} deleted, {len(auth_failures)} auth failures, {len(skipped_tasks)} skipped",
        extra={
            "user_id": user_id,
            "license_id": license_id,
            "deleted_count": deleted_count,
            "auth_failures": len(auth_failures),
            "skipped_count": len(skipped_tasks)
        }
    )

    # FIX: Return detailed info about partial successes/failures
    if deleted_count == 0:
        if auth_failures:
            raise HTTPException(
                status_code=403,
                detail={
                    "message": f"Permission denied for {len(auth_failures)} tasks",
                    "auth_failures": auth_failures,
                    "skipped_tasks": skipped_tasks
                }
            )
        raise HTTPException(
            status_code=400,
            detail={
                "message": "No tasks were deleted",
                "skipped_tasks": skipped_tasks
            }
        )

    # Return success with details about what happened
    return {
        "success": True,
        "deleted_count": deleted_count,
        "deleted_tasks": task_ids[:deleted_count] if deleted_count <= len(task_ids) else task_ids,
        "auth_failures": auth_failures,
        "skipped_tasks": skipped_tasks
    }


# ============ Analytics Endpoint ============

# FIX BACKEND-003: Simple in-memory cache for analytics
_analytics_cache: dict[str, tuple[dict, float]] = {}
_ANALYTICS_CACHE_TTL = 300  # 5 minutes cache

@router.get("/analytics")
async def get_task_analytics(
    user: dict = Depends(get_current_user)
):
    """
    Get task statistics without fetching all tasks.
    Efficient for users with many tasks.
    
    FIX BACKEND-003: Added caching to reduce database load.
    """
    import time
    from db_helper import get_db, fetch_one, fetch_all

    license_id = user["license_id"]
    user_id = user["user_id"]
    cache_key = f"{license_id}:{user_id}"
    
    # FIX BACKEND-003: Check cache first
    current_time = time.time()
    if cache_key in _analytics_cache:
        cached_data, cached_time = _analytics_cache[cache_key]
        if current_time - cached_time < _ANALYTICS_CACHE_TTL:
            return cached_data
    
    async with get_db() as db:
        # Total tasks (respecting visibility)
        total_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
        """, (license_id, user_id))

        # Completed tasks
        completed_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            AND is_completed = TRUE
        """, (license_id, user_id))

        # Active tasks
        active_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            AND is_completed = FALSE
        """, (license_id, user_id))

        # Overdue tasks (due date in past, not completed)
        overdue_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            AND is_completed = FALSE
            AND due_date IS NOT NULL
            AND due_date < CURRENT_TIMESTAMP
        """, (license_id, user_id))

        # Due today
        today_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            AND is_completed = FALSE
            AND due_date IS NOT NULL
            AND DATE(due_date) = DATE(CURRENT_TIMESTAMP)
        """, (license_id, user_id))

        # Due this week (7 days from now)
        week_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            AND is_completed = FALSE
            AND due_date IS NOT NULL
            AND due_date >= CURRENT_TIMESTAMP
            AND due_date <= datetime(CURRENT_TIMESTAMP, '+7 days')
        """, (license_id, user_id))

        # By category - use fetch_all for GROUP BY
        category_rows = await fetch_all(db, """
            SELECT category, COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            AND category IS NOT NULL
            GROUP BY category
        """, (license_id, user_id))

        # By priority - use fetch_all for GROUP BY
        priority_rows = await fetch_all(db, """
            SELECT priority, COUNT(*) as count FROM tasks
            WHERE license_key_id = ? AND (visibility = 'shared' OR created_by = ?)
            GROUP BY priority
        """, (license_id, user_id))

        # Build response
        analytics = {
            "total": total_row["count"] if total_row else 0,
            "completed": completed_row["count"] if completed_row else 0,
            "active": active_row["count"] if active_row else 0,
            "overdue": overdue_row["count"] if overdue_row else 0,
            "due_today": today_row["count"] if today_row else 0,
            "due_this_week": week_row["count"] if week_row else 0,
            "by_category": {row["category"]: row["count"] for row in (category_rows or [])},
            "by_priority": {row["priority"]: row["count"] for row in (priority_rows or [])}
        }
        
        # FIX BACKEND-003: Cache the result
        _analytics_cache[cache_key] = (analytics, current_time)
        
        # Cleanup old cache entries (keep last 100)
        if len(_analytics_cache) > 100:
            oldest_keys = sorted(_analytics_cache.keys(), key=lambda k: _analytics_cache[k][1])[:20]
            for key in oldest_keys:
                del _analytics_cache[key]

        return analytics


# ============ Search Endpoint ============

@router.get("/search")
@limiter.limit(RateLimits.API)  # FIX BACKEND-001: Add rate limiting to prevent abuse
async def search_tasks(
    q: str,
    limit: int = 50,
    offset: int = 0,
    user: dict = Depends(get_current_user),
    request: Request = None  # Required for rate limiting
):
    """
    Full-text search across tasks.
    Searches title and description fields.
    
    FIX BACKEND-001: Added rate limiting to prevent expensive query abuse.
    """
    from db_helper import get_db, fetch_all
    from models.tasks import _parse_task_row

    if not q or len(q.strip()) < 2:
        return []

    license_id = user["license_id"]
    user_id = user["user_id"]
    search_query = f"%{q.strip()}%"

    async with get_db() as db:
        # Use LIKE for cross-database compatibility
        # PostgreSQL could use ILIKE for case-insensitive, FTS for advanced
        rows = await fetch_all(db, """
            SELECT * FROM tasks
            WHERE license_key_id = ?
            AND (visibility = 'shared' OR created_by = ?)
            AND (
                title LIKE ? OR
                (description IS NOT NULL AND description LIKE ?) OR
                (category IS NOT NULL AND category LIKE ?)
            )
            ORDER BY
                CASE WHEN title LIKE ? THEN 0 ELSE 1 END,
                created_at DESC
            LIMIT ? OFFSET ?
        """, (license_id, user_id, search_query, search_query, search_query, search_query, limit, offset))
        
        return [_parse_task_row(dict(row)) for row in rows]

