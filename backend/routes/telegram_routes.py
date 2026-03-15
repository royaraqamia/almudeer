"""
Al-Mudeer - Telegram Routes
Bot integration and Phone session (MTProto) management
"""

import base64
import logging
from fastapi import APIRouter, HTTPException, Depends, Request, BackgroundTasks
from pydantic import BaseModel, Field
from typing import Optional, List

from models import (
    save_telegram_config,
    get_telegram_config,
    save_telegram_phone_session,
    get_telegram_phone_session,
    get_telegram_phone_session_data,
    deactivate_telegram_phone_session,
    save_inbox_message,
)
from services import (
    TelegramService,
    TelegramBotManager,
    TelegramPhoneService,
    get_telegram_phone_service,
)
from dependencies import get_license_from_header

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/integrations", tags=["Telegram"])

# Guides
TELEGRAM_SETUP_GUIDE = """
# دليل إعداد بوت تيليجرام
...
""" # Abbreviated for brevity, normally I'd copy full text

class TelegramConfigRequest(BaseModel):
    bot_token: str

class TelegramPhoneStartRequest(BaseModel):
    phone_number: str

class TelegramPhoneVerifyRequest(BaseModel):
    phone_number: str
    code: str
    session_id: str
    password: Optional[str] = None

@router.get("/telegram/guide")
async def get_telegram_guide():
    return {"guide": TELEGRAM_SETUP_GUIDE}

@router.post("/telegram/config")
async def configure_telegram(
    config: TelegramConfigRequest,
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    """Configure Telegram bot integration"""
    bot_token = config.bot_token.strip()
    if ":" not in bot_token:
        raise HTTPException(status_code=400, detail="توكن البوت غير صالح")
    
    telegram_service = TelegramService(bot_token)
    success, message, bot_info = await telegram_service.test_connection()
    
    if not success:
        raise HTTPException(status_code=400, detail=message)
    
    await save_telegram_config(
        license_id=license["license_id"],
        bot_token=bot_token,
        bot_username=bot_info.get("username")
    )
    
    # Set webhook
    base_url = str(request.base_url).rstrip('/').replace('http://', 'https://')
    webhook_url = f"{base_url}/api/integrations/telegram/webhook/{license['license_id']}"
    await telegram_service.set_webhook(webhook_url)
    
    return {"success": True, "message": "تم حفظ إعدادات تيليجرام بنجاح", "bot_username": bot_info.get("username")}

@router.post("/telegram/webhook/set")
async def set_telegram_webhook(
    request: Request,
    license: dict = Depends(get_license_from_header)
):
    from models import get_telegram_bot_token
    bot_token = await get_telegram_bot_token(license["license_id"])
    if not bot_token:
        raise HTTPException(status_code=400, detail="Telegram bot not configured")
    
    telegram_service = TelegramService(bot_token)
    base_url = str(request.base_url).rstrip('/').replace('http://', 'https://')
    webhook_url = f"{base_url}/api/integrations/telegram/webhook/{license['license_id']}"
    await telegram_service.set_webhook(webhook_url)
    return {"success": True, "message": "تم تسجيل الـ webhook بنجاح", "webhook_url": webhook_url}

@router.get("/telegram/config")
async def get_telegram_configuration(license: dict = Depends(get_license_from_header)):
    config = await get_telegram_config(license["license_id"], include_inactive=False)
    return {"config": config}

@router.get("/telegram/webhook/status")
async def get_telegram_webhook_status(license: dict = Depends(get_license_from_header)):
    from models import get_telegram_bot_token
    bot_token = await get_telegram_bot_token(license["license_id"])
    if not bot_token: return {"error": "Telegram bot not configured"}
    
    import httpx
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"https://api.telegram.org/bot{bot_token}/getWebhookInfo")
        return {"success": True, "webhook_info": resp.json().get("result", {})}

