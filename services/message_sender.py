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
            
        elif channel == "telegram_bot":
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
            
        elif channel == "almudeer" or channel == "saved":
            # Internal Almudeer messages - just mark as sent
            # No need to save to inbox as it's the same user (outgoing = incoming for same account)
            # The mobile app shows the outgoing message optimistically
            result = {"success": True, "message_id": str(outbox_id)}
            
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
    from services.whatsapp_service import WhatsAppService
    from services.email_service import get_whatsapp_config
    
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
    from services.email_service import get_telegram_config
    
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
    from services.email_service import get_telegram_phone_session_data
    
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
    from services.email_service import get_email_oauth_tokens
    
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
