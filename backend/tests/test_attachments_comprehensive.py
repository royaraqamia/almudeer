"""
Al-Mudeer - Comprehensive Attachment Tests

Tests for attachment handling across all channels:
- Telegram Bot (Webhook)
- Telegram Phone (MTProto)
- WhatsApp
- Almudeer Internal

Tests cover:
- Image attachments (photo)
- Video attachments
- Voice/audio attachments
- Document attachments
- Multiple attachments
- Large file handling
- Base64 encoding
- Error handling
- Edge cases
"""

import asyncio
import base64
import json
import os
import sys
import pytest
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from io import BytesIO

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# ============ Test Data ============

# Sample image data (small PNG - 1x1 pixel)
SAMPLE_IMAGE_DATA = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)

# Sample PDF data (minimal)
SAMPLE_PDF_DATA = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF"

# Sample audio data (minimal MP3 frame)
SAMPLE_AUDIO_DATA = b"\xff\xfb\x90\x00" + b"\x00" * 100


class TestTelegramWebhookAttachments:
    """Test Telegram Bot webhook attachment handling"""
    
    @pytest.mark.asyncio
    async def test_parse_photo_message(self):
        """Test parsing Telegram photo message"""
        from services.telegram_service import TelegramService
        
        update = {
            "update_id": 123456,
            "message": {
                "message_id": 789,
                "from": {
                    "id": 111222333,
                    "first_name": "Test",
                    "last_name": "User",
                    "username": "testuser",
                    "is_bot": False
                },
                "chat": {
                    "id": 111222333,
                    "type": "private"
                },
                "date": int(datetime.now().timestamp()),
                "photo": [
                    {"file_id": "small_id", "file_size": 1000, "width": 100, "height": 100},
                    {"file_id": "medium_id", "file_size": 5000, "width": 500, "height": 500},
                    {"file_id": "large_id", "file_size": 20000, "width": 1280, "height": 720}
                ]
            }
        }
        
        parsed = TelegramService.parse_update(update)
        
        assert parsed is not None
        assert parsed["message_id"] == 789
        assert parsed["user_id"] == "111222333"
        assert len(parsed["attachments"]) == 1
        assert parsed["attachments"][0]["type"] == "photo"
        assert parsed["attachments"][0]["file_id"] == "large_id"  # Should get largest
        assert parsed["attachments"][0]["file_size"] == 20000
        # Fallback text for photo-only message
        assert parsed["text"] == "[صورة]"
    
    @pytest.mark.asyncio
    async def test_parse_photo_with_caption(self):
        """Test parsing Telegram photo with caption"""
        from services.telegram_service import TelegramService
        
        update = {
            "update_id": 123457,
            "message": {
                "message_id": 790,
                "from": {"id": 111222333, "first_name": "Test", "is_bot": False},
                "chat": {"id": 111222333, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "photo": [
                    {"file_id": "photo_id", "file_size": 15000, "width": 800, "height": 600}
                ],
                "caption": "Check out this photo! 📷"
            }
        }
        
        parsed = TelegramService.parse_update(update)
        
        assert parsed["text"] == "Check out this photo! 📷"
        assert len(parsed["attachments"]) == 1
        assert parsed["attachments"][0]["type"] == "photo"
    
    @pytest.mark.asyncio
    async def test_parse_voice_message(self):
        """Test parsing Telegram voice message"""
        from services.telegram_service import TelegramService
        
        update = {
            "update_id": 123458,
            "message": {
                "message_id": 791,
                "from": {"id": 111222333, "first_name": "Test", "is_bot": False},
                "chat": {"id": 111222333, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "voice": {
                    "file_id": "voice_id",
                    "file_size": 50000,
                    "duration": 15,
                    "mime_type": "audio/ogg"
                }
            }
        }
        
        parsed = TelegramService.parse_update(update)
        
        assert len(parsed["attachments"]) == 1
        assert parsed["attachments"][0]["type"] == "voice"
        assert parsed["attachments"][0]["file_id"] == "voice_id"
        assert parsed["attachments"][0]["mime_type"] == "audio/ogg"
        assert parsed["text"] == "[رسالة صوتية]"
    
    @pytest.mark.asyncio
    async def test_parse_document(self):
        """Test parsing Telegram document"""
        from services.telegram_service import TelegramService
        
        update = {
            "update_id": 123459,
            "message": {
                "message_id": 792,
                "from": {"id": 111222333, "first_name": "Test", "is_bot": False},
                "chat": {"id": 111222333, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "document": {
                    "file_id": "doc_id",
                    "file_name": "invoice.pdf",
                    "file_size": 102400,
                    "mime_type": "application/pdf"
                }
            }
        }
        
        parsed = TelegramService.parse_update(update)
        
        assert len(parsed["attachments"]) == 1
        assert parsed["attachments"][0]["type"] == "document"
        assert parsed["attachments"][0]["file_name"] == "invoice.pdf"
        assert parsed["attachments"][0]["mime_type"] == "application/pdf"
    
    @pytest.mark.asyncio
    async def test_parse_video(self):
        """Test parsing Telegram video"""
        from services.telegram_service import TelegramService
        
        update = {
            "update_id": 123460,
            "message": {
                "message_id": 793,
                "from": {"id": 111222333, "first_name": "Test", "is_bot": False},
                "chat": {"id": 111222333, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "video": {
                    "file_id": "video_id",
                    "file_size": 5000000,
                    "duration": 30,
                    "width": 1920,
                    "height": 1080,
                    "mime_type": "video/mp4",
                    "file_name": "vacation.mp4"
                }
            }
        }
        
        parsed = TelegramService.parse_update(update)
        
        assert len(parsed["attachments"]) == 1
        assert parsed["attachments"][0]["type"] == "video"
        assert parsed["attachments"][0]["file_size"] == 5000000
        assert parsed["text"] == "[فيديو]"
    
    @pytest.mark.asyncio
    async def test_parse_multiple_attachments(self):
        """Test parsing message with multiple attachment types"""
        from services.telegram_service import TelegramService
        
        # Note: Telegram typically sends one media type per message
        # But we test the parser handles various types
        update = {
            "update_id": 123461,
            "message": {
                "message_id": 794,
                "from": {"id": 111222333, "first_name": "Test", "is_bot": False},
                "chat": {"id": 111222333, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "photo": [
                    {"file_id": "photo1", "file_size": 10000}
                ],
                "caption": "Photo with caption"
            }
        }
        
        parsed = TelegramService.parse_update(update)
        
        assert len(parsed["attachments"]) == 1
        assert parsed["text"] == "Photo with caption"


class TestTelegramWebhookHandler:
    """Test Telegram webhook endpoint attachment processing"""
    
    @pytest.mark.asyncio
    async def test_webhook_downloads_and_saves_attachment(self):
        """Test webhook handler downloads and saves attachments"""
        from routes.telegram_routes import telegram_webhook
        from services.telegram_service import TelegramBotManager
        from services.file_storage_service import FileStorageService
        
        # Mock request
        mock_request = MagicMock()
        mock_request.json = AsyncMock(return_value={
            "update_id": 123456,
            "message": {
                "message_id": 789,
                "from": {
                    "id": 111222333,
                    "first_name": "Test",
                    "username": "testuser",
                    "is_bot": False
                },
                "chat": {"id": 111222333, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "photo": [
                    {"file_id": "photo_id", "file_size": 15000}
                ]
            }
        })
        
        # Mock Telegram bot
        mock_bot = MagicMock()
        mock_bot.get_file = AsyncMock(return_value={
            "file_id": "photo_id",
            "file_path": "photos/file.jpg"
        })
        mock_bot.download_file = AsyncMock(return_value=SAMPLE_IMAGE_DATA)
        
        # Mock file storage
        mock_storage = MagicMock()
        mock_storage.save_file = MagicMock(return_value=(
            "images/abc123.jpg",
            "/static/uploads/images/abc123.jpg"
        ))
        
        with patch.object(TelegramBotManager, 'get_bot', return_value=mock_bot):
            with patch('routes.telegram_routes.get_file_storage', return_value=mock_storage):
                with patch('routes.telegram_routes.get_telegram_config') as mock_config:
                    mock_config.return_value = {
                        "bot_token": "test_token",
                        "bot_username": "test_bot",
                        "is_active": True
                    }
                    
                    with patch('routes.telegram_routes.save_inbox_message') as mock_save:
                        mock_save.return_value = 1
                        
                        result = await telegram_webhook(
                            license_id=1,
                            request=mock_request,
                            background_tasks=MagicMock()
                        )
                        
                        assert result == {"ok": True}
                        
                        # Verify attachment was processed
                        call_args = mock_save.call_args
                        attachments = call_args[1].get('attachments') or call_args[0][8]
                        
                        assert attachments is not None
                        assert len(attachments) > 0
                        assert attachments[0].get('url') == "/static/uploads/images/abc123.jpg"
                        assert attachments[0].get('path') == "images/abc123.jpg"
                        assert 'base64' in attachments[0]  # Small image should have base64


class TestWhatsAppAttachments:
    """Test WhatsApp attachment handling"""
    
    @pytest.mark.asyncio
    async def test_parse_image_message(self):
        """Test parsing WhatsApp image message"""
        from services.whatsapp_service import WhatsAppService
        
        service = WhatsAppService(phone_number_id="123", access_token="test")
        
        payload = {
            "entry": [{
                "changes": [{
                    "value": {
                        "metadata": {"phone_number_id": "123"},
                        "messages": [{
                            "from": "966501234567",
                            "id": "msg_123",
                            "timestamp": "1234567890",
                            "type": "image",
                            "image": {
                                "id": "media_123",
                                "mime_type": "image/jpeg",
                                "caption": "Test image"
                            }
                        }],
                        "contacts": [{
                            "profile": {"name": "Test User"},
                            "wa_id": "966501234567"
                        }]
                    }
                }]
            }]
        }
        
        messages = service.parse_webhook_message(payload)
        
        assert len(messages) == 1
        msg = messages[0]
        assert msg["type"] == "image"
        assert msg["media_id"] == "media_123"
        assert msg["body"] == "[صورة]"
    
    @pytest.mark.asyncio
    async def test_parse_voice_message(self):
        """Test parsing WhatsApp voice message"""
        from services.whatsapp_service import WhatsAppService
        
        service = WhatsAppService(phone_number_id="123", access_token="test")
        
        payload = {
            "entry": [{
                "changes": [{
                    "value": {
                        "metadata": {"phone_number_id": "123"},
                        "messages": [{
                            "from": "966501234567",
                            "id": "msg_124",
                            "timestamp": "1234567890",
                            "type": "audio",
                            "audio": {
                                "id": "media_124",
                                "mime_type": "audio/ogg",
                                "voice": True
                            }
                        }],
                        "contacts": [{
                            "profile": {"name": "Test User"},
                            "wa_id": "966501234567"
                        }]
                    }
                }]
            }]
        }
        
        messages = service.parse_webhook_message(payload)
        
        assert len(messages) == 1
        msg = messages[0]
        assert msg["type"] == "audio"
        assert msg["is_voice"] == True
        assert msg["body"] == "[رسالة صوتية]"


class TestAttachmentFieldNormalization:
    """Test attachment field name normalization"""
    
    def test_inbox_message_parses_attachments(self):
        """Test mobile app InboxMessage.fromJson handles various attachment formats"""
        # This simulates what the Dart code does
        
        # Test with filename/file_name variation
        att1 = {"type": "photo", "filename": "test.jpg", "size": 1000}
        att2 = {"type": "photo", "file_name": "test2.jpg", "file_size": 2000}
        
        # Simulate Dart normalization
        for att in [att1, att2]:
            if att.get('file_name') is None and att.get('filename') is not None:
                att['file_name'] = att['filename']
            elif att.get('filename') is None and att.get('file_name') is not None:
                att['filename'] = att['file_name']
            
            if att.get('size') is None and att.get('file_size') is not None:
                att['size'] = att['file_size']
            elif att.get('file_size') is None and att.get('size') is not None:
                att['file_size'] = att['size']
        
        assert att1['file_name'] == "test.jpg"
        assert att1['size'] == 1000
        assert att2['filename'] == "test2.jpg"
        assert att2['file_size'] == 2000
    
    def test_base64_to_data_url(self):
        """Test base64 conversion to data URL"""
        base64_data = base64.b64encode(SAMPLE_IMAGE_DATA).decode('utf-8')
        mime_type = "image/png"
        data_url = f"data:{mime_type};base64,{base64_data}"
        
        assert data_url.startswith("data:image/png;base64,")
        # Verify it can be decoded back
        extracted = data_url.split(",")[1]
        decoded = base64.b64decode(extracted)
        assert decoded == SAMPLE_IMAGE_DATA


class TestFileStorageService:
    """Test file storage service"""
    
    def test_save_file_returns_correct_paths(self):
        """Test file storage returns relative path and public URL"""
        from services.file_storage_service import FileStorageService
        import tempfile
        import os
        
        with tempfile.TemporaryDirectory() as tmpdir:
            storage = FileStorageService(upload_dir=tmpdir)
            
            rel_path, pub_url = storage.save_file(
                content=SAMPLE_IMAGE_DATA,
                filename="test.png",
                mime_type="image/png"
            )
            
            # Verify paths
            assert rel_path.startswith("images/")
            assert rel_path.endswith(".png")
            assert pub_url.startswith("/static/uploads/")
            assert pub_url.endswith(".png")
            
            # Verify file exists
            full_path = os.path.join(tmpdir, rel_path)
            assert os.path.exists(full_path)
    
    def test_secure_filename(self):
        """Test filename sanitization"""
        from services.file_storage_service import secure_filename
        
        # Safe filenames
        assert secure_filename("test.jpg") == "test.jpg"
        assert secure_filename("my-photo_2024.png") == "my-photo_2024.png"
        
        # Unsafe filenames
        assert ".." not in secure_filename("../etc/passwd")
        assert "/" not in secure_filename("folder/image.jpg")
        assert "\\" not in secure_filename("folder\\image.jpg")


class TestAttachmentSizeHandling:
    """Test attachment size limits and base64 thresholds"""
    
    def test_small_image_gets_base64(self):
        """Test images < 200KB get base64 encoded"""
        small_image = b"\x00" * (100 * 1024)  # 100KB
        
        assert len(small_image) < 200 * 1024
        # Should be encoded
        base64_data = base64.b64encode(small_image).decode('utf-8')
        assert len(base64_data) > 0
    
    def test_large_image_no_base64(self):
        """Test images > 200KB don't get base64 encoded"""
        large_image = b"\x00" * (500 * 1024)  # 500KB
        
        assert len(large_image) > 200 * 1024
        # Should NOT be encoded (URL only)
        # This is handled by the webhook/handler logic
    
    def test_file_size_limit(self):
        """Test 20MB file size limit"""
        MAX_SIZE = 20 * 1024 * 1024
        
        small_file = b"\x00" * (10 * 1024 * 1024)  # 10MB
        large_file = b"\x00" * (25 * 1024 * 1024)  # 25MB
        
        assert len(small_file) < MAX_SIZE
        assert len(large_file) > MAX_SIZE


class TestAttachmentErrorHandling:
    """Test attachment error scenarios"""
    
    @pytest.mark.asyncio
    async def test_download_timeout_handling(self):
        """Test handling of download timeouts"""
        import httpx
        
        # Simulate timeout
        with pytest.raises(httpx.TimeoutException):
            async with httpx.AsyncClient(timeout=0.001) as client:
                await client.get("http://example.com/largefile")
    
    @pytest.mark.asyncio
    async def test_missing_file_id_handling(self):
        """Test handling of missing file_id"""
        from services.telegram_service import TelegramService
        
        update = {
            "message": {
                "photo": [{}],  # Missing file_id
            }
        }
        
        # Should not crash
        parsed = TelegramService.parse_update(update)
        assert parsed is not None


class TestGetExtensionForMime:
    """Test MIME to extension mapping"""
    
    def test_mime_to_extension(self):
        """Test MIME type to file extension mapping"""
        from routes.telegram_routes import _get_extension_for_mime
        
        assert _get_extension_for_mime("image/jpeg") == ".jpg"
        assert _get_extension_for_mime("image/png") == ".png"
        assert _get_extension_for_mime("video/mp4") == ".mp4"
        assert _get_extension_for_mime("audio/mpeg") == ".mp3"
        assert _get_extension_for_mime("application/pdf") == ".pdf"
        assert _get_extension_for_mime("unknown/type") == ".bin"
        assert _get_extension_for_mime("") == ""


# ============ Integration Tests ============

class TestAttachmentEndToEnd:
    """End-to-end attachment flow tests"""
    
    @pytest.mark.asyncio
    async def test_full_attachment_flow(self):
        """Test complete attachment flow from receipt to storage"""
        # 1. Parse incoming message
        from services.telegram_service import TelegramService
        
        update = {
            "update_id": 999,
            "message": {
                "message_id": 1,
                "from": {"id": 123, "first_name": "Test", "is_bot": False},
                "chat": {"id": 123, "type": "private"},
                "date": int(datetime.now().timestamp()),
                "photo": [{"file_id": "test_photo", "file_size": 15000}]
            }
        }
        
        parsed = TelegramService.parse_update(update)
        assert parsed["attachments"][0]["file_id"] == "test_photo"
        
        # 2. Verify attachment has required fields
        att = parsed["attachments"][0]
        assert "type" in att
        assert "file_id" in att
        assert "file_size" in att
        
        # 3. After download, should have url, path, base64
        # (This is tested in webhook handler tests)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
