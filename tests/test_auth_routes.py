"""
Al-Mudeer Auth Routes Tests
API tests for authentication endpoints
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


# ============ Login Request Models ============

class TestAuthModels:
    """Tests for authentication request/response models"""
    
    def test_login_request_model(self):
        """Test LoginRequest model accepts valid data"""
        from routes.auth import LoginRequest
        # Login with license key
        req = LoginRequest(license_key="MUDEER-TEST-1234")
        assert req.license_key == "MUDEER-TEST-1234"

    def test_token_response_model(self):
        """Test TokenResponse model"""
        from routes.auth import TokenResponse
        
        resp = TokenResponse(
            access_token="eyJ...",
            refresh_token="refresh_token_here",
            expires_in=3600,
            user={"email": "user@example.com", "role": "admin"}
        )
        
        assert resp.token_type == "bearer"
        assert resp.expires_in == 3600
    
    def test_refresh_request_model(self):
        """Test RefreshRequest model"""
        from routes.auth import RefreshRequest
        
        req = RefreshRequest(refresh_token="valid_refresh_token")
        assert req.refresh_token == "valid_refresh_token"


# ============ Login Endpoint ============

class TestLoginEndpoint:
    """Tests for /api/auth/login endpoint"""
    
    @pytest.mark.asyncio
    async def test_login_missing_credentials(self):
        """Test login fails without credentials"""
        from main import app
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/auth/login",
                json={}
            )
            
            # Should return error for missing credentials
            assert response.status_code in [400, 422, 401]
    
    @pytest.mark.asyncio
    async def test_login_invalid_license_key(self):
        """Test login fails with invalid license key"""
        from main import app
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/auth/login",
                json={"license_key": "INVALID-KEY-12345"}
            )
            
            # Should return unauthorized
            assert response.status_code in [401, 404]


# ============ Token Refresh Endpoint ============

class TestTokenRefreshEndpoint:
    """Tests for /api/auth/refresh endpoint"""
    
    @pytest.mark.asyncio
    async def test_refresh_invalid_token(self):
        """Test refresh fails with invalid token"""
        from main import app
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/auth/refresh",
                json={"refresh_token": "invalid_token_here"}
            )
            
            assert response.status_code in [401, 400]


# ============ Current User Endpoint ============

class TestGetCurrentUserEndpoint:
    """Tests for /api/auth/me endpoint"""
    
    @pytest.mark.asyncio
    async def test_get_me_without_auth(self):
        """Test /me fails without authentication"""
        from main import app
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/auth/me")
            
            # Should require authentication
            assert response.status_code in [401, 403]
    
    @pytest.mark.asyncio
    async def test_get_me_with_invalid_token(self):
        """Test /me fails with invalid token"""
        from main import app
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get(
                "/api/auth/me",
                headers={"Authorization": "Bearer invalid_token"}
            )
            
            assert response.status_code in [401, 403]


# ============ Logout Endpoint ============

class TestLogoutEndpoint:
    """Tests for /api/auth/logout endpoint"""
    
    @pytest.mark.asyncio
    async def test_logout_without_auth(self):
        """Test logout fails without authentication"""
        from main import app
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post("/api/auth/logout")
            
            assert response.status_code in [401, 403]


# ============ JWT Token Functions ============

class TestJWTTokenFunctions:
    """Tests for JWT token creation and verification"""
    
    def test_create_and_verify_token(self):
        """Test JWT token creation and verification"""
        from services.jwt_auth import create_access_token, verify_token, TokenType
        
        # Create token (returns tuple: token_str, jti, expiry)
        token, jti, expiry = create_access_token({
            "sub": "test@example.com",
            "license_id": 1,
            "role": "admin"
        })
        
        assert token is not None
        
        # Verify token
        payload = verify_token(token, TokenType.ACCESS)
        
        assert payload is not None
        assert payload["sub"] == "test@example.com"
        assert payload["license_id"] == 1
    
    def test_refresh_token_has_jti(self):
        """Test refresh token contains JTI for revocation"""
        from services.jwt_auth import create_refresh_token, verify_token, TokenType
        
        token = create_refresh_token({"sub": "user@test.com"})
        payload = verify_token(token, TokenType.REFRESH)
        
        assert "jti" in payload
    
    def test_invalid_token_returns_none(self):
        """Test invalid token verification returns None"""
        from services.jwt_auth import verify_token, TokenType
        
        result = verify_token("completely.invalid.token", TokenType.ACCESS)
        
        assert result is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
