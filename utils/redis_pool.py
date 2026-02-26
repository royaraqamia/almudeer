"""
Redis Connection Pool Utility
Provides a singleton Redis connection pool for efficient connection reuse.
"""

import os
from typing import Optional
from logging_config import get_logger

logger = get_logger(__name__)


class RedisPool:
    """Singleton Redis connection pool"""
    
    _instance: Optional["RedisPool"] = None
    _redis_client = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    async def initialize(self) -> bool:
        """Initialize Redis connection pool"""
        if self._redis_client is not None:
            return True
        
        redis_url = os.getenv("REDIS_URL")
        if not redis_url:
            logger.info("Redis URL not configured, pool disabled")
            return False
        
        try:
            import redis.asyncio as aioredis
            # Create connection pool with optimal settings
            self._redis_client = await aioredis.from_url(
                redis_url,
                decode_responses=True,
                max_connections=50,  # Adjust based on load
                socket_timeout=5,
                socket_connect_timeout=5,
                retry_on_timeout=True,
            )
            await self._redis_client.ping()
            logger.info("Redis connection pool initialized")
            return True
        except Exception as e:
            logger.warning(f"Failed to initialize Redis pool: {e}")
            return False
    
    async def get_client(self):
        """Get Redis client from pool"""
        if not await self.initialize():
            return None
        return self._redis_client
    
    async def close(self):
        """Close all connections in pool"""
        if self._redis_client:
            await self._redis_client.close()
            self._redis_client = None
            logger.info("Redis connection pool closed")


# Global singleton instance
_redis_pool: Optional[RedisPool] = None


def get_redis_pool() -> RedisPool:
    """Get the global Redis connection pool"""
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = RedisPool()
    return _redis_pool


async def get_redis_client():
    """
    Convenience function to get Redis client.
    Usage:
        redis = await get_redis_client()
        if redis:
            await redis.setex(key, 10, "1")
    """
    pool = get_redis_pool()
    return await pool.get_client()
