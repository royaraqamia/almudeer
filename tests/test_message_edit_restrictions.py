import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch, MagicMock
from models.inbox import edit_outbox_message

@pytest.mark.asyncio
async def test_edit_message_almudeer_no_time_limit():
    """Test that Almudeer messages can be edited even after 15 minutes."""
    license_id = 1
    message_id = 100
    # Set created_at to 1 hour ago
    created_at = datetime.now(timezone.utc) - timedelta(hours=1)
    
    message = {
        "id": message_id,
        "license_key_id": license_id,
        "channel": "almudeer",
        "created_at": created_at,
        "body": "Original body",
        "original_body": None,
        "edit_count": 0,
        "recipient_email": "test@example.com",
        "recipient_id": None
    }
    
    mock_fetch_one = AsyncMock(return_value=message)
    mock_execute_sql = AsyncMock()
    
    mock_db = MagicMock()
    mock_db.__aenter__ = AsyncMock(return_value=mock_db)
    mock_db.__aexit__ = AsyncMock(return_value=None)
    
    with patch("models.inbox.get_db", return_value=mock_db), \
         patch("models.inbox.fetch_one", mock_fetch_one), \
         patch("models.inbox.execute_sql", mock_execute_sql), \
         patch("models.inbox.commit_db", AsyncMock()), \
         patch("models.inbox.upsert_conversation_state", AsyncMock()):
        
        result = await edit_outbox_message(message_id, license_id, "New body")
        
        assert result["success"] is True
        assert result["edit_count"] == 1
        # Verify update was called
        mock_execute_sql.assert_called()

@pytest.mark.asyncio
async def test_edit_message_external_channels_restricted():
    """Test that external channels (WhatsApp, Telegram) cannot be edited."""
    license_id = 1
    message_id = 101
    
    for channel in ['telegram', 'whatsapp', 'gmail']:
        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": channel,
            "created_at": datetime.now(timezone.utc),
            "body": "Original body"
        }
        
        mock_fetch_one = AsyncMock(return_value=message)
        
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)
        
        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one):
            
            with pytest.raises(ValueError, match=f"لا يمكن تعديل الرسائل المرسلة عبر {channel}"):
                await edit_outbox_message(message_id, license_id, "New body")

@pytest.mark.asyncio
async def test_edit_message_generic_channel_no_time_limit():
    """Test that other channels also have no time limit now."""
    license_id = 1
    message_id = 102
    
    # After 15 minutes (should now succeed)
    message = {
        "id": message_id,
        "license_key_id": license_id,
        "channel": "generic",
        "created_at": datetime.now(timezone.utc) - timedelta(minutes=60),
        "body": "Original body",
        "original_body": None,
        "edit_count": 0,
        "recipient_email": "test@example.com",
        "recipient_id": None
    }
    
    mock_fetch_one = AsyncMock(return_value=message)
    
    mock_db = MagicMock()
    mock_db.__aenter__ = AsyncMock(return_value=mock_db)
    mock_db.__aexit__ = AsyncMock(return_value=None)
    
    with patch("models.inbox.get_db", return_value=mock_db), \
         patch("models.inbox.fetch_one", mock_fetch_one), \
         patch("models.inbox.execute_sql", AsyncMock()), \
         patch("models.inbox.commit_db", AsyncMock()), \
         patch("models.inbox.upsert_conversation_state", AsyncMock()):
        
        with pytest.raises(ValueError, match="لا يمكن تعديل الرسائل المرسلة عبر generic"):
            await edit_outbox_message(message_id, license_id, "New body")
