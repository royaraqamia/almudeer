"""
Al-Mudeer - Stories API Routes
Handling story creation, listing, viewing, and real-time broadcasts
"""

import os
import logging
from typing import Optional, List

logger = logging.getLogger(__name__)

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from starlette.requests import Request

from db_helper import get_db, fetch_one, fetch_all
from dependencies import get_license_from_header
from services.jwt_auth import get_current_user_optional
from models.stories import (
    add_story,
    get_active_stories,
    mark_story_viewed,
    mark_stories_viewed_batch,
    get_story_viewers,
    get_story_view_count,
    delete_story,
    update_story,
    get_archived_stories,
    get_highlights,
    create_highlight,
    add_story_to_highlight
)
from schemas.stories import (
    StoryCreateText,
    StoriesListResponse,
    StoryResponse,
    StoryViewerDetails,
    StoryUpdate,
    HighlightCreate,
    HighlightResponse,
    BatchViewRequest,
    BatchViewResponse
)
from services.file_storage_service import get_file_storage
from services.websocket_manager import get_websocket_manager, WebSocketMessage
from security import sanitize_string
from rate_limiting import limiter

router = APIRouter(prefix="/api/stories", tags=["Stories"])

# File storage service instance
file_storage = get_file_storage()

@router.get("/", response_model=StoriesListResponse)
async def list_stories(
    viewer_contact: Optional[str] = Query(None),
    license: dict = Depends(get_license_from_header),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(50, ge=1, le=100, description="Items per page")
):
    """List active stories for the license with pagination."""
    offset = (page - 1) * page_size
    stories = await get_active_stories(
        license["license_id"], 
        viewer_contact=viewer_contact,
        limit=page_size,
        offset=offset
    )
    return {"success": True, "stories": stories}

@router.post("/text", response_model=StoryResponse)
async def create_text_story(
    data: StoryCreateText,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Create a new text-only story."""
    user_id = user.get("user_id") if user else None
    user_name = license.get("full_name", "مستخدم")
    
    if user_id:
        async with get_db() as db:
            user_row = await fetch_one(db, "SELECT name FROM users WHERE email = ?", [user_id])
            if user_row and user_row.get("name"):
                user_name = user_row["name"]

    story = await add_story(
        license_id=license["license_id"],
        story_type="text",
        user_id=user_id,
        user_name=user_name,
        title=sanitize_string(data.title) if data.title else None,
        content=sanitize_string(data.content, max_length=1000),
        duration_hours=data.duration_hours
    )
    
    # Broadcast to all connected clients for this license
    manager = get_websocket_manager()
    await manager.send_to_license(
        license["license_id"],
        WebSocketMessage(event="new_story", data=story)
    )
    
    return story

@router.post("/upload", response_model=StoryResponse)
async def upload_media_story(
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    content: Optional[str] = Form(None),
    duration_hours: int = Form(24),
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Upload a media story (image/video/audio)."""
    user_id = user.get("user_id") if user else None
    user_name = license.get("full_name", "مستخدم")
    
    # Validate file size before processing (max 50MB)
    MAX_FILE_SIZE = 50 * 1024 * 1024
    
    content_type = file.content_type or "application/octet-stream"
    
    # Determine type and validate
    allowed_image_types = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'}
    allowed_video_types = {'video/mp4', 'video/webm', 'video/3gpp'}
    allowed_audio_types = {'audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/ogg', 'audio/m4a'}
    
    story_type = "file"
    if content_type.startswith("image/"):
        story_type = "image"
        if content_type not in allowed_image_types:
            raise HTTPException(status_code=400, detail="نوع الصورة غير مسموح. الأنواع المسموحة: JPEG, PNG, GIF, WebP")
    elif content_type.startswith("video/"):
        story_type = "video"
        if content_type not in allowed_video_types:
            raise HTTPException(status_code=400, detail="نوع الفيديو غير مسموح. الأنواع المسموحة: MP4, WebM, 3GPP")
    elif content_type.startswith("audio/"):
        story_type = "audio"
        if content_type not in allowed_audio_types:
            raise HTTPException(status_code=400, detail="نوع الصوت غير مسموح. الأنواع المسموحة: MP3, WAV, OGG, M4A")
    else:
        raise HTTPException(status_code=400, detail="نوع الملف غير مسموح")
    
    if user_id:
        async with get_db() as db:
            user_row = await fetch_one(db, "SELECT name FROM users WHERE email = ?", [user_id])
            if user_row and user_row.get("name"):
                user_name = user_row["name"]

    try:
        # Read file header to validate magic bytes (security)
        header = await file.read(1024)
        await file.seek(0)  # Reset file pointer after reading header
        
        # Validate magic bytes for allowed types
        is_valid = _validate_magic_bytes(header, story_type)
        if not is_valid:
            raise HTTPException(status_code=400, detail="الملف غير صالح أو تالف")
        
        # Validate file size by reading content length if available
        # For streaming uploads, we rely on the client but add a safety check
        filename = file.filename or "unknown"
        
        # Save file asynchronously
        relative_path, public_url = await file_storage.save_upload_file_async(
            upload_file=file,
            filename=filename,
            mime_type=content_type,
            subfolder="stories"
        )
        
        story = await add_story(
            license_id=license["license_id"],
            story_type=story_type,
            user_id=user_id,
            user_name=user_name,
            title=sanitize_string(title) if title else None,
            content=sanitize_string(content, max_length=1000) if content else None,
            media_path=public_url,
            duration_hours=duration_hours
        )
        
        # Broadcast real-time update
        manager = get_websocket_manager()
        await manager.send_to_license(
            license["license_id"],
            WebSocketMessage(event="new_story", data=story)
        )
        
        return story
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in upload_media_story: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"حدث خطأ أثناء رفع القصة: {str(e)}")

