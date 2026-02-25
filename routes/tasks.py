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
    user: dict = Depends(get_current_user)
):
    """Get tasks. Private tasks only visible to creator."""
    tasks = await get_tasks(user["license_id"], user["user_id"], since=since, limit=limit, offset=offset)
    return tasks

@router.post("/", response_model=TaskResponse)
async def create_new_task(
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

    # Process Attachments
    processed_attachments = task.attachments or []
    if files:
        from services.file_storage_service import get_file_storage
        storage = get_file_storage()
        for file in files:
            rel_path, url = await storage.save_upload_file_async(
                file, file.filename, file.content_type, subfolder="tasks"
            )
            processed_attachments.append({
                "url": url,
                "type": "file" if not file.content_type.startswith("image/") else "image",
                "file_name": file.filename,
                "mime_type": file.content_type
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
    except Exception as e:
        # If we get a unique constraint error, it might be a collision across licenses
        if "unique constraint" in str(e).lower() or "already exists" in str(e).lower():
            # Verify if it exists for another license
            from db_helper import get_db, fetch_one
            async with get_db() as db:
                global_check = await fetch_one(db, "SELECT license_key_id FROM tasks WHERE id = ?", (task.id,))
                if global_check and global_check["license_key_id"] != license_id:
                    raise HTTPException(
                        status_code=409, 
                        detail="Task ID already exists for a different account."
                    )
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

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
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid update data: {str(e)}")

    # Process New Files
    if files:
        from services.file_storage_service import get_file_storage
        storage = get_file_storage()
        processed_attachments = update_data.get("attachments", current_task.get("attachments", []))
        
        for file in files:
            rel_path, url = await storage.save_upload_file_async(
                file, file.filename, file.content_type, subfolder="tasks"
            )
            processed_attachments.append({
                "url": url,
                "type": "file" if not file.content_type.startswith("image/") else "image",
                "file_name": file.filename,
                "mime_type": file.content_type
            })
        update_data["attachments"] = processed_attachments
    result = await update_task(license_id, task_id, update_data)
    if not result:
        raise HTTPException(status_code=404, detail="Task not found")
    
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
                next_due = old_due + relativedelta(months=1)
                
            if next_due != old_due:
                # Spawn a cloned task for the next occurrence
                import uuid
                new_task_id = str(uuid.uuid4())

                # FIX: Properly reset all subtasks to incomplete state
                def reset_subtask(subtask):
                    """Ensure subtask is a dict with is_completed=False"""
                    if isinstance(subtask, dict):
                        return {**subtask, "is_completed": False}
                    elif isinstance(subtask, str):
                        # Handle JSON string subtasks (edge case)
                        try:
                            import json
                            st_dict = json.loads(subtask)
                            return {**st_dict, "is_completed": False}
                        except:
                            return {"id": str(uuid.uuid4()), "title": str(subtask), "is_completed": False}
                    else:
                        # Fallback for any other type
                        return {"id": str(uuid.uuid4()), "title": str(subtask), "is_completed": False}

                # Clone parameters
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
                    "alarm_time": None, # Needs calculation if using specific time, keep none for simplicity or copy
                    "recurrence": current_task.get("recurrence"),
                    "category": current_task.get("category"),
                    "order_index": current_task.get("order_index", 0.0),
                    "created_by": current_task.get("created_by"),
                    "assigned_to": current_task.get("assigned_to"),
                }
                
                # Try to map alarm time
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
async def create_comment(
    task_id: str,
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
        storage = get_file_storage()
        for file in files:
            rel_path, url = await storage.save_upload_file_async(
                file, file.filename, file.content_type, subfolder="task_comments"
            )
            processed_attachments.append({
                "url": url,
                "type": "file" if not file.content_type.startswith("image/") else "image",
                "file_name": file.filename,
                "mime_type": file.content_type
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
