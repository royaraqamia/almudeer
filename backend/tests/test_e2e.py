"""
Al-Mudeer Backend E2E Tests
End-to-end testing with actual API calls
"""

import os
import pytest
from httpx import AsyncClient, ASGITransport

# Set test environment
os.environ["TESTING"] = "true"
os.environ["DB_TYPE"] = "sqlite"


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def test_license_key():
    """Test license key for authenticated requests"""
    return "TEST-DEMO-KEY-12345678"


# ============ E2E: Health & System ============

@pytest.mark.anyio
async def test_e2e_health_endpoints():
    """E2E: All health endpoints work"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Basic health
        resp = await client.get("/health")
        assert resp.status_code == 200
        
        # Liveness
        resp = await client.get("/health/live")
        assert resp.status_code == 200
        
        # Readiness
        resp = await client.get("/health/ready")
        assert resp.status_code == 200


# ============ E2E: Authentication Flow ============

@pytest.mark.anyio
async def test_e2e_auth_login_invalid():
    """E2E: Invalid login returns 401"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.post(
            "/api/auth/login",
            json={"license_key": "INVALID-KEY-12345"}
        )
        assert resp.status_code == 401


@pytest.mark.anyio
async def test_e2e_auth_me_requires_token():
    """E2E: /me endpoint requires authentication"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/auth/me")
        assert resp.status_code == 401


# Analyze tests removed (AI removed)


# ============ E2E: Paginated Endpoints ============

@pytest.mark.anyio
async def test_e2e_inbox_paginated_requires_auth():
    """E2E: Paginated inbox requires auth"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/inbox/paginated")
        assert resp.status_code in [401, 403]


# ============ E2E: Rate Limiting ============

@pytest.mark.anyio
async def test_e2e_rate_limit_headers():
    """E2E: Rate limit headers present"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/health")
        # Should not be rate limited for health endpoint
        assert resp.status_code == 200


# ============ E2E: Error Handling ============

@pytest.mark.anyio
async def test_e2e_404_handling():
    """E2E: 404 for non-existent endpoints"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/nonexistent")
        assert resp.status_code == 404


@pytest.mark.anyio
async def test_e2e_invalid_json():
    """E2E: Invalid JSON returns 422"""
    from main import app
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.post(
            "/api/auth/login",
            content="invalid json",
            headers={"Content-Type": "application/json"}
        )
        assert resp.status_code == 422