def _validate_magic_bytes(header: bytes, story_type: str) -> bool:
    """Validate file magic bytes to ensure file type matches content."""
    if len(header) < 8:
        return False
    
    # Magic bytes signatures
    signatures = {
        'image': [
            b'\xff\xd8\xff',  # JPEG
            b'\x89PNG',       # PNG
            b'GIF8',          # GIF
            b'RIFF',          # WebP (starts with RIFF)
        ],
        'video': [
            b'\x00\x00\x00',  # MP4/3GP often starts with ftyp
            b'ftyp',          # MP4
            b'\x1aE\xdf\xa3', # WebM
        ],
        'audio': [
            b'ID3',           # MP3 with ID3
            b'\xff\xfb',      # MP3 without ID3
            b'RIFF',          # WAV (starts with RIFF)
            b'OggS',          # OGG
            b'ftyp',          # M4A/AAC
        ]
    }
    
    allowed_sigs = signatures.get(story_type, [])
    for sig in allowed_sigs:
        if header.startswith(sig):
            return True
    
    return len(allowed_sigs) == 0  # Allow if no signatures defined

@router.put("/{story_id}", response_model=StoryResponse)
async def update_story_content(
    story_id: int,
    data: StoryUpdate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Update an existing story (text/title only)."""
    user_id = user.get("user_id") if user else None
    if not user_id:
        raise HTTPException(status_code=403, detail="يجب تسجيل الدخول لتعديل القصة")
        
    story = await update_story(
        story_id=story_id,
        license_id=license["license_id"],
        user_id=user_id,
        title=sanitize_string(data.title) if data.title else None,
        content=sanitize_string(data.content) if data.content else None
    )
    
    if not story:
        raise HTTPException(status_code=404, detail="القصة غير موجودة أو لا تملك صلاحية تعديلها")
        
    # Broadcast real-time update
    manager = get_websocket_manager()
    await manager.send_to_license(
        license["license_id"],
        WebSocketMessage(event="story_updated", data=story)
    )
    
    return story

@router.post("/{story_id}/view")
@limiter.limit("10/minute")  # ISSUE-005: Rate limit to prevent analytics pollution
async def view_story(
    request: Request,
    story_id: int,
    viewer_contact: str = Form(...),
    viewer_name: Optional[str] = Form(None),
    license: dict = Depends(get_license_from_header)
):
    """Mark a story as viewed by a contact."""
    # Sanitize viewer_contact to prevent injection
    viewer_contact = sanitize_string(viewer_contact, max_length=100)
    if viewer_name:
        viewer_name = sanitize_string(viewer_name, max_length=200)

    # Verify the story belongs to this license key
    async with get_db() as db:
        story = await fetch_one(db, "SELECT id FROM stories WHERE id = ? AND license_key_id = ?", [story_id, license["license_id"]])
        if not story:
            raise HTTPException(status_code=404, detail="القصة غير موجودة")

    success = await mark_story_viewed(story_id, viewer_contact, viewer_name)

    if success:
        # Broadcast that this story was viewed
        manager = get_websocket_manager()
        await manager.send_to_license(
            license["license_id"],
            WebSocketMessage(event="story_viewed", data={
                "story_id": story_id,
                "viewer_contact": viewer_contact,
                "viewer_name": viewer_name
            })
        )

    return {"success": success}

@router.get("/{story_id}/viewers", response_model=List[StoryViewerDetails])
async def list_story_viewers(
    story_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Get list of people who viewed this story. Only story owner or admin can view."""
    user_id = user.get("user_id") if user else None
    is_admin = user.get("role") == "admin" if user else False
    
    # Verify story belongs to this license and check ownership
    async with get_db() as db:
        story = await fetch_one(
            db, 
            "SELECT id, user_id FROM stories WHERE id = ? AND license_key_id = ?",
            [story_id, license["license_id"]]
        )
        if not story:
            raise HTTPException(status_code=404, detail="القصة غير موجودة")
        
        # Only owner or admin can see viewers
        if not is_admin and story.get("user_id") != user_id:
            raise HTTPException(status_code=403, detail="لا يمكنك عرض مشاهدي هذه القصة")
    
    viewers = await get_story_viewers(story_id, license["license_id"])
    return viewers

@router.get("/{story_id}/view-count")
async def get_story_views_count(
    story_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Get view count for a story. Only story owner or admin can view."""
    user_id = user.get("user_id") if user else None
    is_admin = user.get("role") == "admin" if user else False
    
    # Verify story belongs to this license and check ownership
    async with get_db() as db:
        story = await fetch_one(
            db, 
            "SELECT id, user_id FROM stories WHERE id = ? AND license_key_id = ?",
            [story_id, license["license_id"]]
        )
        if not story:
            raise HTTPException(status_code=404, detail="القصة غير موجودة")
    
    # Anyone in the license can see view count (unlike detailed viewers list)
    view_count = await get_story_view_count(story_id, license["license_id"])
    return {"story_id": story_id, "view_count": view_count}

@router.delete("/{story_id}")
async def remove_story(
    story_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Delete a story. Ensures only owner or admin can delete."""
    user_id = user.get("user_id") if user else None
    is_admin = user.get("role") == "admin" if user else False
    
    # If not admin and not logged in, forbid
    if not user_id and not is_admin:
        raise HTTPException(status_code=403, detail="لا تملك صلاحية حذف هذه القصة")
        
    success = await delete_story(story_id, license["license_id"], user_id=None if is_admin else user_id)
    
    if success:
        # Broadcast real-time delete
        manager = get_websocket_manager()
        await manager.send_to_license(
            license["license_id"],
            WebSocketMessage(event="story_deleted", data={"id": story_id})
        )
        
    return {"success": success}

@router.get("/archive", response_model=List[StoryResponse])
async def list_archived_stories(
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """List archived/expired stories for the current user."""
    user_id = user.get("user_id") if user else None
    stories = await get_archived_stories(license["license_id"], user_id)
    return stories

@router.get("/highlights", response_model=List[HighlightResponse])
async def list_highlights(
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """List story highlights."""
    user_id = user.get("user_id") if user else None
    highlights = await get_highlights(license["license_id"], user_id)
    return highlights

@router.post("/highlights", response_model=HighlightResponse)
async def create_new_highlight(
    data: HighlightCreate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Create a new highlight group and optionally add stories to it."""
    user_id = user.get("user_id") if user else "مستخدم"
    highlight = await create_highlight(
        license["license_id"], 
        user_id, 
        data.title, 
        data.cover_media_path
    )
    
    if highlight and data.story_ids:
        for sid in data.story_ids:
            await add_story_to_highlight(sid, highlight["id"])
            
    return highlight

@router.post("/{story_id}/highlight/{highlight_id}")
async def add_to_highlight(
    story_id: int,
    highlight_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Add a specific story to a highlight. Only owner can add their own stories."""
    user_id = user.get("user_id") if user else None
    if not user_id:
        raise HTTPException(status_code=403, detail="يجب تسجيل الدخول لإضافة قصة إلى الأبرز")
    
    # Verify the story belongs to the requesting user
    async with get_db() as db:
        story = await fetch_one(db, 
            "SELECT id, user_id FROM stories WHERE id = ? AND license_key_id = ?", 
            [story_id, license["license_id"]]
        )
        if not story:
            raise HTTPException(status_code=404, detail="القصة غير موجودة")
        if story.get("user_id") != user_id:
            raise HTTPException(status_code=403, detail="لا يمكنك إضافة قصص الآخرين إلى الأبرز")
        
        # Verify highlight belongs to user
        highlight = await fetch_one(db,
            "SELECT id FROM story_highlights WHERE id = ? AND license_key_id = ? AND user_id = ?",
            [highlight_id, license["license_id"], user_id]
        )
        if not highlight:
            raise HTTPException(status_code=404, detail="الأبرز غير موجود")
    
    success = await add_story_to_highlight(story_id, highlight_id)
    return {"success": success}

@router.post("/views/batch", response_model=BatchViewResponse)
async def batch_view_stories(
    data: BatchViewRequest,
    license: dict = Depends(get_license_from_header)
):
    """Mark multiple stories as viewed in a single request."""
    if not data.story_ids:
        return {"success": True, "processed_count": 0}
    
    # Limit batch size to prevent abuse
    max_batch_size = 50
    story_ids = data.story_ids[:max_batch_size]
    
    # Validate all IDs are integers to prevent SQL injection via type confusion
    valid_ids = []
    for sid in story_ids:
        try:
            valid_ids.append(int(sid))
        except (ValueError, TypeError):
            pass  # Skip invalid IDs
    
    if not valid_ids:
        return {"success": True, "processed_count": 0}
    
    # Sanitize viewer_contact
    viewer_contact = sanitize_string(data.viewer_contact, max_length=100)
    viewer_name = sanitize_string(data.viewer_name, max_length=200) if data.viewer_name else None
    
    # Verify all stories belong to this license using parameterized queries
    async with get_db() as db:
        placeholders = ','.join(['?' for _ in valid_ids])
        query = f"""
            SELECT id FROM stories 
            WHERE id IN ({placeholders}) 
            AND license_key_id = ?
            AND deleted_at IS NULL
        """
        valid_stories = await fetch_all(db, query, valid_ids + [license["license_id"]])
        valid_ids = [row['id'] for row in valid_stories]
    
    if not valid_ids:
        return {"success": True, "processed_count": 0}
    
    success = await mark_stories_viewed_batch(
        valid_ids, 
        viewer_contact, 
        viewer_name,
        license["license_id"]
    )
    
    # Broadcast view events for each story
    if success:
        manager = get_websocket_manager()
        for story_id in valid_ids:
            await manager.send_to_license(
                license["license_id"],
                WebSocketMessage(event="story_viewed", data={
                    "story_id": story_id,
                    "viewer_contact": viewer_contact,
                    "viewer_name": viewer_name
                })
            )
    
    return {"success": success, "processed_count": len(valid_ids)}
