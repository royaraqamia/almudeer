"""
Al-Mudeer Miscellaneous Routes Tests
Tests for Subscription, System/Integrations, and Version routes
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock

# Mock authentication
@pytest.fixture
def mock_auth_data():
    return {"is_admin": True, "license_id": 1}

@pytest.fixture
def mock_license_dependency():
    with patch("dependencies.get_license_from_header", return_value={"license_id": 1}):
        yield

class TestSubscriptionRoutes:
    
    @pytest.mark.asyncio
    async def test_create_subscription(self, mock_auth_data):
        from routes.subscription import create_subscription, SubscriptionCreate
        
        with patch("routes.subscription.generate_license_key", new_callable=AsyncMock) as mock_gen, \
             patch("db_helper.get_db") as mock_get_db, \
             patch("db_helper.fetch_one", new_callable=AsyncMock) as mock_fetch_one:
            
            mock_gen.return_value = "KEY-123"
            mock_fetch_one.return_value = None  # Username not taken
            
            mock_db = AsyncMock()
            mock_get_db.return_value.__aenter__.return_value = mock_db
            
            payload = SubscriptionCreate(
                full_name="Test Company",
                days_valid=30,
                username="test_user"
            )
            
            response = await create_subscription(payload, auth=mock_auth_data)
            
            assert response.success is True
            assert response.subscription_key == "KEY-123"
            assert getattr(response, "full_name", getattr(response, "company_name", None)) == "Test Company"

    @pytest.mark.asyncio
    async def test_list_subscriptions(self, mock_auth_data):
        from routes.subscription import list_subscriptions
        
        # Mock DB helpers directly
        with patch("db_helper.get_db") as mock_get_db, \
             patch("db_helper.fetch_all", new_callable=AsyncMock) as mock_fetch:
            
            mock_db = AsyncMock()
            mock_get_db.return_value.__aenter__.return_value = mock_db
            
            mock_fetch.return_value = [{"id": 1, "full_name": "Test Co", "is_active": 1, "created_at": "2023-01-01"}]
            
            response = await list_subscriptions(limit=10, auth=mock_auth_data)
            
            assert response.total == 1
            assert response.subscriptions[0].get("full_name") == "Test Co" or response.subscriptions[0].get("company_name") == "Test Co"


class TestSystemRoutes:
    


    @pytest.mark.asyncio
    async def test_list_integration_accounts(self, mock_license_dependency):
        from routes.system_routes import list_integration_accounts
        
        with patch("routes.system_routes.get_email_config", new_callable=AsyncMock) as mock_email, \
             patch("routes.system_routes.get_telegram_config", new_callable=AsyncMock) as mock_tg, \
             patch("routes.system_routes.get_telegram_phone_session", new_callable=AsyncMock), \
             patch("routes.system_routes.get_whatsapp_config", new_callable=AsyncMock):
             
            mock_email.return_value = {"email_address": "test@gmail.com", "is_active": True}
            mock_tg.return_value = None
            
            response = await list_integration_accounts({"license_id": 1})
            
            accounts = response["accounts"]
            assert len(accounts) >= 1
            assert accounts[0].id == "email"
            assert accounts[0].display_name == "test@gmail.com"

class TestVersionRoutes:
    
    @pytest.mark.asyncio
    async def test_update_check(self):
        """Test the version update check endpoint"""
        from routes.version import check_update, UpdateCheckResponse
        
        # Mock DB logic to prevent OperationalError
        with patch("routes.version.get_app_config", new_callable=AsyncMock) as mock_config, \
             patch("routes.version.get_all_app_config", new_callable=AsyncMock) as mock_all_config, \
             patch("routes.version._get_changelog", new_callable=AsyncMock) as mock_changelog:
            
            mock_config.return_value = "1.0.0" # min build
            mock_all_config.return_value = {
                "min_android_version": "1.0.0",
                "latest_android_version": "1.1.0",
                "android_download_url": "https://example.com/app.apk",
                "android_release_notes": "New features!"
            }
            mock_changelog.return_value = {"version": "1.1.0", "notes": "New features!"}
            
            mock_request = MagicMock()
            response = await check_update(
                request=mock_request,
                current_version="1.0.0",
                platform="android"
            )
            
            assert isinstance(response, dict)
            assert response["update_available"] is True
            assert response["version"] == "1.0.0"
            assert "update_url" in response


