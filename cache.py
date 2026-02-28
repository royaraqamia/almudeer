"""
Caching layer for Al-Mudeer
Supports both in-memory and Redis caching
"""

import os
import json
import hashlib
from typing import Optional, Any
from datetime import timedelta
from cachetools import TTLCache

# Try to import Redis (optional)
try:
    import redis
    REDIS_AVAILABLE = True
except ImportError:
    REDIS_AVAILABLE = False
    redis = None


class CacheManager:
    """Unified cache manager supporting both in-memory and Redis"""
    
    def __init__(self):
        self.redis_client: Optional[Any] = None
        self.use_redis = False
        
        # In-memory cache as fallback
        self.memory_cache = TTLCache(maxsize=1000, ttl=300)  # 5 min TTL
        
        # Try to connect to Redis if available
        redis_url = os.getenv("REDIS_URL")
        if REDIS_AVAILABLE and redis_url:
            try:
                self.redis_client = redis.from_url(redis_url, decode_responses=True)
                # Test connection
                self.redis_client.ping()
                self.use_redis = True
            except Exception:
                # Fallback to in-memory cache
                self.redis_client = None
                self.use_redis = False
    
    def _make_key(self, prefix: str, *args) -> str:
        """
        Create a cache key from prefix and arguments.
        
        SECURITY FIX #9: Use SHA-256 instead of MD5 to prevent collision attacks.
        While MD5 collisions are theoretical for cache keys, SHA-256 provides
        better security margin for sensitive data caching.
        """
        key_data = f"{prefix}:{':'.join(str(arg) for arg in args)}"
        return hashlib.sha256(key_data.encode()).hexdigest()
    
    async def get(self, key: str) -> Optional[Any]:
        """Get value from cache"""
        # Try Redis first
        if self.use_redis and self.redis_client:
            try:
                # Redis client is sync, but we're in async context
                # Use asyncio.to_thread for sync operations in async context
                import asyncio
                value = await asyncio.to_thread(self.redis_client.get, key)
                if value:
                    return json.loads(value)
            except Exception:
                pass
        
        # Fallback to memory cache
        return self.memory_cache.get(key)
    
    async def set(self, key: str, value: Any, ttl: int = 300) -> None:
        """Set value in cache with TTL (seconds)"""
        # Try Redis first
        if self.use_redis and self.redis_client:
            try:
                # Redis client is sync, use asyncio.to_thread
                import asyncio
                await asyncio.to_thread(
                    self.redis_client.setex, key, ttl, json.dumps(value)
                )
                return
            except Exception:
                pass
        
        # Fallback to memory cache
        self.memory_cache[key] = value
    
    async def delete(self, key: str) -> None:
        """Delete value from cache"""
        if self.use_redis and self.redis_client:
            try:
                # Redis client is sync, use asyncio.to_thread
                import asyncio
                await asyncio.to_thread(self.redis_client.delete, key)
            except Exception:
                pass
        
        if key in self.memory_cache:
            del self.memory_cache[key]
    
    async def get_or_set(self, key: str, func, ttl: int = 300) -> Any:
        """Get from cache or compute and cache the result"""
        value = await self.get(key)
        if value is not None:
            return value
        
        # Compute value
        if callable(func):
            # Check if function is async
            if hasattr(func, '__code__') and func.__code__.co_flags & 0x80:  # CO_COROUTINE flag
                value = await func()
            else:
                value = func()
        else:
            value = func
        
        # Cache it
        await self.set(key, value, ttl)
        return value

    async def increment(self, key: str, amount: int = 1) -> int:
        """Increment value in cache (atomic in Redis)"""
        if self.use_redis and self.redis_client:
            try:
                import asyncio
                return await asyncio.to_thread(self.redis_client.incr, key, amount)
            except Exception:
                pass
        
        # Fallback to memory (not atomic across processes)
        try:
            current = self.memory_cache.get(key, 0)
            if isinstance(current, str): 
                current = int(current)
            new_val = current + amount
            self.memory_cache[key] = new_val
            return new_val
        except Exception:
            return 0

    async def expire(self, key: str, ttl: int) -> bool:
        """Set expiration for a key in seconds"""
        if self.use_redis and self.redis_client:
            try:
                import asyncio
                return await asyncio.to_thread(self.redis_client.expire, key, ttl)
            except Exception:
                pass
        
        # Fallback: TTLCache has fixed TTL.
        return False


# Global cache instance
cache = CacheManager()


# Convenience functions
async def cache_license_validation(license_key: str, result: dict, ttl: int = 300) -> None:
    """Cache license validation result"""
    key = f"license:{hashlib.sha256(license_key.encode()).hexdigest()}"
    await cache.set(key, result, ttl)


async def get_cached_license_validation(license_key: str) -> Optional[dict]:
    """Get cached license validation result"""
    key = f"license:{hashlib.sha256(license_key.encode()).hexdigest()}"
    return await cache.get(key)

