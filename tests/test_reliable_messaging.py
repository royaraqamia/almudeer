
import asyncio
import json
import base64
from unittest.mock import MagicMock, AsyncMock, patch
import sys
import os

# Create a mock for the database connection context manager
class MockDBContext:
    async def __aenter__(self):
        return MagicMock()
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass

async def test_send_message_with_captions():
    print("Starting verification of _send_message with captions...")
    
    # Mocking dependencies
    with patch("workers.get_db") as mock_get_db, \
         patch("workers.fetch_all", new_callable=AsyncMock) as mock_fetch_all, \
         patch("workers.fetch_one", new_callable=AsyncMock) as mock_fetch_one, \
         patch("workers.mark_outbox_sent", new_callable=AsyncMock) as mock_mark_sent, \
         patch("workers.mark_outbox_failed", new_callable=AsyncMock) as mock_mark_failed, \
         patch("services.delivery_status.save_platform_message_id", new_callable=AsyncMock) as mock_save_pid, \
         patch("workers.get_whatsapp_config", new_callable=AsyncMock) as mock_wa_config, \
         patch("workers.get_telegram_phone_session_data", new_callable=AsyncMock) as mock_tg_session:
         
        mock_get_db.return_value = MockDBContext()
        
        # Helper to setup a message
        def setup_message(channel, body="Hello", attachments=None):
            att_str = json.dumps(attachments) if attachments else None
            mock_fetch_all.return_value = [{
                "id": 1,
                "license_key_id": 1,
                "body": body,
                "recipient_id": "12345",
                "recipient_email": "test@example.com",
                "attachments": att_str,
                "inbox_message_id": 100,
                "sender_name": "Source",
                "sender_contact": "source_contact",
                "sender_id": "source_id",
                "platform_message_id": None
            }]

        from workers import MessagePoller
        poller = MessagePoller()
        
        # Test Case 1: WhatsApp with Image and Caption
        print("\nTest 1: WhatsApp Image + Caption")
        setup_message("whatsapp", body="Check this photo", attachments=[{"filename": "test.jpg", "base64": base64.b64encode(b"fake_data").decode()}])
        mock_wa_config.return_value = {"phone_number_id": "pid", "access_token": "token"}
        
        with patch("workers.WhatsAppService") as MockWS:
            ws_instance = MockWS.return_value
            ws_instance.upload_media = AsyncMock(return_value="media_id_123")
            ws_instance.send_image_message = AsyncMock(return_value={"success": True, "message_id": "wa_msg_id"})
            
            await poller._send_message(outbox_id=1, license_id=1, channel="whatsapp")
            
            ws_instance.send_image_message.assert_called_once_with("12345", "media_id_123", caption="Check this photo", reply_to_message_id=None)
            mock_mark_sent.assert_called_once()
            print("SUCCESS: WhatsApp image sent with caption.")

        # Reset mocks
        mock_mark_sent.reset_mock()
        
        # Test Case 2: Telegram Bot with Document and Caption
        print("\nTest 2: Telegram Bot Document + Caption")
        setup_message("telegram_bot", body="Here is the PDF", attachments=[{"filename": "doc.pdf", "base64": base64.b64encode(b"pdf_data").decode()}])
        mock_fetch_one.return_value = {"bot_token": "bot_token_123"}
        
        with patch("workers.TelegramService") as MockTS:
            ts_instance = MockTS.return_value
            ts_instance.send_document = AsyncMock(return_value={"message_id": "tg_msg_id"})
            
            await poller._send_message(outbox_id=1, license_id=1, channel="telegram_bot")
            
            # Note: in workers.py, send_document for bot is called with caption=caption
            ts_instance.send_document.assert_called_once()
            args, kwargs = ts_instance.send_document.call_args
            if kwargs.get("caption") == "Here is the PDF":
                print("SUCCESS: Telegram Bot document sent with caption.")
            else:
                print(f"FAILURE: Caption mismatch: {kwargs.get('caption')}")

        # Test Case 3: Email with Multiple Attachments
        print("\nTest 3: Email with Multiple Attachments")
        atts = [
            {"filename": "file1.txt", "base64": base64.b64encode(b"data1").decode()},
            {"filename": "file2.jpg", "base64": base64.b64encode(b"data2").decode()}
        ]
        setup_message("email", body="See attached files", attachments=atts)
        
        with patch("services.gmail_api_service.GmailAPIService") as MockGS, \
             patch("models.email_config.get_email_oauth_tokens", new_callable=AsyncMock) as mock_tokens, \
             patch("services.gmail_oauth_service.GmailOAuthService") as MockOAuth:
            mock_tokens.return_value = {"access_token": "at"}
            gs_instance = MockGS.return_value
            gs_instance.send_message = AsyncMock(return_value={"id": "gmail_id"})
            
            await poller._send_message(outbox_id=1, license_id=1, channel="email")
            
            gs_instance.send_message.assert_called_once()
            args, kwargs = gs_instance.send_message.call_args
            if len(kwargs.get("attachments", [])) == 2:
                print("SUCCESS: Email sent with 2 attachments.")
            else:
                print(f"FAILURE: Attachment count mismatch: {len(kwargs.get('attachments', []))}")

    print("\nVerification completed.")

