"""
Al-Mudeer Forwarding Service
Handles cross-channel media re-uploading and message forwarding.
Supports WhatsApp, Telegram, and Gmail.
"""

import os
import tempfile
from typing import Optional, List, Dict, Any
from services.whatsapp_service import WhatsAppService
from services.telegram_service import TelegramService
from services.email_service import EmailService
from logging_config import get_logger

logger = get_logger(__name__)

class ForwardingService:
    def __init__(
        self,
        whatsapp_service: Optional[WhatsAppService] = None,
        telegram_service: Optional[TelegramService] = None,
        email_service: Optional[EmailService] = None
    ):
        self.whatsapp = whatsapp_service
        self.telegram = telegram_service
        self.email = email_service

    async def forward_media(
        self,
        source_channel: str,
        target_channel: str,
        target_id: str,
        media_id: str,
        media_type: str,
        caption: Optional[str] = None,
        filename: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Downloads media from source and uploads to target channel.
        Returns success status and platform-specific message ID.
        """
        temp_file_path = None
        try:
            # 1. Download from Source
            media_content = await self._download_from_source(source_channel, media_id)
            if not media_content:
                return {"success": False, "error": f"Failed to download media from {source_channel}"}

            # 2. Save to Temporary File
            with tempfile.NamedTemporaryFile(delete=False) as temp_file:
                temp_file.write(media_content)
                temp_file_path = temp_file.name

            # 3. Upload/Send to Target
            result = await self._upload_to_target(
                target_channel,
                target_id,
                temp_file_path,
                media_type,
                caption=caption,
                filename=filename
            )
            return result

        except Exception as e:
            logger.error(f"Error in forward_media: {e}")
            return {"success": False, "error": str(e)}
        finally:
            if temp_file_path and os.path.exists(temp_file_path):
                os.remove(temp_file_path)

    async def _download_from_source(self, channel: str, media_id: str) -> Optional[bytes]:
        if channel == "whatsapp" and self.whatsapp:
            return await self.whatsapp.download_media(media_id)
        elif channel == "telegram" and self.telegram:
            # Telegram uses file_id, we need to get file_path first
            file_info = await self.telegram.get_file(media_id)
            if file_info.get("file_path"):
                return await self.telegram.download_file(file_info["file_path"])
        elif channel == "email" and self.email:
            # Download from our DB/Storage since email attachments are saved locally
            # In GmailAPIService._parse_message, attachments are saved to storage
            # media_id here would be the file_id or path
            from services.file_storage_service import get_file_storage
            # We assume media_id might be a path or we need to find it
            # For simplicity, if media_id is a path, we read it
            if os.path.exists(media_id):
                with open(media_id, "rb") as f:
                    return f.read()
            return None
        return None

    async def _upload_to_target(
        self,
        channel: str,
        target_id: str,
        file_path: str,
        media_type: str,
        caption: Optional[str] = None,
        filename: Optional[str] = None
    ) -> Dict[str, Any]:
        if channel == "whatsapp" and self.whatsapp:
            mime_type = self._get_mime_type(media_type)
            wa_media_id = await self.whatsapp.upload_media(file_path, mime_type=mime_type)
            if not wa_media_id:
                return {"success": False, "error": "WhatsApp upload failed"}
            
            if media_type == "image":
                return await self.whatsapp.send_image_message(target_id, wa_media_id, caption=caption)
            elif media_type == "audio" or media_type == "voice":
                return await self.whatsapp.send_audio_message(target_id, wa_media_id)
            elif media_type == "video":
                return await self.whatsapp.send_video_message(target_id, wa_media_id, caption=caption)
            else: # document
                return await self.whatsapp.send_document_message(target_id, wa_media_id, filename or "file", caption=caption)

        elif channel == "telegram" and self.telegram:
            if media_type == "image":
                return await self.telegram.send_photo(target_id, file_path, caption=caption)
            elif media_type == "voice":
                return await self.telegram.send_voice(target_id, file_path, caption=caption)
            elif media_type == "audio":
                return await self.telegram.send_audio(target_id, file_path, title=caption)
            elif media_type == "video":
                return await self.telegram.send_video(target_id, file_path, caption=caption)
            else: # document
                return await self.telegram.send_document(target_id, file_path, caption=caption)

        elif channel == "email" and self.email:
            # Email sending logic normally uses body + attachments
            # We use EmailService or GmailAPIService
            try:
                # We need a subject and body. If not provided, use defaults.
                attachments = []
                if os.path.exists(file_path):
                    import base64
                    with open(file_path, "rb") as f:
                        b64_data = base64.b64encode(f.read()).decode('utf-8')
                        attachments.append({
                            "filename": filename or os.path.basename(file_path),
                            "base64": b64_data
                        })
                
                # We need to know which email config to use. 
                # This service might need a license_id to fetch the right config.
                # However, the current __init__ takes an initialized service.
                res = await self.email.send_image_message(target_id, file_path, caption=caption) if media_type == "image" else \
                      await self.email.send_message(target_id, caption or "Shared File", attachments=attachments)
                
                return {"success": True, "message_id": res.get("id") if res else None}
            except Exception as e:
                return {"success": False, "error": str(e)}

        return {"success": False, "error": f"Unsupported target channel: {channel}"}

    def _get_mime_type(self, media_type: str) -> str:
        mapping = {
            "image": "image/jpeg",
            "audio": "audio/mpeg",
            "voice": "audio/ogg",
            "video": "video/mp4",
            "document": "application/pdf"
        }
        return mapping.get(media_type, "application/octet-stream")
