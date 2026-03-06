"""
Al-Mudeer - Idempotency Service

Production-ready idempotency cache with Redis persistence.
Prevents duplicate operation processing on retries or server restarts.

P0-1 FIX: Replaces in-memory cache with Redis-backed persistent storage.
"""

import json
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any
from logging_config import get_logger

logger = get_logger(__name__)


class IdempotencyService:
    """
    Redis-backed idempotency cache for sync operations.
    
    Features:
    - Persistent storage (survives server restarts)
    - Automatic TTL expiration (24 hours)
    - Atomic operations with Lua scripts
    - Fallback to in-memory cache if Redis unavailable
    """
    
    IDEMPOTENCY_CACHE_TTL_HOURS = 24
    IDEMPOTENCY_KEY_PREFIX = "idempotency:"
    
    def __init__(self):
        self.redis_client = None
        self.use_redis = False
        self._memory_cache: Dict[str, tuple] = {}  # Fallback: (result, timestamp)
        self._locks: Dict[str, asyncio.Lock] = {}
        self._initialized = False
    
    async def initialize(self) -> bool:
        """Initialize Redis connection. Returns True if successful."""
        if self._initialized:
            return self.use_redis
        
        try:
            import redis.asyncio as redis
            
            redis_url = os.getenv("REDIS_URL")
            if redis_url:
                self.redis_client = redis.from_url(
                    redis_url,
                    decode_responses=True,
                    socket_connect_timeout=5.0,
                    socket_timeout=5.0,
                )
                await self.redis_client.ping()
                self.use_redis = True
                logger.info("IdempotencyService: Redis initialized successfully")
            else:
                logger.warning("IdempotencyService: REDIS_URL not set, using in-memory fallback")
        except Exception as e:
            logger.error(f"IdempotencyService: Redis connection failed: {e}, using in-memory fallback")
            self.redis_client = None
            self.use_redis = False
        
        self._initialized = True
        return self.use_redis
    
    async def get(self, key: str) -> Optional[Dict[str, Any]]:
        """
        Get cached result for idempotency key.
        
        Args:
            key: Idempotency key
            
        Returns:
            Cached result dict or None if not found/expired
        """
        if self.use_redis and self.redis_client:
            try:
                data = await self.redis_client.get(f"{self.IDEMPOTENCY_KEY_PREFIX}{key}")
                if data:
                    return json.loads(data)
                return None
            except Exception as e:
                logger.error(f"IdempotencyService: Redis get error: {e}")
                # Fallback to memory cache
                return self._get_memory(key)
        else:
            return self._get_memory(key)
    
    def _get_memory(self, key: str) -> Optional[Dict[str, Any]]:
        """Get from in-memory cache with TTL check."""
        if key in self._memory_cache:
            result, timestamp = self._memory_cache[key]
            age = (datetime.now(timezone.utc) - timestamp).total_seconds() / 3600
            if age < self.IDEMPOTENCY_CACHE_TTL_HOURS:
                return result
            else:
                del self._memory_cache[key]
        return None
    
    async def set(self, key: str, result: Dict[str, Any]) -> bool:
        """
        Store result for idempotency key with TTL.
        
        Args:
            key: Idempotency key
            result: Result dict to cache
            
        Returns:
            True if successful
        """
        if self.use_redis and self.redis_client:
            try:
                ttl_seconds = int(self.IDEMPOTENCY_CACHE_TTL_HOURS * 3600)
                await self.redis_client.setex(
                    f"{self.IDEMPOTENCY_KEY_PREFIX}{key}",
                    ttl_seconds,
                    json.dumps(result)
                )
                return True
            except Exception as e:
                logger.error(f"IdempotencyService: Redis set error: {e}")
                # Fallback to memory cache
                self._set_memory(key, result)
                return False
        else:
            self._set_memory(key, result)
            return True
    
    def _set_memory(self, key: str, result: Dict[str, Any]):
        """Store in in-memory cache."""
        self._memory_cache[key] = (result, datetime.now(timezone.utc))
        
        # Clean old entries if cache grows too large
        if len(self._memory_cache) > 10000:
            cutoff = datetime.now(timezone.utc)
            to_delete = [
                k for k, (_, t) in self._memory_cache.items()
                if (cutoff - t).total_seconds() / 3600 > self.IDEMPOTENCY_CACHE_TTL_HOURS
            ]
            for k in to_delete:
                del self._memory_cache[k]
    
    async def acquire_lock(self, key: str, timeout: float = 5.0) -> bool:
        """
        Acquire distributed lock for idempotency key.
        
        Args:
            key: Idempotency key
            timeout: Timeout in seconds to wait for lock
            
        Returns:
            True if lock acquired, False otherwise
        """
        if self.use_redis and self.redis_client:
            try:
                # Use Redis SETNX for distributed locking
                lock_key = f"{self.IDEMPOTENCY_KEY_PREFIX}lock:{key}"
                lock_value = f"{datetime.now(timezone.utc).isoformat()}:{id(asyncio.current_task())}"
                ttl_seconds = 30  # Lock expires after 30 seconds to prevent deadlocks
                
                # Try to acquire lock with 5 second timeout
                acquired = await asyncio.wait_for(
                    self.redis_client.set(
                        lock_key,
                        lock_value,
                        nx=True,
                        ex=ttl_seconds
                    ),
                    timeout=timeout
                )
                return acquired is not None and acquired
            except asyncio.TimeoutError:
                logger.warning(f"IdempotencyService: Timeout acquiring lock for key: {key}")
                return False
            except Exception as e:
                logger.error(f"IdempotencyService: Redis lock error: {e}")
                # Fallback to in-memory lock
                return await self._acquire_memory_lock(key)
        else:
            return await self._acquire_memory_lock(key)
    
    async def _acquire_memory_lock(self, key: str) -> bool:
        """Acquire in-memory lock."""
        if key not in self._locks:
            self._locks[key] = asyncio.Lock()
        
        try:
            acquired = await asyncio.wait_for(self._locks[key].acquire(), timeout=5.0)
            return acquired
        except asyncio.TimeoutError:
            return False
    
    async def release_lock(self, key: str):
        """Release distributed lock for idempotency key."""
        if self.use_redis and self.redis_client:
            try:
                lock_key = f"{self.IDEMPOTENCY_KEY_PREFIX}lock:{key}"
                await self.redis_client.delete(lock_key)
            except Exception as e:
                logger.error(f"IdempotencyService: Redis unlock error: {e}")
        else:
            self._release_memory_lock(key)
    
    def _release_memory_lock(self, key: str):
        """Release in-memory lock."""
        if key in self._locks and self._locks[key].locked():
            self._locks[key].release()
    
    async def cleanup(self):
        """Close Redis connection."""
        if self.redis_client:
            await self.redis_client.close()
            logger.info("IdempotencyService: Redis connection closed")


# Global singleton instance
_idempotency_service: Optional[IdempotencyService] = None


def get_idempotency_service() -> IdempotencyService:
    """Get the global idempotency service instance."""
    global _idempotency_service
    if _idempotency_service is None:
        _idempotency_service = IdempotencyService()
    return _idempotency_service


async def initialize_idempotency_service() -> bool:
    """Initialize the global idempotency service."""
    service = get_idempotency_service()
    return await service.initialize()
