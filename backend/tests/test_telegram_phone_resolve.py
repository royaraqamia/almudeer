import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
import sys
import os
from db_helper import get_db, fetch_one

# Add the backend directory to sys.path to ensure imports work
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Mock environment variables before importing the service
with patch.dict(os.environ, {"TELEGRAM_API_ID": "12345", "TELEGRAM_API_HASH": "abcde"}):
    from services.telegram_phone_service import TelegramPhoneService

@pytest.fixture
def mock_service():
    with patch.dict(os.environ, {"TELEGRAM_API_ID": "12345", "TELEGRAM_API_HASH": "abcde"}):
        return TelegramPhoneService()

@pytest.mark.asyncio
async def test_resolve_telegram_entity_using_id(mock_service):
    """Test resolution using numeric ID (e.g., already in DB)"""
    client = MagicMock()
    client.get_entity = AsyncMock()
    logger = MagicMock()
    mock_entity = MagicMock()
    client.get_entity.return_value = mock_entity
    
    # Mock DB helpers to prevent OperationalError
    mock_conn = AsyncMock()
    with patch('db_helper.get_db', return_value=mock_conn), \
         patch('db_helper.fetch_one', new_callable=AsyncMock) as mock_fetch:
        result = await mock_service._resolve_telegram_entity(client, "123456", logger)
        
        assert result == mock_entity
        client.get_entity.assert_called_with(123456)

@pytest.mark.asyncio
async def test_resolve_telegram_entity_fallback_dialogs(mock_service):
    """Test resolution falling back to searching dialogs"""
    client = MagicMock()
    client.get_entity = AsyncMock()
    logger = MagicMock()
    
    # 1. get_entity fails
    client.get_entity.side_effect = Exception("Not found")
    
    # 2. Mock dialogs via iter_dialogs (Async Generator)
    mock_entity = MagicMock()
    mock_entity.id = 789
    mock_dialog = MagicMock()
    mock_dialog.entity = mock_entity
    mock_dialog.id = 966501234567
    mock_dialog.entity.phone = "966501234567"
    
    # Create a real async iterator for Telethon's iter_dialogs
    async def mock_iter_dialogs(*args, **kwargs):
        yield mock_dialog

    client.iter_dialogs = MagicMock(side_effect=mock_iter_dialogs)
    
    # Mock DB helpers
    mock_conn = AsyncMock()
    with patch('db_helper.get_db', return_value=mock_conn), \
         patch('db_helper.fetch_one', new_callable=AsyncMock) as mock_fetch:
        result = await mock_service._resolve_telegram_entity(client, "966501234567", logger)
        
        assert result == mock_entity
        client.iter_dialogs.assert_called_once()



@pytest.mark.asyncio
async def test_send_message_uses_resolver(mock_service):
    client = MagicMock()
    client.get_dialogs = AsyncMock()
    client.send_message = AsyncMock()
    
    with patch.object(mock_service, '_resolve_telegram_entity', new_callable=AsyncMock) as mock_resolve:
        mock_entity = MagicMock()
        mock_resolve.return_value = mock_entity
        
        # Mock other dependencies
        with patch.object(mock_service, 'create_client_from_session', return_value=client):
            with patch('logging_config.get_logger', return_value=MagicMock()):
                
                # Setup sent message return
                sent_msg = MagicMock()
                sent_msg.id = 999
                sent_msg.peer_id.user_id = 123456
                sent_msg.text = "hello"
                sent_msg.date = None
                
                # Mock _execute_with_retry to handle multiple calls
                async def side_effect(func, *args, **kwargs):
                    if func == client.get_dialogs:
                        return None
                    if func == client.send_message:
                        return sent_msg
                    return None
                
                mock_service._execute_with_retry = AsyncMock(side_effect=side_effect)
                
                result = await mock_service.send_message("session", "123456", "hello")
                
                assert result["id"] == 999
                mock_resolve.assert_called_once()
