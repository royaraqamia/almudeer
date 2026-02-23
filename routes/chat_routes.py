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
    status: Optional[str] = None,
    channel: Optional[str] = None,
    limit: int = 25,
    offset: int = 0,
    license: dict = Depends(get_license_from_header)
):
    conversations = await get_inbox_conversations(license["license_id"], status, channel, limit, offset)
    total = await get_inbox_conversations_count(license["license_id"], status, channel)
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
async def send_typing_indicator(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from services.websocket_manager import broadcast_typing_indicator, RedisPubSubManager
    data = await request.json()
    is_typing = data.get("is_typing", False)
    
    # [Senior Optimization] Persist in Redis for multi-device/multi-worker consistency
    redis_mgr = RedisPubSubManager()
    if await redis_mgr.initialize():
        key = f"typing:{license['license_id']}:{sender_contact}"
        if is_typing:
            await redis_mgr._redis_client.setex(key, 10, "1")
        else:
            await redis_mgr._redis_client.delete(key)

    await broadcast_typing_indicator(license["license_id"], sender_contact, is_typing)
    return {"success": True}

@router.post("/conversations/{sender_contact:path}/recording")
async def send_recording_indicator(
    sender_contact: str,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from services.websocket_manager import broadcast_recording_indicator, RedisPubSubManager
    data = await request.json()
    is_recording = data.get("is_recording", False)
    
    # [Senior Optimization] Persist in Redis
    redis_mgr = RedisPubSubManager()
    if await redis_mgr.initialize():
        key = f"recording:{license['license_id']}:{sender_contact}"
        if is_recording:
            await redis_mgr._redis_client.setex(key, 15, "1")
        else:
            await redis_mgr._redis_client.delete(key)

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
    
    # 1. Handle Multipart Files (The new standard)
    if files:
        from services.file_storage_service import get_file_storage
        storage = get_file_storage()
        for file in files:
            # We save to 'outbox' subfolder. These are NOT public yet.
            rel_path, _ = await storage.save_upload_file_async(
                file, 
                file.filename, 
                file.content_type, 
                subfolder="outbox"
            )
            processed_attachments.append({
                "type": "file",
                "local_path": rel_path, # Store the disk path
                "filename": file.filename,
                "mime_type": file.content_type
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
    from services.websocket_manager import broadcast_message_edited
    data = await request.json()
    new_body = data.get("body", "").strip()
    if not new_body: raise HTTPException(status_code=400, detail="النص فارغ")
    
    try:
        result = await edit_outbox_message(message_id, license["license_id"], new_body)
        await broadcast_message_edited(license["license_id"], message_id, new_body, result["edited_at"])
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
    from services.websocket_manager import broadcast_message_deleted
    try:
        result = await soft_delete_message(message_id, license["license_id"], msg_type=type)
        await broadcast_message_deleted(license["license_id"], message_id)
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

# --- Conversations Actions ---

@router.delete("/conversations/{sender_contact:path}/clear")
async def clear_conversation_route(
    sender_contact: str,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import clear_conversation_messages
    from services.websocket_manager import broadcast_chat_cleared
    
    result = await clear_conversation_messages(license["license_id"], sender_contact)
    # Broadcast event so UI updates instantly
    await broadcast_chat_cleared(license["license_id"], sender_contact)
    return result

@router.delete("/conversations/{sender_contact:path}")
async def delete_conversation_route(
    sender_contact: str,
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
async def delete_multiple_conversations_route(
    request: BatchDeleteRequest,
    license: dict = Depends(get_license_from_header)
):
    from models.inbox import soft_delete_conversation
    from services.websocket_manager import broadcast_conversation_deleted
    
    if not request.sender_contacts:
        raise HTTPException(status_code=400, detail="قائمة المحادثات فارغة")
        
    for contact in request.sender_contacts:
        await soft_delete_conversation(license["license_id"], contact)
        await broadcast_conversation_deleted(license["license_id"], contact)
        
    return {"success": True, "count": len(request.sender_contacts), "message": "تم حذف المحادثات بنجاح"}


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
    return {"success": True, "count": count}


# --- Internal Background Tasks Implementation (Original core_integrations.py logic) ---

    # AI analysis removed
    pass


async def send_approved_message(outbox_id: int, license_id: int):
    """
    Unified entry point for sending approved messages.
    Calls the centralized logic in workers.py to ensure 100% reliability
    and consistent handling of attachments, captions, and internal channels.
    """
    from workers import start_message_polling
    from logging_config import get_logger
    logger = get_logger(__name__)
    
    try:
        poller = await start_message_polling()
        # Find the message to get its channel
        from models import get_pending_outbox
        outbox = await get_pending_outbox(license_id)
        message = next((m for m in outbox if m["id"] == outbox_id), None)
        
        if not message:
            logger.error(f"Unified Send: Outbox message {outbox_id} not found for license {license_id}")
            return
            
        await poller._send_message(outbox_id, license_id, message["channel"])
    except Exception as e:
        logger.error(f"Unified Send: Critical failure for outbox {outbox_id}: {e}", exc_info=True)
