"""
Al-Mudeer - Message Sender Service

Unified service for sending messages through all supported channels:
- WhatsApp
- Telegram (Bot & Phone)
- Gmail
- Almudeer (internal)

This module extracts the sending logic from chat_routes.py to avoid
circular dependencies and allow reuse by background services.
"""

import logging
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

from logging_config import get_logger

logger = get_logger(__name__)


async def send_outbox_message(outbox_id: int, license_id: int) -> Dict[str, Any]:
    """
    Send an outbox message through the appropriate channel.
    
    This is the unified entry point for sending approved messages.
    Directly calls the appropriate channel service to send the message.
    
    Args:
        outbox_id: The outbox message ID
        license_id: The license key ID
        
    Returns:
        Dict with success status and message_id if successful
    """
    from models.inbox import mark_outbox_sent, mark_outbox_failed
    from db_helper import fetch_one, get_db
    from services.websocket_manager import broadcast_message_status_update
    
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
            return {"success": False, "error": "Message not found"}
        
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
            result = await _send_via_whatsapp(
                license_id, outbox_id, body, recipient_id, recipient_email, reply_to_platform_id
            )
            
        elif channel in ("telegram_bot", "telegram"):
            # Support both "telegram_bot" and legacy "telegram" channel names
            # For "telegram", we need to detect whether to use Bot or Phone
            if channel == "telegram":
                # Check which Telegram configuration is available
                from models.telegram_config import get_telegram_phone_session_data
                
                # get_telegram_phone_session_data returns the session_string directly (str) or None
                session_string = await get_telegram_phone_session_data(license_id)
                if session_string:
                    result = await _send_via_telegram_phone(
                        license_id, outbox_id, body, recipient_id, recipient_email, reply_to_platform_id
                    )
                else:
                    result = await _send_via_telegram_bot(
                        license_id, outbox_id, body, recipient_id, recipient_email, reply_to_platform_id
                    )
            else:
                # Explicit "telegram_bot" channel
                result = await _send_via_telegram_bot(
                    license_id, outbox_id, body, recipient_id, recipient_email, reply_to_platform_id
                )
            
        elif channel == "telegram_phone":
            result = await _send_via_telegram_phone(
                license_id, outbox_id, body, recipient_id, recipient_email, reply_to_platform_id
            )
            
        elif channel == "gmail":
            result = await _send_via_gmail(
                license_id, outbox_id, body, subject, recipient_email, reply_to_platform_id, attachments
            )
            
        elif channel == "saved":
            # Saved Messages (self-chat) - just mark as sent
            # No need to save to inbox as it's the same user
            # The mobile app shows the outgoing message optimistically
            result = {"success": True, "message_id": str(outbox_id)}
            
        elif channel == "almudeer":
            # Almudeer internal message - deliver to recipient's inbox
            result = await _send_via_almudeer(
                license_id, outbox_id, body, recipient_id, recipient_email, 
                reply_to_platform_id, attachments
            )
            
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
            
        return result
        
    except Exception as e:
        logger.error(f"Unified Send: Critical failure for outbox {outbox_id}: {e}", exc_info=True)
        try:
            await mark_outbox_failed(outbox_id, str(e))
        except:
            pass
        return {"success": False, "error": str(e)}


async def _send_via_whatsapp(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    recipient_email: Optional[str],
    reply_to_platform_id: Optional[str]
) -> Dict[str, Any]:
    """Send message via WhatsApp."""
    from services.whatsapp_service import WhatsAppService, get_whatsapp_config
    
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
    return result


async def _send_via_telegram_bot(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    recipient_email: Optional[str],
    reply_to_platform_id: Optional[str]
) -> Dict[str, Any]:
    """Send message via Telegram Bot."""
    from services.telegram_service import TelegramService
    from models.telegram_config import get_telegram_config
    
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
    return {"success": True, "message_id": str(result.get("message_id", ""))}


async def _send_via_telegram_phone(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    recipient_email: Optional[str],
    reply_to_platform_id: Optional[str]
) -> Dict[str, Any]:
    """Send message via Telegram Phone."""
    from services.telegram_phone_service import TelegramPhoneService
    from models.telegram_config import get_telegram_phone_session_data
    
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
    return {"success": True, "message_id": str(result.get("id", ""))}


