"""
Al-Mudeer Backend Tests
Basic tests for core functionality
"""

import pytest
from httpx import AsyncClient, ASGITransport


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_health_check(test_client):
    """Test health endpoint returns 200"""
    response = await test_client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


@pytest.mark.anyio
async def test_health_live(test_client):
    """Test liveness probe"""
    response = await test_client.get("/health/live")
    assert response.status_code == 200
    assert response.json()["status"] == "alive"





@pytest.mark.anyio
async def test_auth_login_invalid(test_client):
    """Test login with invalid credentials"""
    response = await test_client.post(
        "/api/auth/login",
        json={"license_key": "invalid-key-12345"}
    )
    assert response.status_code == 401


# ============ Unit Tests ============

def test_sanitize_message():
    """Test message sanitization"""
    from security import sanitize_message
    
    # Normal message should pass through
    result = sanitize_message("Hello world")
    assert result == "Hello world"
    
    # XSS should be escaped
    result = sanitize_message("<script>alert('xss')</script>")
    assert "<script>" not in result




@pytest.mark.anyio
async def test_jwt_tokens():
    """Test JWT token creation and verification"""
    from services.jwt_auth import create_token_pair, verify_token, TokenType
    
    tokens = await create_token_pair(
        user_id="test@example.com",
        license_id=1,
        role="user"
    )
    
    assert "access_token" in tokens
    assert "refresh_token" in tokens
    
    # Verify access token
    payload = verify_token(tokens["access_token"], TokenType.ACCESS)
    assert payload is not None
    assert payload["sub"] == "test@example.com"
    assert payload["license_id"] == 1



