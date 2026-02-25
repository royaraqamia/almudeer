"""
Al-Mudeer - Token Blacklist Service
Invalidates JWT tokens on logout for proper session termination
"""

import os
import time
from typing import Optional, Set
from datetime import datetime, timedelta
from threading import Lock

from logging_config import get_logger

logger = get_logger(__name__)


class TokenBlacklist:
    """
    In-memory token blacklist with optional Redis backend.
    Stores invalidated token JTIs (JWT IDs) until they would naturally expire.
    """
    
    def __init__(self):
        self._memory_store: dict[str, float] = {}  # jti -> expiry_timestamp
        self._lock = Lock()
        self._redis_client = None
        self._init_redis()
    
    def _init_redis(self):
        """Try to connect to Redis if available."""
        redis_url = os.getenv("REDIS_URL")
        environment = os.getenv("ENVIRONMENT", "development")
        
        if redis_url:
            try:
                import redis
                self._redis_client = redis.from_url(redis_url)
                self._redis_client.ping()
                logger.info("Token blacklist using Redis backend")
            except Exception as e:
                logger.warning(f"Redis not available for token blacklist: {e}")
                self._redis_client = None
                # SECURITY WARNING: Running in production without Redis
                if environment == "production":
                    logger.error(
                        "CRITICAL: Token blacklist running in-memory mode in PRODUCTION! "
                        "Blacklisted tokens will not be synced across instances and will be lost on restart. "
                        "ACTION REQUIRED: Set REDIS_URL environment variable. "
                        "Example: REDIS_URL=redis://localhost:6379/0 "
                        "This is a security risk - logged out users may retain access!"
                    )
        else:
            logger.info("Token blacklist using in-memory storage (tokens won't persist across restarts)")
            # SECURITY WARNING: Running in production without Redis
            if environment == "production":
                logger.error(
                    "CRITICAL: REDIS_URL not set in PRODUCTION! Token blacklist using in-memory mode. "
                    "Blacklisted tokens will not be synced across instances and will be lost on restart. "
                    "ACTION REQUIRED: Set REDIS_URL environment variable. "
                    "Example: REDIS_URL=redis://localhost:6379/0"
                )
    
    def blacklist_token(self, jti: str, expires_at: datetime) -> bool:
        """
        Add a token to the blacklist.
        
        Args:
            jti: JWT ID (unique token identifier)
            expires_at: When the token would naturally expire
            
        Returns:
            True if successfully blacklisted
        """
        if not jti:
            return False
        
        # Calculate TTL (time until token would expire anyway)
        ttl_seconds = int((expires_at - datetime.utcnow()).total_seconds())
        if ttl_seconds <= 0:
            # Token already expired, no need to blacklist
            return True
        
        try:
            if self._redis_client:
                # Use Redis with auto-expiry
                key = f"blacklist:{jti}"
                self._redis_client.setex(key, ttl_seconds, "1")
                logger.debug(f"Token {jti[:8]}... blacklisted in Redis (TTL: {ttl_seconds}s)")
            else:
                # Use in-memory store
                with self._lock:
                    expiry_timestamp = time.time() + ttl_seconds
                    self._memory_store[jti] = expiry_timestamp
                    self._cleanup_expired()
                logger.debug(f"Token {jti[:8]}... blacklisted in memory (TTL: {ttl_seconds}s)")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to blacklist token: {e}")
            return False
    
    def is_blacklisted(self, jti: str) -> bool:
        """
        Check if a token is blacklisted.
        
        Args:
            jti: JWT ID to check
            
        Returns:
            True if token is blacklisted (should be rejected)
        """
        if not jti:
            return False
        
        try:
            if self._redis_client:
                key = f"blacklist:{jti}"
                return self._redis_client.exists(key) > 0
            else:
                with self._lock:
                    if jti in self._memory_store:
                        if self._memory_store[jti] > time.time():
                            return True
                        else:
                            # Expired, remove it
                            del self._memory_store[jti]
                return False
                
        except Exception as e:
            logger.error(f"Failed to check token blacklist: {e}")
            # SECURITY: Fail closed - assume blacklisted on error to prevent
            # potentially revoked tokens from being accepted during outages
            return True
    
    def _cleanup_expired(self):
        """Remove expired entries from memory store."""
        current_time = time.time()
        expired = [jti for jti, exp in self._memory_store.items() if exp <= current_time]
        for jti in expired:
            del self._memory_store[jti]
        
        if expired:
            logger.debug(f"Cleaned up {len(expired)} expired blacklist entries")
    
    def get_stats(self) -> dict:
        """Get blacklist statistics."""
        if self._redis_client:
            try:
                keys = self._redis_client.keys("blacklist:*")
                return {"backend": "redis", "count": len(keys)}
            except:
                return {"backend": "redis", "count": "unknown", "error": "failed to count"}
        else:
            with self._lock:
                self._cleanup_expired()
                return {"backend": "memory", "count": len(self._memory_store)}


# Singleton instance
_blacklist: Optional[TokenBlacklist] = None


def get_token_blacklist() -> TokenBlacklist:
    """Get the global token blacklist instance."""
    global _blacklist
    if _blacklist is None:
        _blacklist = TokenBlacklist()
    return _blacklist


def blacklist_token(jti: str, expires_at: datetime) -> bool:
    """Convenience function to blacklist a token."""
    return get_token_blacklist().blacklist_token(jti, expires_at)


def is_token_blacklisted(jti: str) -> bool:
    """Convenience function to check if a token is blacklisted."""
    return get_token_blacklist().is_blacklisted(jti)