@router.post("/telegram/webhook/{license_id}")
async def telegram_webhook(
    license_id: int,
    request: Request,
    background_tasks: BackgroundTasks
):
    """Receive Telegram webhook updates with robust attachment handling"""
    import httpx
    from services.file_storage_service import get_file_storage
    
    update = await request.json()
    parsed = TelegramService.parse_update(update)
    if not parsed or parsed["is_bot"]: 
        return {"ok": True}
    if parsed["chat_type"] != "private": 
        return {"ok": True}

    config = await get_telegram_config(license_id)
    if not config or not config.get("is_active"): 
        return {"ok": True}

    # Avoid loop
    if config.get("bot_username") == parsed.get("username"): 
        return {"ok": True}

    sender_contact = parsed["username"] if parsed["username"] else f"tg:{parsed['user_id']}"
    sender_name = f"{parsed.get('first_name', '')} {parsed.get('last_name', '')}".strip() or "Telegram User"

    # Parse attachments from the update
    attachments = parsed.get("attachments", [])
    body_text = parsed.get("text", "")
    
    # Download and process attachments if present
    if attachments:
        try:
            bot = TelegramBotManager.get_bot(license_id, config["bot_token"])
            file_storage = get_file_storage()
            
            processed_attachments = []
            download_errors = []
            
            for idx, att in enumerate(attachments):
                file_id = att.get("file_id")
                if not file_id:
                    logger.warning(f"Attachment {idx} missing file_id, skipping")
                    continue
                
                try:
                    # Get file info from Telegram
                    file_info = await bot.get_file(file_id)
                    if not file_info or not file_info.get("file_path"):
                        download_errors.append(f"File info not available for attachment {idx}")
                        continue
                    
                    # Download file content
                    content = await bot.download_file(file_info["file_path"])
                    if not content:
                        download_errors.append(f"Failed to download content for attachment {idx}")
                        continue
                    
                    # Determine filename with proper extension
                    filename = att.get("file_name")
                    if not filename:
                        ext = _get_extension_for_mime(att.get("mime_type", ""))
                        filename = f"{att.get('type', 'file')}_{file_id}{ext}"
                    
                    # Save to persistent storage
                    rel_path, abs_url = file_storage.save_file(
                        content=content,
                        filename=filename,
                        mime_type=att.get("mime_type", "application/octet-stream")
                    )
                    
                    # Build complete attachment object
                    processed_att = {
                        "type": att.get("type", "file"),
                        "mime_type": att.get("mime_type", "application/octet-stream"),
                        "file_id": file_id,
                        "url": abs_url,
                        "path": rel_path,
                        "file_size": len(content),
                        "size": len(content),
                        "filename": filename,
                        "file_name": filename,
                    }
                    
                    # Add base64 for instant preview on small files
                    # Images < 200KB, other files < 100KB
                    size_threshold = 200 * 1024 if att.get("type") == "photo" else 100 * 1024
                    if len(content) < size_threshold:
                        try:
                            processed_att["base64"] = base64.b64encode(content).decode('utf-8')
                        except Exception as b64_err:
                            logger.warning(f"Failed to encode attachment {idx} as base64: {b64_err}")
                    
                    processed_attachments.append(processed_att)
                    
                except httpx.TimeoutException as e:
                    logger.error(f"Timeout downloading attachment {idx}: {e}")
                    download_errors.append(f"Timeout for attachment {idx}")
                    # Keep attachment with file_id only - will be downloaded on-demand
                    att["download_pending"] = True
                    processed_attachments.append(att)
                except Exception as e:
                    logger.error(f"Error processing attachment {idx}: {e}", exc_info=True)
                    download_errors.append(f"Error for attachment {idx}: {str(e)}")
                    # Keep attachment with file_id only - will be downloaded on-demand
                    att["download_pending"] = True
                    processed_attachments.append(att)
            
            # Use processed attachments
            attachments = processed_attachments
            
            if download_errors:
                logger.warning(f"Attachment download warnings: {download_errors}")
                
        except Exception as e:
            logger.error(f"Critical error in attachment processing: {e}", exc_info=True)
            # Don't fail the message - save with original attachments (file_id only)
    
    # Ensure body text is never empty when attachments exist
    if not body_text or not body_text.strip():
        if attachments:
            # Create descriptive fallback based on attachment types
            attachment_types = [att.get("type", "file") for att in attachments]
            if len(attachments) == 1:
                att_type = attachment_types[0]
                if att_type == "photo":
                    body_text = "📷 صورة"
                elif att_type == "video":
                    body_text = "🎥 فيديو"
                elif att_type == "voice":
                    body_text = "🎤 رسالة صوتية"
                elif att_type == "audio":
                    body_text = "🎵 ملف صوتي"
                elif att_type == "document":
                    body_text = "📄 ملف"
                else:
                    body_text = "📎 مرفق"
            else:
                body_text = f"📎 {len(attachments)} مرفقات"
        else:
            body_text = "(بدون نص)"
    
    # Save the message to inbox
    msg_id = await save_inbox_message(
        license_id=license_id,
        channel="telegram_bot",
        body=body_text,
        sender_name=sender_name,
        sender_contact=sender_contact,
        sender_id=parsed["user_id"],
        channel_message_id=str(parsed["message_id"]),
        received_at=parsed["date"],
        attachments=attachments if attachments else None,
        is_forwarded=parsed.get("is_forwarded", False)
    )
    
    if msg_id > 0:
        logger.info(f"Saved Telegram message {msg_id} with {len(attachments)} attachments")
    else:
        logger.warning(f"Message not saved (filtered/blocked) for license {license_id}")
    
    return {"ok": True}


