"""
Al-Mudeer Service Tests
Unit tests for individual services
"""

import pytest
from unittest.mock import AsyncMock, patch
from datetime import datetime


# ============ JWT Auth Service ============

class TestJWTAuth:
    """Tests for JWT authentication service"""
    
    @pytest.mark.anyio
    async def test_create_access_token(self):
        """Test access token creation"""
        from services.jwt_auth import create_access_token, verify_token, TokenType
        
        data = {"sub": "user@test.com", "license_id": 1}
        # access_token used to return just the token, now returns (token, jti, expiry)
        token, jti, expiry = create_access_token(data)
        
        assert token is not None
        assert isinstance(token, str)
        assert isinstance(jti, str)
        assert isinstance(expiry, datetime)

        payload = verify_token(token, TokenType.ACCESS)
        
        assert payload is not None
        assert payload["sub"] == "user@test.com"
        assert payload["type"] == "access"
    
    def test_create_refresh_token(self):
        """Test refresh token creation"""
        from services.jwt_auth import create_refresh_token, verify_token, TokenType
        
        token = create_refresh_token({"sub": "user@test.com"})
        payload = verify_token(token, TokenType.REFRESH)
        
        assert payload is not None
        assert payload["type"] == "refresh"
        assert "jti" in payload  # Unique ID for revocation
    
    @pytest.mark.anyio
    async def test_token_pair(self):
        """Test creating token pair"""
        from services.jwt_auth import create_token_pair
        
        tokens = await create_token_pair("user@test.com", license_id=1, role="admin")
        
        assert "access_token" in tokens
        assert "refresh_token" in tokens
        assert tokens["token_type"] == "bearer"
        assert tokens["expires_in"] > 0
    
    def test_invalid_token(self):
        """Test invalid token verification"""
        from services.jwt_auth import verify_token, TokenType
        
        result = verify_token("invalid-token", TokenType.ACCESS)
        assert result is None
    



# ============ Pagination Service ============

class TestPagination:
    """Tests for pagination service"""
    
    def test_pagination_params(self):
        """Test pagination parameter defaults"""
        from services.pagination import PaginationParams
        
        params = PaginationParams()
        assert params.page == 1
        assert params.page_size == 20
        assert params.offset == 0
        assert params.limit == 20
    
    def test_pagination_params_custom(self):
        """Test custom pagination parameters"""
        from services.pagination import PaginationParams
        
        params = PaginationParams(page=3, page_size=50)
        assert params.page == 3
        assert params.page_size == 50
        assert params.offset == 100  # (3-1) * 50
    
    def test_pagination_max_size(self):
        """Test page size limit enforced"""
        from services.pagination import PaginationParams
        
        params = PaginationParams(page_size=500)  # Over limit
        assert params.page_size == 100  # Max enforced
    
    def test_paginate_function(self):
        """Test paginate helper"""
        from services.pagination import paginate, PaginationParams
        
        items = ["a", "b", "c"]
        params = PaginationParams(page=1, page_size=10)
        result = paginate(items, total=100, params=params)
        
        assert result.items == items
        assert result.total == 100
        assert result.total_pages == 10
        assert result.has_next is True
        assert result.has_prev is False


# ============ Request Batcher Service ============

class TestRequestBatcher:
    """Tests for request batching service"""
    
    def test_batch_key_generation(self):
        """Test batch key is generated correctly"""
        from services.request_batcher import RequestBatcher
        
        batcher = RequestBatcher()
        key1 = batcher._get_batch_key("short message", license_id=1)
        key2 = batcher._get_batch_key("another short", license_id=1)
        key3 = batcher._get_batch_key("short message", license_id=2)
        
        # Same license and length category = same key
        assert key1 == key2
        # Different license = different key
        assert key1 != key3


# ============ Cache Service ============

class TestCache:
    """Tests for caching service"""
    
    @pytest.mark.anyio
    async def test_memory_cache_set_get(self):
        """Test in-memory cache operations"""
        from cache import CacheManager
        
        manager = CacheManager()
        
        await manager.set("test_key", {"data": "value"}, ttl=60)
        result = await manager.get("test_key")
        
        assert result == {"data": "value"}
    
    @pytest.mark.anyio
    async def test_cache_miss(self):
        """Test cache miss returns None"""
        from cache import CacheManager
        
        manager = CacheManager()
        result = await manager.get("nonexistent_key")
        
        assert result is None


# ============ Security Functions ============

class TestSecurity:
    """Tests for security functions"""
    
    def test_sanitize_string_basic(self):
        """Test basic string sanitization"""
        from security import sanitize_string
        
        result = sanitize_string("Hello World")
        assert result == "Hello World"
    
    def test_sanitize_string_xss(self):
        """Test XSS prevention"""
        from security import sanitize_string
        
        result = sanitize_string("<script>alert('xss')</script>")
        assert "<script>" not in result
        assert "alert" not in result or "&" in result
    
    def test_sanitize_email_valid(self):
        """Test valid email sanitization"""
        from security import sanitize_email
        
        result = sanitize_email("test@example.com")
        assert result == "test@example.com"
    
    def test_sanitize_email_invalid(self):
        """Test invalid email returns None"""
        from security import sanitize_email
        
        result = sanitize_email("not-an-email")
        assert result is None
    
    def test_sanitize_phone(self):
        """Test phone sanitization"""
        from security import sanitize_phone
        
        result = sanitize_phone("+966501234567")
        assert result is not None
        assert "966" in result


# ============ LLM Response Cache Tests Removed ============