async def test_internal_channels():
    print("\nStarting verification of internal channels (saved, almudeer)...")
    
    with patch("workers.get_db") as mock_get_db, \
         patch("workers.fetch_all", new_callable=AsyncMock) as mock_fetch_all, \
         patch("workers.fetch_one", new_callable=AsyncMock) as mock_fetch_one, \
         patch("workers.mark_outbox_sent", new_callable=AsyncMock) as mock_mark_sent, \
         patch("workers.mark_outbox_failed", new_callable=AsyncMock) as mock_mark_failed, \
         patch("models.inbox.upsert_conversation_state", new_callable=AsyncMock) as mock_upsert_global, \
         patch("services.delivery_status.save_platform_message_id", new_callable=AsyncMock) as mock_save_pid:

        mock_get_db.return_value = MockDBContext()
        from workers import MessagePoller
        poller = MessagePoller()

        # Test Case 4: Saved Messages
        print("Test 4: Saved Messages (self-chat)")
        mock_fetch_all.return_value = [{
            "id": 10, "license_key_id": 1, "body": "My note", "recipient_id": "__saved_messages__",
            "attachments": None, "inbox_message_id": 101, "sender_contact": "me", "sender_name": "Me", "sender_id": "me",
            "platform_message_id": None
        }]
        await poller._send_message(outbox_id=10, license_id=1, channel="saved")
        mock_mark_sent.assert_called_once()
        print("SUCCESS: Saved message marked as sent.")

        # Test Case 5: Almudeer Internal Delivery
        print("\nTest 5: Almudeer Internal Delivery")
        mock_fetch_all.return_value = [{
            "id": 11, "license_key_id": 1, "body": "Hello Peer", "recipient_email": "peer_user",
            "attachments": None, "inbox_message_id": 102, "sender_contact": "me", "sender_name": "Me", "sender_id": "me",
            "platform_message_id": None
        }]
        mock_fetch_one.side_effect = [
            {"id": 2, "company_name": "Target Company"}, # Target license holder
            {"username": "me", "company_name": "My Company"} # Sender license info
        ]
        
        with patch("models.inbox.save_inbox_message", new_callable=AsyncMock) as mock_save_inbox, \
             patch("services.websocket_manager.broadcast_new_message", new_callable=AsyncMock) as mock_broadcast, \
             patch("services.websocket_manager.broadcast_message_status_update", new_callable=AsyncMock) as mock_status_broadcast, \
             patch("models.inbox.upsert_conversation_state", new_callable=AsyncMock) as mock_upsert:
            
            mock_save_inbox.return_value = 500 # new inbox id
            await poller._send_message(outbox_id=11, license_id=1, channel="almudeer")
            
            mock_save_inbox.assert_called_once()
            mock_broadcast.assert_called_once()
            mock_status_broadcast.assert_called_once()
            assert mock_upsert.call_count == 2
            mock_mark_sent.assert_called()
            print("SUCCESS: Almudeer internal message delivered, broadcasted, and states updated.")

if __name__ == "__main__":
    import os
    import sys
    # Add the backend directory to sys.path
    backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if backend_dir not in sys.path:
        sys.path.append(backend_dir)
    
    async def run_all():
        await test_send_message_with_captions()
        await test_internal_channels()
    asyncio.run(run_all())