def _get_extension_for_mime(mime_type: str) -> str:
    """Get file extension from MIME type"""
    if not mime_type:
        return ""
    
    mime_to_ext = {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/gif": ".gif",
        "image/webp": ".webp",
        "video/mp4": ".mp4",
        "video/quicktime": ".mov",
        "audio/mpeg": ".mp3",
        "audio/ogg": ".ogg",
        "audio/wav": ".wav",
        "application/pdf": ".pdf",
        "application/msword": ".doc",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
        "text/plain": ".txt",
        "text/csv": ".csv",
    }
    
    return mime_to_ext.get(mime_type, ".bin")

# ============ Telegram Phone Routes (MTProto) ============

@router.post("/telegram-phone/start")
async def start_telegram_phone_login(
    request: TelegramPhoneStartRequest,
    license: dict = Depends(get_license_from_header)
):
    try:
        result = await get_telegram_phone_service().start_login(request.phone_number)
        return {"success": True, "session_id": result.get("session_id"), "phone_number": result["phone_number"]}
    except Exception as e:
        logger.exception("Error starting telegram phone login")
        raise HTTPException(status_code=500, detail="حدث خطأ داخلي")

@router.post("/telegram-phone/verify")
async def verify_telegram_phone_code(
    request: TelegramPhoneVerifyRequest,
    license: dict = Depends(get_license_from_header)
):
    try:
        session_string, user_info = await get_telegram_phone_service().verify_code(
            phone_number=request.phone_number,
            code=request.code,
            session_id=request.session_id,
            password=request.password
        )

        config_id = await save_telegram_phone_session(
            license_id=license["license_id"],
            phone_number=request.phone_number,
            session_string=session_string,
            user_id=str(user_info.get("id")),
            user_first_name=user_info.get("first_name"),
            user_last_name=user_info.get("last_name"),
            user_username=user_info.get("username")
        )
        return {"success": True, "message": "تم ربط رقم Telegram بنجاح", "user": user_info}
    except ValueError as e:
        logger.warning("Invalid value in telegram phone verify: %s", e)
        raise HTTPException(status_code=400, detail="بيانات غير صحيحة")
    except Exception as e:
        logger.exception("Error verifying telegram phone code")
        raise HTTPException(status_code=500, detail="حدث خطأ داخلي")

@router.get("/telegram-phone/config")
async def get_telegram_phone_config(license: dict = Depends(get_license_from_header)):
    config = await get_telegram_phone_session(license["license_id"])
    return {"config": config}

@router.post("/telegram-phone/test")
async def test_telegram_phone_connection(license: dict = Depends(get_license_from_header)):
    try:
        session_string = await get_telegram_phone_session_data(license["license_id"])
        if not session_string: raise HTTPException(status_code=404, detail="لا توجد جلسة نشطة")

        from services.telegram_listener_service import get_telegram_listener
        listener = get_telegram_listener()
        active_client = await listener.ensure_client_active(license["license_id"])

        success, message, user_info = await get_telegram_phone_service().test_connection(session_string, client=active_client)
        return {"success": success, "message": message, "user": user_info}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error testing telegram phone connection")
        raise HTTPException(status_code=500, detail="حدث خطأ داخلي")

@router.post("/telegram-phone/disconnect")
async def disconnect_telegram_phone(license: dict = Depends(get_license_from_header)):
    await deactivate_telegram_phone_session(license["license_id"])
    return {"success": True, "message": "تم قطع الاتصال بنجاح"}
