"""
Al-Mudeer - Chat Routes
Inbox management, conversation history, AI analysis, and message actions.
Modularized from legacy core_integrations.py
"""

import os
import re
import json
import base64
import tempfile
import asyncio
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Depends, Request, BackgroundTasks
from pydantic import BaseModel, Field
from models.task_queue import enqueue_task
from rate_limiting import limiter, RateLimits

from models import (
    get_inbox_messages,
    get_inbox_messages_count,
    get_inbox_conversations,
    get_inbox_conversations_count,
    get_inbox_status_counts,
    get_conversation_messages_cursor,
    get_full_chat_history,
    search_messages,
    update_inbox_status,
    create_outbox_message,
    approve_outbox_message,
    get_pending_outbox,
    get_pending_outbox,
    mark_outbox_sent,
    mark_outbox_failed,
    get_email_oauth_tokens,
    get_whatsapp_config,
    get_telegram_config,
    get_telegram_phone_session_data,
)
from services import (
    GmailOAuthService,
    GmailAPIService,
    TelegramService,
    TelegramPhoneService,
)
from services.whatsapp_service import WhatsAppService
# from agent import process_message (AI removed)
from dependencies import get_license_from_header

router = APIRouter(prefix="/api/integrations", tags=["Chat"])

# --- Schemas ---
class ApprovalRequest(BaseModel):
    action: str = Field(..., description="approve or ignore")
    edited_body: Optional[str] = None
    reply_to_platform_id: Optional[str] = None
    reply_to_body_preview: Optional[str] = None
    reply_to_sender_name: Optional[str] = None
    reply_to_id: Optional[int] = None

class ForwardRequest(BaseModel):
    target_channel: str
    target_contact: str

# --- Inbox Endpoints ---

@router.get("/inbox")
async def get_inbox_route(
    status: Optional[str] = None,
    channel: Optional[str] = None,
    limit: int = 25,
    offset: int = 0,
    license: dict = Depends(get_license_from_header)
):
    messages = await get_inbox_messages(license["license_id"], status, channel, limit, offset)
    total = await get_inbox_messages_count(license["license_id"], status, channel)
    return {"messages": messages, "total": total, "has_more": offset + len(messages) < total}