async def _send_via_gmail(
    license_id: int,
    outbox_id: int,
    body: str,
    subject: Optional[str],
    recipient_email: Optional[str],
    reply_to_platform_id: Optional[str],
    attachments: Optional[List[Dict]]
) -> Dict[str, Any]:
    """Send message via Gmail."""
    from services.gmail_api_service import GmailAPIService
    from models.email_config import get_email_oauth_tokens
    
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
    return {"success": True, "message_id": result.get("id")}


async def _send_via_almudeer(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    recipient_email: Optional[str],
    reply_to_platform_id: Optional[str],
    attachments: Optional[List[Dict]]
) -> Dict[str, Any]:
    """
    Send internal Almudeer message to another user.
    
    This delivers the message to the recipient's inbox and broadcasts
    real-time updates to both sender and recipient.
    """
    from models.inbox import save_inbox_message, upsert_conversation_state
    from services.websocket_manager import broadcast_new_message, broadcast_message_status_update
    from db_helper import get_db, fetch_one
    from datetime import datetime, timezone
    
    # Use a single connection for all DB operations
    async with get_db() as db:
        # Get outbox message details
        outbox_msg = await fetch_one(
            db,
            "SELECT * FROM outbox_messages WHERE id = ?",
            [outbox_id]
        )
        
        if not outbox_msg:
            raise ValueError(f"Outbox message {outbox_id} not found")
        
        # Get sender license info
        sender_license = await fetch_one(
            db,
            "SELECT username, full_name FROM license_keys WHERE id = ?",
            [license_id]
        )
        
        if not sender_license:
            raise ValueError(f"Sender license {license_id} not found")
        
        # Find recipient license by username
        recipient_username = recipient_email or recipient_id
        if not recipient_username:
            raise ValueError("No recipient specified for Almudeer message")
        
        recipient_license = await fetch_one(
            db,
            "SELECT id, username, full_name FROM license_keys WHERE username = ?",
            [recipient_username]
        )
        
        if not recipient_license:
            raise ValueError(f"Recipient '{recipient_username}' not found on Almudeer")
        
        recipient_license_id = recipient_license["id"]
        
        # Prepare sender info for the message
        sender_name = sender_license.get("full_name") or sender_license.get("username")
        sender_contact = sender_license.get("username")
        sender_id = sender_license.get("username")
        
        # Save to recipient's inbox
        now = datetime.now(timezone.utc)
        inbox_message_id = await save_inbox_message(
            license_id=recipient_license_id,
            channel="almudeer",
            body=body,
            sender_name=sender_name,
            sender_contact=sender_contact,
            sender_id=sender_id,
            received_at=now,
            attachments=attachments,
            reply_to_platform_id=reply_to_platform_id,
            platform_message_id=str(outbox_id),
            platform_status="delivered",
        )
    
    # Check if message was saved successfully
    if inbox_message_id == 0:
        logger.warning(f"Almudeer message {outbox_id} was not saved (duplicate or blocked)")
        return {"success": False, "error": "Message not saved"}
    
    # Update conversation state for recipient (outside DB context - uses its own connection)
    await upsert_conversation_state(recipient_license_id, sender_contact)
    
    # Also update conversation state for sender (to show the message in their chat)
    await upsert_conversation_state(license_id, recipient_username)
    
    # Broadcast to recipient (new message notification)
    recipient_event = {
        "id": inbox_message_id,
        "channel": "almudeer",
        "sender_contact": sender_contact,
        "sender_name": sender_name,
        "body": body,
        "status": "received",
        "direction": "incoming",
        "timestamp": now.isoformat(),
        "attachments": attachments or [],
        "is_forwarded": bool(outbox_msg.get("is_forwarded", False)),
    }
    await broadcast_new_message(recipient_license_id, recipient_event)
    
    # Broadcast status update to sender (message delivered)
    sender_event = {
        "id": outbox_id,
        "outbox_id": outbox_id,
        "channel": "almudeer",
        "sender_contact": recipient_username,
        "sender_name": recipient_license.get("full_name") or recipient_username,
        "body": body,
        "status": "sent",
        "direction": "outgoing",
        "timestamp": now.isoformat(),
        "attachments": attachments or [],
        "is_forwarded": bool(outbox_msg.get("is_forwarded", False)),
    }
    await broadcast_message_status_update(license_id, sender_event)
    
    logger.info(f"Almudeer message {outbox_id} delivered to {recipient_username}")
    return {"success": True, "message_id": str(inbox_message_id)}
