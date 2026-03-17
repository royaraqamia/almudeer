"""
Al-Mudeer - Message Sender Service (UPDATED)

Unified service for sending messages through all supported channels:
- Telegram (Bot & Phone)
- Almudeer (internal)
"""

import logging
import os
import tempfile
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

from logging_config import get_logger

logger = get_logger(__name__)


async def send_outbox_message(outbox_id: int, license_id: int) -> Dict[str, Any]:
    """
    Send an outbox message through the appropriate channel.
    """
    from models.inbox import mark_outbox_sent, mark_outbox_failed
    from db_helper import fetch_one, get_db
    from services.websocket_manager import broadcast_message_status_update

    try:
        async with get_db() as db:
            message = await fetch_one(
                db,
                "SELECT * FROM outbox_messages WHERE id = $1 AND license_key_id = $2",
                [outbox_id, license_id]
            )

        if not message:
            logger.error(f"Unified Send: Outbox message {outbox_id} not found for license {license_id}")
            return {"success": False, "error": "Message not found"}

        channel = message["channel"]
        body = message["body"] or ""
        recipient_id = message.get("recipient_id")
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

        # Send based on channel
        if channel == "whatsapp":
            # WhatsApp is deprecated - treat as telegram_bot
            logger.warning(f"Message {outbox_id} uses deprecated 'whatsapp' channel, treating as telegram_bot")
            result = await _send_via_telegram_bot(
                license_id, outbox_id, body, recipient_id, reply_to_platform_id, attachments
            )

        elif channel in ("telegram_bot", "telegram"):
            if channel == "telegram":
                from models.telegram_config import get_telegram_phone_session_data
                session_string = await get_telegram_phone_session_data(license_id)
                if session_string:
                    result = await _send_via_telegram_phone(
                        license_id, outbox_id, body, recipient_id, reply_to_platform_id, attachments
                    )
                else:
                    result = await _send_via_telegram_bot(
                        license_id, outbox_id, body, recipient_id, reply_to_platform_id, attachments
                    )
            else:
                result = await _send_via_telegram_bot(
                    license_id, outbox_id, body, recipient_id, reply_to_platform_id, attachments
                )

        elif channel == "saved":
            result = {"success": True, "message_id": str(outbox_id)}

        elif channel == "almudeer":
            result = await _send_via_almudeer(
                license_id, outbox_id, body, recipient_id,
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


async def _send_via_telegram_bot(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    reply_to_platform_id: Optional[str],
    attachments: Optional[List[Dict]] = None
) -> Dict[str, Any]:
    """Send message via Telegram Bot with attachments and captions."""
    from services.telegram_service import TelegramService
    from models.telegram_config import get_telegram_config
    from services.file_storage_service import get_file_storage

    config = await get_telegram_config(license_id)
    if not config or not config.get("bot_token"):
        raise ValueError("Telegram Bot not configured")

    service = TelegramService(bot_token=config["bot_token"])
    chat_id = recipient_id
    reply_to = int(reply_to_platform_id) if reply_to_platform_id and reply_to_platform_id.isdigit() else None

    try:
        # If no attachments, send as text message
        if not attachments or len(attachments) == 0:
            result = await service.send_message(
                chat_id=chat_id,
                text=body,
                reply_to_message_id=reply_to
            )
            return {"success": True, "message_id": str(result.get("message_id", ""))}

        # Send attachments with captions
        # For multiple attachments, we send them as separate messages
        sent_message_id = None
        
        for i, attachment in enumerate(attachments):
            att_type = attachment.get("type", "file")
            caption = attachment.get("caption")

            # CRITICAL: Normalize empty/whitespace captions to None
            if caption and not caption.strip():
                caption = None

            # Use body as caption for first attachment if no caption specified
            if i == 0 and not caption and body:
                caption = body

            # Get file path from storage
            local_path = attachment.get("local_path") or attachment.get("path")
            if not local_path:
                logger.warning(f"Attachment {i} has no valid path")
                continue

            # Resolve full path using file storage service
            try:
                storage = get_file_storage()
                # Use the storage service's path resolution
                if local_path.startswith('/'):
                    full_path = local_path
                elif local_path.startswith('http') or local_path.startswith('/static/'):
                    full_path = storage.get_local_path(local_path)
                else:
                    full_path = os.path.join(storage.upload_dir, local_path)

                # Verify file exists
                if not os.path.exists(full_path):
                    # Try alternative path formats
                    alt_path = local_path.replace('/static/uploads/', '')
                    if alt_path != local_path:
                        full_path = os.path.join(storage.upload_dir, alt_path)

                    if not os.path.exists(full_path):
                        logger.error(f"Attachment file not found: {full_path} (tried: {local_path})")
                        continue
            except Exception as path_error:
                logger.error(f"Failed to resolve attachment path: {path_error}")
                continue

            # Send based on type
            try:
                if att_type in ("photo", "image"):
                    result = await service.send_photo(
                        chat_id=chat_id,
                        photo_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )
                elif att_type == "video":
                    result = await service.send_video(
                        chat_id=chat_id,
                        video_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )
                elif att_type in ("voice", "audio") and attachment.get("is_voice"):
                    result = await service.send_voice(
                        chat_id=chat_id,
                        audio_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )
                elif att_type == "audio":
                    result = await service.send_audio(
                        chat_id=chat_id,
                        audio_path=full_path,
                        reply_to_message_id=reply_to if i == 0 else None
                    )
                else:
                    # Document (fallback for all types)
                    result = await service.send_document(
                        chat_id=chat_id,
                        document_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )

                sent_message_id = result.get("message_id")

            except Exception as att_error:
                logger.error(f"Failed to send attachment {i}: {att_error}")
                # Continue with next attachment

        if sent_message_id:
            return {"success": True, "message_id": str(sent_message_id)}
        else:
            return {"success": False, "error": "Failed to send all attachments"}

    except Exception as e:
        logger.error(f"Telegram Bot send error: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


async def _send_via_telegram_phone(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    reply_to_platform_id: Optional[str],
    attachments: Optional[List[Dict]] = None
) -> Dict[str, Any]:
    """Send message via Telegram Phone with attachments and captions."""
    from services.telegram_phone_service import TelegramPhoneService
    from models.telegram_config import get_telegram_phone_session_data
    from services.file_storage_service import get_file_storage

    session_string = await get_telegram_phone_session_data(license_id)
    if not session_string:
        raise ValueError("Telegram Phone not configured")

    service = TelegramPhoneService()
    reply_to = int(reply_to_platform_id) if reply_to_platform_id and reply_to_platform_id.isdigit() else None

    try:
        # If no attachments, send as text message
        if not attachments or len(attachments) == 0:
            result = await service.send_message(
                session_string=session_string,
                recipient_id=recipient_id,
                text=body,
                reply_to_message_id=reply_to
            )
            return {"success": True, "message_id": str(result.get("id", ""))}

        # Send attachments with captions
        sent_message_id = None

        for i, attachment in enumerate(attachments):
            att_type = attachment.get("type", "file")
            caption = attachment.get("caption")

            # CRITICAL: Normalize empty/whitespace captions to None
            if caption and not caption.strip():
                caption = None

            # Use body as caption for first attachment if no caption specified
            if i == 0 and not caption and body:
                caption = body

            # Get file path from storage
            local_path = attachment.get("local_path") or attachment.get("path")
            if not local_path:
                logger.warning(f"Attachment {i} has no valid path")
                continue

            # Resolve full path using file storage service
            try:
                storage = get_file_storage()
                # Use the storage service's path resolution
                if local_path.startswith('/'):
                    full_path = local_path
                elif local_path.startswith('http') or local_path.startswith('/static/'):
                    full_path = storage.get_local_path(local_path)
                else:
                    full_path = os.path.join(storage.upload_dir, local_path)

                # Verify file exists
                if not os.path.exists(full_path):
                    # Try alternative path formats
                    alt_path = local_path.replace('/static/uploads/', '')
                    if alt_path != local_path:
                        full_path = os.path.join(storage.upload_dir, alt_path)

                    if not os.path.exists(full_path):
                        logger.error(f"Attachment file not found: {full_path} (tried: {local_path})")
                        continue
            except Exception as path_error:
                logger.error(f"Failed to resolve attachment path: {path_error}")
                continue

            # Send based on type
            try:
                if att_type in ("photo", "image", "video"):
                    # Telegram Phone uses send_file for both photos and videos
                    result = await service.send_file(
                        session_string=session_string,
                        recipient_id=recipient_id,
                        file_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )
                elif att_type in ("voice", "audio"):
                    result = await service.send_voice(
                        session_string=session_string,
                        recipient_id=recipient_id,
                        audio_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )
                else:
                    # Document (fallback)
                    result = await service.send_file(
                        session_string=session_string,
                        recipient_id=recipient_id,
                        file_path=full_path,
                        caption=caption,
                        reply_to_message_id=reply_to if i == 0 else None
                    )

                sent_message_id = result.get("id")

            except Exception as att_error:
                logger.error(f"Failed to send attachment {i}: {att_error}")
                continue

        if sent_message_id:
            return {"success": True, "message_id": str(sent_message_id)}
        else:
            return {"success": False, "error": "Failed to send all attachments"}

    except Exception as e:
        logger.error(f"Telegram Phone send error: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


async def _send_via_almudeer(
    license_id: int,
    outbox_id: int,
    body: str,
    recipient_id: Optional[str],
    reply_to_platform_id: Optional[str],
    attachments: Optional[List[Dict]]
) -> Dict[str, Any]:
    """
    Send internal Almudeer message to another user.
    """
    from models.inbox import save_inbox_message, upsert_conversation_state
    from services.websocket_manager import broadcast_new_message, broadcast_message_status_update
    from db_helper import get_db, fetch_one, execute_sql, commit_db
    from datetime import datetime, timezone

    async with get_db() as db:
        outbox_msg = await fetch_one(db, "SELECT * FROM outbox_messages WHERE id = ?", [outbox_id])
        if not outbox_msg:
            raise ValueError(f"Outbox message {outbox_id} not found")

        sender_license = await fetch_one(db, "SELECT username, full_name FROM license_keys WHERE id = ?", [license_id])
        if not sender_license:
            raise ValueError(f"Sender license {license_id} not found")

        recipient_username = recipient_id
        if not recipient_username:
            raise ValueError("No recipient specified for Almudeer message")

        recipient_license = await fetch_one(db, "SELECT id, username, full_name FROM license_keys WHERE username = ?", [recipient_username])
        if not recipient_license:
            raise ValueError(f"Recipient '{recipient_username}' not found on Almudeer")

        recipient_license_id = recipient_license["id"]
        sender_name = sender_license.get("full_name") or sender_license.get("username")
        sender_contact = sender_license.get("username")
        sender_id = sender_license.get("username")
        now = datetime.now(timezone.utc)

        reply_to_body_preview = None
        reply_to_sender_name = None
        reply_to_id_val = None
        reply_identifier = reply_to_platform_id or outbox_msg.get("reply_to_id")

        if reply_identifier:
            original_msg = await fetch_one(
                db,
                """
                SELECT id, body, sender_name, 'inbox' as source
                FROM inbox_messages WHERE id = $1
                UNION ALL
                SELECT id, body, sender_name, 'outbox' as source
                FROM outbox_messages WHERE id = $1
                LIMIT 1
                """,
                [int(reply_identifier) if str(reply_identifier).isdigit() else reply_identifier]
            )
            if original_msg:
                reply_to_id_val = original_msg["id"]
                reply_to_body_preview = original_msg["body"][:100] if original_msg["body"] else ""
                reply_to_sender_name = original_msg.get("sender_name") or "مستخدم" if original_msg.get("source") == "inbox" else "أنا"

        inbox_message_id = await save_inbox_message(
            license_id=recipient_license_id,
            channel="almudeer",
            body=body,
            sender_name=sender_name,
            sender_contact=sender_contact,
            sender_id=sender_id,
            received_at=now,
            attachments=attachments,
            reply_to_platform_id=str(reply_identifier) if reply_identifier else None,
            reply_to_body_preview=reply_to_body_preview,
            reply_to_sender_name=reply_to_sender_name,
            reply_to_id=reply_to_id_val,
            platform_message_id=str(outbox_id),
            platform_status="delivered",
        )

    if inbox_message_id == 0:
        logger.warning(f"Almudeer message {outbox_id} was not saved (duplicate or blocked)")
        return {"success": False, "error": "Message not saved"}

    await upsert_conversation_state(recipient_license_id, sender_contact)
    await upsert_conversation_state(license_id, recipient_username)

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
        "reply_to_id": reply_to_id_val,
        "reply_to_platform_id": str(reply_identifier) if reply_identifier else None,
        "reply_to_body_preview": reply_to_body_preview,
        "reply_to_sender_name": reply_to_sender_name,
    }
    await broadcast_new_message(recipient_license_id, recipient_event)

    async with get_db() as db:
        await execute_sql(db, "UPDATE outbox_messages SET delivery_status = 'sent' WHERE id = ?", [outbox_id])
        await commit_db(db)

    from services.websocket_manager import get_websocket_manager
    manager = get_websocket_manager()
    recipient_is_online = recipient_license_id in manager.get_connected_licenses()

    if recipient_is_online:
        async with get_db() as db:
            await execute_sql(db, "UPDATE outbox_messages SET delivery_status = 'delivered' WHERE id = ?", [outbox_id])
            await commit_db(db)

        sender_event = {
            "outbox_id": outbox_id,
            "inbox_message_id": inbox_message_id,
            "sender_contact": recipient_username,
            "status": "delivered",
            "delivery_status": "delivered",
            "timestamp": now.isoformat(),
        }
        await broadcast_message_status_update(license_id, sender_event)
        logger.info(f"Almudeer message {outbox_id} delivered to {recipient_username} (recipient online)")
    else:
        sender_event = {
            "outbox_id": outbox_id,
            "inbox_message_id": inbox_message_id,
            "sender_contact": recipient_username,
            "status": "sent",
            "delivery_status": "sent",
            "timestamp": now.isoformat(),
        }
        await broadcast_message_status_update(license_id, sender_event)
        logger.info(f"Almudeer message {outbox_id} sent to {recipient_username} (recipient offline)")

    return {"success": True, "message_id": str(inbox_message_id)}