@router.get("/inbox/{message_id}")
async def get_inbox_message(
    message_id: int,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import get_inbox_message_by_id
    message = await get_inbox_message_by_id(message_id, license["license_id"])
    if not message:
        raise HTTPException(status_code=404, detail="الرسالة غير موجودة")
    return {"message": message}

# --- Conversations Endpoints ---

@router.get("/conversations")
async def get_conversations_route(
    limit: int = 25,
    offset: int = 0,
    license: dict = Depends(get_license_from_header)
):
    """
    Get all conversations in unified list - no filters.
    All chats appear together regardless of status or channel.
    """
    conversations = await get_inbox_conversations(license["license_id"], limit=limit, offset=offset)
    total = await get_inbox_conversations_count(license["license_id"])
    status_counts = await get_inbox_status_counts(license["license_id"])
    return {"conversations": conversations, "total": total, "status_counts": status_counts}

@router.get("/conversations/stats")
async def get_conversations_stats(
    license: dict = Depends(get_license_from_header)
):
    """Lightweight endpoint for fetching unread counts"""
    return await get_inbox_status_counts(license["license_id"])

@router.get("/conversations/search")
async def search_user_messages(
    query: str,
    sender_contact: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    license: dict = Depends(get_license_from_header)
):
    return await search_messages(license["license_id"], query, sender_contact, limit, offset)

@router.get("/conversations/{sender_contact:path}/search")
async def search_within_conversation(
    sender_contact: str,
    query: str,
    limit: int = 50,
    offset: int = 0,
    license: dict = Depends(get_license_from_header)
):
    """
    Search for messages within a specific conversation.
    Returns matching messages with context (previous/next messages).
    """
    from models.inbox import search_messages_in_conversation
    results = await search_messages_in_conversation(
        license["license_id"],
        sender_contact,
        query,
        limit,
        offset
    )
    return {
        "results": results,
        "total": len(results),
        "has_more": len(results) == limit,
        "sender_contact": sender_contact
    }

@router.get("/conversations/{sender_contact:path}/messages")
async def get_conversation_messages_paginated(
    sender_contact: str,
    cursor: Optional[str] = None,
    limit: int = 25,
    direction: str = "older",
    license: dict = Depends(get_license_from_header)
):
    limit = min(max(1, limit), 100)
    result = await get_conversation_messages_cursor(license["license_id"], sender_contact, limit, cursor, direction)
    return {**result, "sender_contact": sender_contact}

@router.get("/conversations/{sender_contact:path}")
async def get_conversation_detail(
    sender_contact: str,
    limit: int = 100,
    license: dict = Depends(get_license_from_header)
):
    from models.customers import get_customer_for_message
    messages = await get_full_chat_history(license["license_id"], sender_contact, limit)
    
    if not messages:
        # If no messages, return a skeleton response instead of 404 to avoid blocking UI for new chats
        return {
            "sender_name": "عميل",
            "sender_contact": sender_contact,
            "messages": [],
            "total": 0,
            "channel": "almudeer"
        }
    
    incoming_msgs = [m for m in messages if m.get("direction") == "incoming"]
    sender_name = incoming_msgs[0].get("sender_name", "عميل") if incoming_msgs else "عميل"
    
    return {
        "sender_name": sender_name,
        "sender_contact": sender_contact,
        "messages": messages,
        "total": len(messages)
    }

@router.post("/conversations/{sender_contact:path}/typing")
@limiter.limit(RateLimits.SEND_MESSAGE)  # Use SEND_MESSAGE rate limit (30/minute)
async def send_typing_indicator(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from services.websocket_manager import broadcast_typing_indicator
    from utils.redis_pool import get_redis_client

    data = await request.json()
    is_typing = data.get("is_typing", False)

    # P0-6: Use singleton Redis pool instead of creating new connection each time
    redis = await get_redis_client()
    if redis:
        key = f"typing:{license['license_id']}:{sender_contact}"
        if is_typing:
            # P2-10 FIX: Use EXPIRE to extend TTL on each typing event
            # This prevents typing indicator from disappearing while user is still typing
            await redis.set(key, "1")  # Set without TTL first
            await redis.expire(key, 10)  # Then set/extend TTL by 10 seconds
        else:
            await redis.delete(key)

    await broadcast_typing_indicator(license["license_id"], sender_contact, is_typing)
    return {"success": True}

@router.post("/conversations/{sender_contact:path}/recording")
@limiter.limit(RateLimits.SEND_MESSAGE)  # Use SEND_MESSAGE rate limit (30/minute)
async def send_recording_indicator(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from services.websocket_manager import broadcast_recording_indicator
    from utils.redis_pool import get_redis_client

    data = await request.json()
    is_recording = data.get("is_recording", False)

    # P0-6: Use singleton Redis pool
    redis = await get_redis_client()
    if redis:
        key = f"recording:{license['license_id']}:{sender_contact}"
        if is_recording:
            # P2-10 FIX: Use EXPIRE to extend TTL on each recording event
            await redis.set(key, "1")
            await redis.expire(key, 15)  # Extend TTL by 15 seconds
        else:
            await redis.delete(key)

    await broadcast_recording_indicator(license["license_id"], sender_contact, is_recording)
    return {"success": True}

from fastapi import Form, File, UploadFile
from typing import List

@router.post("/conversations/{sender_contact:path}/send")
async def send_chat_message(
    sender_contact: str,
    background_tasks: BackgroundTasks,
    message: Optional[str] = Form(None),
    channel: Optional[str] = Form(None),
    reply_to_platform_id: Optional[str] = Form(None),
    reply_to_body_preview: Optional[str] = Form(None),
    reply_to_sender_name: Optional[str] = Form(None),
    reply_to_id: Optional[int] = Form(None),
    is_forwarded: bool = Form(False),
    attachments: Optional[str] = Form(None), # For legacy Base64 or metadata
    files: Optional[List[UploadFile]] = File(None),
    license: dict = Depends(get_license_from_header)
):
    body = (message or "").strip()
    
    # Process Attachments
    processed_attachments = []

    # P0-3 FIX: Attachment validation constants
    MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB max file size
    ALLOWED_MIME_TYPES = {
        # Images
        'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
        # Videos
        'video/mp4', 'video/quicktime', 'video/x-msvideo', 'video/x-matroska',
        # Audio
        'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/wav', 'audio/webm',
        # Documents
        'application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'text/plain', 'text/csv', 'application/rtf',
        # Archives
        'application/zip', 'application/x-zip-compressed', 'application/x-rar-compressed', 'application/x-7z-compressed',
    }
    # Additional allowed extensions for MIME type inference
    ALLOWED_EXTENSIONS = {
        '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif',
        '.mp4', '.mov', '.avi', '.mkv', '.webm',
        '.mp3', '.m4a', '.aac', '.ogg', '.wav', '.flac', '.amr',
        '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
        '.txt', '.csv', '.rtf',
        '.zip', '.rar', '.7z', '.tar', '.gz'
    }

    # 1. Handle Multipart Files (The new standard)
    if files:
        from services.file_storage_service import get_file_storage
        storage = get_file_storage()
        
        for file in files:
            # P0-3 FIX: Validate file size
            file_size = 0
            content = await file.read()
            file_size = len(content)
            await file.seek(0)  # Reset file pointer
            
            if file_size > MAX_FILE_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail=f"حجم الملف كبير جداً. الحد الأقصى هو {MAX_FILE_SIZE // (1024 * 1024)} ميجابايت"
                )
            
            # P0-3 FIX: Validate MIME type
            mime_type = file.content_type or ''
            filename = file.filename or ''
            ext = '.' + filename.split('.')[-1].lower() if '.' in filename else ''
            
            # Check if MIME type is explicitly allowed
            is_allowed = mime_type.lower() in ALLOWED_MIME_TYPES
            
            # If MIME type is generic or missing, check extension
            if not is_allowed and ext:
                is_allowed = ext.lower() in ALLOWED_EXTENSIONS
            
            # Block dangerous file types regardless of extension
            dangerous_extensions = {'.exe', '.bat', '.cmd', '.scr', '.pif', '.js', '.vbs', '.sh', '.php', '.asp', '.aspx'}
            if ext.lower() in dangerous_extensions:
                raise HTTPException(
                    status_code=400,
                    detail="نوع الملف غير مسموح به لأسباب أمنية"
                )
            
            if not is_allowed:
                raise HTTPException(
                    status_code=400,
                    detail="نوع الملف غير مدعوم. الأنواع المدعومة: صور، فيديو، صوت، مستندات، وأرشيف"
                )
            
            # We save to 'outbox' subfolder. These are NOT public yet.
            rel_path, _ = await storage.save_upload_file_async(
                file,
                file.filename,
                mime_type,
                subfolder="outbox"
            )
            processed_attachments.append({
                "type": "file",
                "local_path": rel_path, # Store the disk path
                "filename": file.filename,
                "mime_type": mime_type,
                "file_size": file_size
            })
            
    # 2. Handle metadata/legacy attachments if provided as JSON string
    if attachments:
        try:
            extra_attachments = json.loads(attachments)
            if isinstance(extra_attachments, list):
                processed_attachments.extend(extra_attachments)
        except:
            pass

    if not body and not processed_attachments:
        raise HTTPException(status_code=400, detail="الرسالة فارغة")
    
    if not channel:
        if sender_contact == "__saved_messages__":
            channel = "saved"
        else:
            history = await get_full_chat_history(license["license_id"], sender_contact, limit=1)
            if not history: raise HTTPException(status_code=404, detail="المحادثة غير موجودة")
            channel = history[0].get("channel", "whatsapp")
    
    recipient_id = None
    if sender_contact == "__saved_messages__":
        recipient_id = "__saved_messages__"
    else:
        history = history if 'history' in locals() else await get_full_chat_history(license["license_id"], sender_contact, limit=1)
        if history:
            recipient_id = history[0].get("sender_id")
    
    outbox_id = await create_outbox_message(
        inbox_message_id=reply_to_id,
        license_id=license["license_id"],
        channel=channel,
        body=body,
        recipient_id=recipient_id,
        recipient_email=sender_contact,
        attachments=processed_attachments or None,
        reply_to_platform_id=reply_to_platform_id,
        reply_to_body_preview=reply_to_body_preview,
        reply_to_id=reply_to_id,
        reply_to_sender_name=reply_to_sender_name,
        is_forwarded=is_forwarded
    )
    
    # Standardize: pass license_id if needed, though approve_outbox_message fetches internally from outbox_id
    await approve_outbox_message(outbox_id, body)
    
    # Instant Send: Trigger Redis wake-up
    from services.websocket_manager import RedisPubSubManager
    trigger_mgr = RedisPubSubManager()
    if await trigger_mgr.initialize():
        await trigger_mgr.publish_outbox_trigger(license["license_id"])
        
    background_tasks.add_task(send_approved_message, outbox_id, license["license_id"])
    return {"success": True, "outbox_id": outbox_id, "id": outbox_id}

# --- Actions ---

@router.post("/inbox/{message_id}/approve")
async def approve_chat_message(
    message_id: int,
    approval: ApprovalRequest,
    background_tasks: BackgroundTasks,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import get_inbox_message_by_id, approve_chat_messages
    message = await get_inbox_message_by_id(message_id, license["license_id"])
    if not message: 
        from logging_config import get_logger
        get_logger(__name__).warning(f"Approve attempt for non-existent message: {message_id} (License ID: {license['license_id']})")
        raise HTTPException(status_code=404, detail="الرسالة غير موجودة")
    
    if approval.action == "approve":
        body = approval.edited_body or message.get("ai_draft_response")
        if not body: raise HTTPException(status_code=400, detail="لا يوجد رد للإرسال")
        
        outbox_id = await create_outbox_message(
            inbox_message_id=message_id,
            license_id=license["license_id"],
            channel=message["channel"],
            body=body,
            recipient_id=message.get("sender_id"),
            recipient_email=message.get("sender_contact"),
            reply_to_platform_id=approval.reply_to_platform_id or message.get("channel_message_id"),
            reply_to_body_preview=approval.reply_to_body_preview,
            reply_to_id=approval.reply_to_id or message_id,
            reply_to_sender_name=approval.reply_to_sender_name
        )
        await approve_outbox_message(outbox_id, body)
        await update_inbox_status(message_id, "approved")
        
        sender = message.get("sender_contact") or message.get("sender_id")
        if sender: await approve_chat_messages(license["license_id"], sender)
        
        background_tasks.add_task(send_approved_message, outbox_id, license["license_id"])
        
        # Instant Send: Trigger Redis wake-up
        from services.websocket_manager import RedisPubSubManager
        trigger_mgr = RedisPubSubManager()
        if await trigger_mgr.initialize():
            await trigger_mgr.publish_outbox_trigger(license["license_id"])
            
        return {"success": True, "message": "تم إرسال الرد"}

@router.post("/inbox/cleanup")
async def cleanup_inbox_status_route(license: dict = Depends(get_license_from_header)):
    from models.inbox import fix_stale_inbox_status
    count = await fix_stale_inbox_status(license["license_id"])
    return {"success": True, "message": "تم تنظيف المحادثات العالقة", "count": count}

@router.patch("/messages/{message_id}/edit")
async def edit_message_route(message_id: int, request: Request, license: dict = Depends(get_license_from_header)):
    from models.inbox import edit_outbox_message
    data = await request.json()
    new_body = data.get("body", "").strip()
    if not new_body: raise HTTPException(status_code=400, detail="النص فارغ")
    
    try:
        # edit_outbox_message already handles websocket broadcasting
        result = await edit_outbox_message(message_id, license["license_id"], new_body)
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.delete("/messages/{message_id}")
async def delete_message_route(
    message_id: int, 
    type: Optional[str] = None,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import soft_delete_message
    try:
        # soft_delete_message already handles websocket broadcasting
        result = await soft_delete_message(message_id, license["license_id"], msg_type=type)
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

# --- Conversations Actions ---

@router.delete("/conversations/{sender_contact:path}/clear")
@limiter.limit("5/minute")  # Rate limit to prevent mass deletion attacks
async def clear_conversation_route(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import clear_conversation_messages
    from services.websocket_manager import broadcast_chat_cleared

    result = await clear_conversation_messages(license["license_id"], sender_contact)
    # Broadcast event so UI updates instantly
    await broadcast_chat_cleared(license["license_id"], sender_contact)
    return result

@router.delete("/conversations/{sender_contact:path}")
@limiter.limit("5/minute")  # Rate limit to prevent mass deletion attacks
async def delete_conversation_route(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import soft_delete_conversation
    from services.websocket_manager import broadcast_conversation_deleted

    result = await soft_delete_conversation(license["license_id"], sender_contact)
    # Broadcast event so UI removes it instantly
    await broadcast_conversation_deleted(license["license_id"], sender_contact)
    return result

class BatchDeleteRequest(BaseModel):
    sender_contacts: List[str]

@router.delete("/conversations")
@limiter.limit("3/minute")  # Stricter limit for batch delete
async def delete_multiple_conversations_route(
    request: Request,
    batch_request: BatchDeleteRequest,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import soft_delete_conversation
    from services.websocket_manager import broadcast_conversation_deleted
    from db_helper import get_db, commit_db

    if not batch_request.sender_contacts:
        raise HTTPException(status_code=400, detail="قائمة المحادثات فارغة")

    # Limit batch size to prevent abuse
    if len(batch_request.sender_contacts) > 50:
        raise HTTPException(
            status_code=400,
            detail="الحد الأقصى لعدد المحادثات التي يمكن حذفها دفعة واحدة هو 50"
        )

    # P0-5: Wrap in database transaction for atomicity
    deleted_contacts = []
    try:
        async with get_db() as db:
            for contact in batch_request.sender_contacts:
                try:
                    await soft_delete_conversation(license["license_id"], contact, db=db)
                    deleted_contacts.append(contact)
                except Exception as e:
                    from logging_config import get_logger
                    get_logger(__name__).warning(f"Failed to delete conversation {contact}: {e}")
                    # Continue with other deletions - don't fail entire batch
            
            # Commit all deletions atomically
            await commit_db(db)
    except Exception as e:
        from logging_config import get_logger
        get_logger(__name__).error(f"Transaction failed for bulk delete: {e}")
        raise HTTPException(status_code=500, detail="فشل حذف المحادثات")

    # Broadcast deletions after successful commit
    for contact in deleted_contacts:
        await broadcast_conversation_deleted(license["license_id"], contact)

    return {"success": True, "count": len(deleted_contacts), "message": "تم حذف المحادثات بنجاح"}


@router.post("/inbox/{message_id}/read")
async def mark_message_as_read_route(message_id: int, license: dict = Depends(get_license_from_header)):
    from models.inbox import mark_message_as_read
    await mark_message_as_read(message_id, license["license_id"])
    return {"success": True}


@router.post("/conversations/{sender_contact:path}/read")
async def mark_conversation_read_route(
    sender_contact: str,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import mark_chat_read
    count = await mark_chat_read(license["license_id"], sender_contact)
    
    # P2-1: Broadcast read status to other devices
    from services.websocket_manager import get_websocket_manager, WebSocketMessage
    manager = get_websocket_manager()
    await manager.send_to_license(
        license["license_id"],
        WebSocketMessage(
            event="conversation_read",
            data={
                "sender_contact": sender_contact,
                "read_count": count,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
    )
    
    return {"success": True, "count": count}


# ============ Advanced Conversation Features ============

@router.get("/conversations/{sender_contact:path}/typing-status")
async def get_typing_status(
    sender_contact: str,
    license: dict = Depends(get_license_from_header)
):
    """P2-3: Get current typing/recording status for a conversation"""
    from utils.redis_pool import get_redis_client
    
    redis = await get_redis_client()
    is_typing = False
    is_recording = False
    
    if redis:
        typing_key = f"typing:{license['license_id']}:{sender_contact}"
        recording_key = f"recording:{license['license_id']}:{sender_contact}"
        
        is_typing = await redis.exists(typing_key)
        is_recording = await redis.exists(recording_key)
    
    return {
        "sender_contact": sender_contact,
        "is_typing": is_typing,
        "is_recording": is_recording
    }

@router.get("/conversations/{sender_contact:path}/draft")
async def get_draft(
    sender_contact: str,
    license: dict = Depends(get_license_from_header)
):
    """P2-6: Get saved draft for a conversation (synced across devices)"""
    from utils.redis_pool import get_redis_client

    redis = await get_redis_client()
    draft = ""
    updated_at = None
    expires_at = None
    ttl_seconds = None

    if redis:
        draft_key = f"draft:{license['license_id']}:{sender_contact}"
        draft = await redis.get(draft_key) or ""
        if draft:
            # Get TTL to know when it was last updated
            ttl = await redis.ttl(draft_key)
            if ttl > 0:
                from datetime import datetime, timedelta
                updated_at = (datetime.utcnow() + timedelta(seconds=ttl)).isoformat()
                expires_at = (datetime.utcnow() + timedelta(seconds=ttl)).isoformat()
                ttl_seconds = ttl

    return {
        "sender_contact": sender_contact,
        "draft": draft,
        "updated_at": updated_at,
        "expires_at": expires_at,  # P2-8 FIX: Include expiry time
        "ttl_seconds": ttl_seconds  # P2-8 FIX: Include remaining TTL
    }

@router.post("/conversations/{sender_contact:path}/draft")
async def save_draft(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    """P2-6: Save draft for a conversation (synced across devices)"""
    from utils.redis_pool import get_redis_client
    from services.websocket_manager import get_websocket_manager, WebSocketMessage

    data = await request.json()
    draft_text = data.get("draft", "")

    redis = await get_redis_client()
    if redis:
        draft_key = f"draft:{license['license_id']}:{sender_contact}"
        if draft_text.strip():
            # P2-8 FIX: Save with 7-day TTL and broadcast expiry info
            await redis.setex(draft_key, 604800, draft_text)
            
            # P2-8 FIX: Broadcast draft saved event with expiry info
            manager = get_websocket_manager()
            from datetime import datetime, timedelta
            expires_at = (datetime.utcnow() + timedelta(seconds=604800)).isoformat()
            await manager.send_to_license(
                license["license_id"],
                WebSocketMessage(
                    event="draft_saved",
                    data={
                        "sender_contact": sender_contact,
                        "draft": draft_text,
                        "expires_at": expires_at,
                        "ttl_seconds": 604800
                    }
                )
            )
        else:
            # Delete empty drafts
            await redis.delete(draft_key)
            
            # P2-8 FIX: Broadcast draft cleared event
            manager = get_websocket_manager()
            await manager.send_to_license(
                license["license_id"],
                WebSocketMessage(
                    event="draft_cleared",
                    data={
                        "sender_contact": sender_contact
                    }
                )
            )

    return {"success": True, "draft": draft_text}

@router.post("/conversations/{sender_contact:path}/archive")
async def archive_conversation(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    """Archive a conversation (hide without deleting)"""
    from models.inbox import archive_conversation as archive_conv
    data = await request.json()
    is_archived = data.get("is_archived", True)
    
    result = await archive_conv(license["license_id"], sender_contact, is_archived)
    return result


@router.post("/messages/{message_id}/pin")
async def pin_message(
    message_id: int,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    """Pin or unpin a message"""
    from models.inbox import pin_message as pin_msg
    data = await request.json()
    is_pinned = data.get("is_pinned", True)
    
    result = await pin_msg(message_id, license["license_id"], is_pinned)
    return result


@router.post("/conversations/{sender_contact:path}/forward")
async def forward_message(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    """Forward a message to another conversation or channel"""
    from models.inbox import forward_message as fwd_msg
    from pydantic import BaseModel
    
    class ForwardRequest(BaseModel):
        message_id: int
        target_contact: str
        target_channel: str
    
    data = await request.json()
    forward_req = ForwardRequest(**data)
    
    result = await fwd_msg(
        license["license_id"],
        forward_req.message_id,
        forward_req.target_contact,
        forward_req.target_channel
    )
    return result


# --- Internal Background Tasks Implementation (Original core_integrations.py logic) ---

    # AI analysis removed
    pass


async def send_approved_message(outbox_id: int, license_id: int):
    """
    Unified entry point for sending approved messages.
    Directly calls the appropriate channel service to send the message.
    """
    from models import get_pending_outbox, mark_outbox_sent, mark_outbox_failed, fetch_one, get_db
    from services.websocket_manager import broadcast_message_status_update
    from logging_config import get_logger
    from datetime import datetime, timezone
    
    logger = get_logger(__name__)

    try:
        # Get the outbox message details
        async with get_db() as db:
            message = await fetch_one(
                db,
                "SELECT * FROM outbox_messages WHERE id = ? AND license_key_id = ?",
                [outbox_id, license_id]
            )
        
        if not message:
            logger.error(f"Unified Send: Outbox message {outbox_id} not found for license {license_id}")
            return

        channel = message["channel"]
        body = message["body"] or ""
        recipient_id = message.get("recipient_id")
        recipient_email = message.get("recipient_email")
        subject = message.get("subject")
        attachments = message.get("attachments")
        reply_to_platform_id = message.get("reply_to_platform_id")
        
        # Parse attachments if stored as JSON string
        if isinstance(attachments, str):
            try:
                import json
                attachments = json.loads(attachments)
            except:
                attachments = None

        result = {"success": False, "error": "Unknown channel"}
        now = datetime.now(timezone.utc)

        # Send based on channel
        if channel == "whatsapp":
            config = await get_whatsapp_config(license_id)
            if not config or not config.get("access_token"):
                raise ValueError("WhatsApp not configured")
            
            service = WhatsAppService(
                phone_number_id=config["phone_number_id"],
                access_token=config["access_token"]
            )
            
            # WhatsApp uses phone number as recipient_id
            to_number = recipient_id or recipient_email
            result = await service.send_message(
                to=to_number,
                message=body,
                reply_to_message_id=reply_to_platform_id
            )

        elif channel == "telegram_bot":
            config = await get_telegram_config(license_id)
            if not config or not config.get("bot_token"):
                raise ValueError("Telegram Bot not configured")
            
            service = TelegramService(bot_token=config["bot_token"])
            
            # Telegram bot sends to chat_id
            chat_id = recipient_id or recipient_email
            result = await service.send_message(
                chat_id=chat_id,
                text=body,
                reply_to_message_id=int(reply_to_platform_id) if reply_to_platform_id and reply_to_platform_id.isdigit() else None
            )
            result = {"success": True, "message_id": str(result.get("message_id", ""))}

        elif channel == "telegram_phone":
            config = await get_telegram_phone_session_data(license_id)
            if not config or not config.get("session_string"):
                raise ValueError("Telegram Phone not configured")
            
            service = TelegramPhoneService()
            
            # Telegram phone uses recipient_id (user/chat ID)
            recipient = recipient_id or recipient_email
            result = await service.send_message(
                session_string=config["session_string"],
                recipient_id=recipient,
                text=body,
                reply_to_message_id=int(reply_to_platform_id) if reply_to_platform_id and reply_to_platform_id.isdigit() else None
            )
            result = {"success": True, "message_id": str(result.get("id", ""))}

        elif channel == "gmail":
            token_data = await get_email_oauth_tokens(license_id, "gmail")
            if not token_data or not token_data.get("access_token"):
                raise ValueError("Gmail not configured")
            
            service = GmailAPIService(
                access_token=token_data["access_token"],
                refresh_token=token_data.get("refresh_token")
            )
            
            # Gmail sends to email address
            to_email = recipient_email
            if not to_email:
                raise ValueError("No recipient email for Gmail message")
            
            result = await service.send_message(
                to_email=to_email,
                subject=subject or "(no subject)",
                body=body,
                reply_to_message_id=reply_to_platform_id,
                attachments=attachments
            )
            result = {"success": True, "message_id": result.get("id")}

        elif channel == "almudeer" or channel == "saved":
            # Internal Almudeer messages - save directly to inbox as the message appears to the same user
            from models.inbox import save_inbox_message
            
            # For internal/saved messages, the message is both sent and received by the same user
            # Save it to inbox so it appears in the conversation
            platform_msg_id = await save_inbox_message(
                license_id=license_id,
                channel="almudeer",
                sender_id=recipient_id or license_id,  # Use recipient or self
                sender_name=None,
                sender_contact=recipient_id or recipient_email,
                body=body,
                subject=None,
                attachments=attachments,
                platform_message_id=None,
                reply_to_platform_id=reply_to_platform_id
            )
            result = {"success": True, "message_id": str(platform_msg_id) if platform_msg_id else None}

        else:
            raise ValueError(f"Unsupported channel: {channel}")

        # Handle result
        if result.get("success"):
            await mark_outbox_sent(outbox_id, platform_message_id=result.get("message_id"))
            logger.info(f"Message {outbox_id} sent successfully via {channel}")
        else:
            error_msg = result.get("error", "Unknown error")
            await mark_outbox_failed(outbox_id, error_msg)
            logger.error(f"Message {outbox_id} failed to send via {channel}: {error_msg}")

    except Exception as e:
        logger.error(f"Unified Send: Critical failure for outbox {outbox_id}: {e}", exc_info=True)
        try:
            await mark_outbox_failed(outbox_id, str(e))
        except:
            pass
