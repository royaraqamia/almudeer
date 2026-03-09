"""
Al-Mudeer FCM Service Tests
Tests for Firebase Cloud Messaging logic
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from services.fcm_mobile_service import (
    send_fcm_notification,
    _send_fcm_v1,
    _send_fcm_legacy,
    save_fcm_token
)

class TestFCMService:
    
    @pytest.mark.asyncio
    async def test_send_fcm_v1_success(self):
        """Test sending via FCM V1 API"""
        with patch("services.fcm_mobile_service.FCM_V1_AVAILABLE", True), \
             patch("services.fcm_mobile_service._get_access_token", return_value="fake-token"), \
             patch("services.fcm_mobile_service.FCM_PROJECT_ID", "test-project"), \
             patch("services.fcm_mobile_service.FCM_PROJECT_ID", "test-project"), \
             patch("httpx.AsyncClient", return_value=AsyncMock()) as mock_client_cls:
            
            mock_instance = mock_client_cls.return_value
            mock_instance.__aenter__.return_value = mock_instance
            
            mock_post = AsyncMock()
            mock_post.return_value.status_code = 200
            mock_instance.post = mock_post
            
            result = await send_fcm_notification(
                token="device-token",
                title="Test",
                body="Message",
                data={"key": "value"}
            )
            
            assert result is True
            mock_post.assert_called_once()
            args, kwargs = mock_post.call_args
            assert "fcm.googleapis.com/v1" in args[0]
            assert kwargs["json"]["message"]["token"] == "device-token"
            assert kwargs["json"]["message"]["data"]["key"] == "value"

    @pytest.mark.asyncio
    async def test_send_fcm_v1_auth_failure_fallback(self):
        """Test fallback to return None if V1 auth fails"""
        with patch("services.fcm_mobile_service.FCM_V1_AVAILABLE", True), \
             patch("services.fcm_mobile_service._get_access_token", return_value="fake-token"), \
             patch("services.fcm_mobile_service.FCM_PROJECT_ID", "test-project"), \
             patch("services.fcm_mobile_service.FCM_PROJECT_ID", "test-project"), \
             patch("httpx.AsyncClient", return_value=AsyncMock()) as mock_client_cls:
            
            mock_instance = mock_client_cls.return_value
            mock_instance.__aenter__.return_value = mock_instance
            
            # Simulate 401 Unauthorized
            mock_post = AsyncMock()
            mock_post.return_value.status_code = 401
            mock_instance.post = mock_post
            
            # This calls internal _send_fcm_v1 directly to verify it returns None (triggering fallback logic in main wrapper)
            result = await _send_fcm_v1("token", "title", "body")
            assert result is None

    @pytest.mark.asyncio
    async def test_send_fcm_legacy_success(self):
        """Test sending via Legacy API"""
        with patch("services.fcm_mobile_service.FCM_SERVER_KEY", "server-key"), \
             patch("httpx.AsyncClient", return_value=AsyncMock()) as mock_client_cls:
            
            mock_instance = mock_client_cls.return_value
            mock_instance.__aenter__.return_value = mock_instance

            # Create a synchronous MagicMock for the response object
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_response.json.return_value = {"success": 1}
            
            # The post method is async, so it returns an awaitable that yields our mock_response
            mock_instance.post = AsyncMock(return_value=mock_response)
            
            result = await _send_fcm_legacy("token", "title", "body")
            
            assert result is True
            mock_instance.post.assert_called_once()
            assert "fcm.googleapis.com/fcm/send" in mock_instance.post.call_args[0][0]

    @pytest.mark.asyncio
    async def test_save_fcm_token_update(self):
        """Test saving/updating FCM token in DB"""
        from services.fcm_mobile_service import save_fcm_token
        
        # Mock DB helpers
        with patch("db_helper.get_db") as mock_db, \
             patch("db_helper.fetch_one", new_callable=AsyncMock) as mock_fetch, \
             patch("db_helper.execute_sql", new_callable=AsyncMock) as mock_exec, \
             patch("db_helper.commit_db", new_callable=AsyncMock):
            
            # Simulate existing token
            mock_fetch.side_effect = [{"id": 10}] # First fetch finds ID 10
            
            license_id = 99
            new_id = await save_fcm_token(license_id, "new-token", "android", "device-123")
            
            assert new_id == 10
            mock_exec.assert_called() # Should call update
            # Verify update query logic roughly (hard to matching exact SQL string without strict equality)
            
    @pytest.mark.asyncio
    async def test_save_fcm_token_insert(self):
        """Test inserting new FCM token"""
        with patch("db_helper.get_db") as mock_db, \
             patch("db_helper.fetch_one", new_callable=AsyncMock) as mock_fetch, \
             patch("db_helper.execute_sql", new_callable=AsyncMock) as mock_exec, \
             patch("db_helper.commit_db", new_callable=AsyncMock):
            
            # First fetch returns None (not found), Insert happens, Second fetch returns ID
            # In save_fcm_token, fetch_one is called for device_id (if exists) then token
            # Since device_id is None in this test, it's only called once for token, then once at the end.
            mock_fetch.side_effect = [None, {"id": 11}] 
            
            new_id = await save_fcm_token(99, "new-token", "android")
            
            assert new_id == 11
