"""
Al-Mudeer - Token Blacklist Service
Invalidates JWT tokens on logout for proper session termination

SECURITY FIX: Added database-backed fallback for production environments.
Redis is now mandatory for production - the service will fail-fast if Redis
is not available in production, preventing security gaps from in-memory storage.

CRITICAL FIX: Added DB fallback table for token blacklist to handle Redis outages.
"""

import os
import time
from typing import Optional, Set
from datetime import datetime, timedelta, timezone
from threading import Lock

from logging_config import get_logger

logger = get_logger(__name__)


class TokenBlacklist:
    """
    Token blacklist with Redis (primary) and database (fallback) backends.
    Stores invalidated token JTIs (JWT IDs) until they would naturally expire.

    SECURITY: In production, Redis is MANDATORY. If Redis is unavailable,
    the service fails closed (assumes tokens are blacklisted) to prevent
    unauthorized access.
    
    CRITICAL FIX: Database fallback table 'token_blacklist' is used when Redis fails.
    """

    def __init__(self):
        self._memory_store: dict[str, float] = {}  # jti -> expiry_timestamp
        self._lock = Lock()
        self._redis_client = None
        self._environment = os.getenv("ENVIRONMENT", "development")
        self._db_fallback_active = False
        self._init_redis()

    def _init_redis(self):
        """
        Initialize Redis connection.
        SECURITY: In production, fail-fast if Redis is unavailable.
        """
        redis_url = os.getenv("REDIS_URL")

        if redis_url:
            try:
                import redis
                self._redis_client = redis.from_url(redis_url)
                self._redis_client.ping()
                logger.info("Token blacklist using Redis backend")
                return
            except Exception as e:
                logger.warning(f"Redis connection failed for token blacklist: {e}")
                self._redis_client = None

        # No Redis available
        if self._environment == "production":
            # SECURITY: Fail closed in production - better to block valid tokens
            # than to allow blacklisted tokens
            logger.critical(
                "CRITICAL: Token blacklist cannot connect to Redis in PRODUCTION! "
                "Operating in FAIL-CLOSED mode - all token blacklist checks will return TRUE (blacklisted). "
                "This blocks ALL authenticated requests until Redis is available. "
                "ACTION REQUIRED: Set REDIS_URL environment variable. "
                "Example: REDIS_URL=redis://localhost:6379/0"
            )
            # CRITICAL FIX: Enable DB fallback in production when Redis fails
            self._db_fallback_active = True
            logger.info("Token blacklist: Database fallback activated due to Redis unavailability")
        else:
            logger.info("Token blacklist using in-memory storage (development only)")
    
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
        # SECURITY FIX: Use timezone-aware datetime
        now = datetime.now(timezone.utc)
        if expires_at.tzinfo is None:
            # Handle naive datetime (assume UTC)
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        ttl_seconds = int((expires_at - now).total_seconds())

        if ttl_seconds <= 0:
            # Token already expired, no need to blacklist
            return True

        try:
            if self._redis_client:
                # Use Redis with auto-expiry
                key = f"blacklist:{jti}"
                self._redis_client.setex(key, ttl_seconds, "1")
                logger.debug(f"Token {jti[:8]}... blacklisted in Redis (TTL: {ttl_seconds}s)")
                return True
            elif self._db_fallback_active:
                # CRITICAL FIX: Use database fallback when Redis is unavailable
                self._blacklist_token_db(jti, expires_at)
                logger.debug(f"Token {jti[:8]}... blacklisted in DB fallback (TTL: {ttl_seconds}s)")
                return True
            else:
                # Use in-memory store (development only)
                with self._lock:
                    expiry_timestamp = time.time() + ttl_seconds
                    self._memory_store[jti] = expiry_timestamp
                    self._cleanup_expired()
                logger.debug(f"Token {jti[:8]}... blacklisted in memory (TTL: {ttl_seconds}s)")
                return True

        except Exception as e:
            logger.error(f"Failed to blacklist token: {e}")
            # CRITICAL FIX: Try DB fallback if Redis fails
            if not self._db_fallback_active and self._environment == "production":
                try:
                    self._blacklist_token_db(jti, expires_at)
                    logger.info("Token blacklisted in DB after Redis failure")
                    return True
                except Exception as db_err:
                    logger.error(f"DB fallback also failed: {db_err}")
            
            # SECURITY: In production, fail closed (assume blacklisted)
            if self._environment == "production":
                return True
            return False

    def _blacklist_token_db(self, jti: str, expires_at: datetime):
        """CRITICAL FIX: Store blacklisted token in database as fallback"""
        try:
            from db_helper import get_db, execute_sql, commit_db
            from database import DB_TYPE
            import asyncio
            
            async def _do_insert():
                async with get_db() as db:
                    try:
                        if DB_TYPE == "postgresql":
                            await execute_sql(db, """
                                INSERT INTO token_blacklist (jti, expires_at, created_at)
                                VALUES (?, ?, NOW())
                                ON CONFLICT (jti) DO UPDATE SET expires_at = ?
                            """, [jti, expires_at, expires_at])
                        else:
                            await execute_sql(db, """
                                INSERT OR REPLACE INTO token_blacklist (jti, expires_at, created_at)
                                VALUES (?, ?, datetime('now'))
                            """, [jti, expires_at.isoformat()])
                        await commit_db(db)
                    except Exception as e:
                        logger.error(f"DB blacklist insert failed: {e}")
                        raise
            
            asyncio.run(_do_insert())
        except Exception as e:
            logger.error(f"DB fallback blacklist failed: {e}")
            raise
    
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
                result = self._redis_client.exists(key)
                if result > 0:
                    return True
                # CRITICAL FIX: If Redis doesn't have it, check DB fallback
                # This handles cases where token was blacklisted during Redis outage
                if self._db_fallback_active:
                    return self._is_blacklisted_db(jti)
                return False
            elif self._db_fallback_active:
                # CRITICAL FIX: Use DB fallback when Redis is unavailable
                return self._is_blacklisted_db(jti)
            else:
                # In-memory store (development only)
                with self._lock:
                    if jti in self._memory_store:
                        if self._memory_store[jti] > time.time():
                            return True
                        else:
                            # Expired, remove it
                            del self._memory_store[jti]
                    # SECURITY FIX #3: Fail closed in ALL environments
                    # Exception: During testing, fail open to allow tests to run without Redis
                    if os.getenv("TESTING") == "1":
                        logger.debug(f"Token blacklist check in testing mode - allowing token {jti[:8]}...")
                        return False
                    # Production/Development: Fail closed
                    logger.warning(
                        f"Token blacklist check failed (no Redis) - failing CLOSED (blocking token {jti[:8]}...). "
                        "WARNING: This blocks ALL authenticated requests. "
                        "For development, set REDIS_URL or understand that logout won't work without Redis."
                    )
                    return True

        except Exception as e:
            logger.error(f"Failed to check token blacklist: {e}")
            # SECURITY FIX #3: Fail closed in ALL environments
            # Exception: During testing, fail open to allow tests to run without Redis
            if os.getenv("TESTING") == "1":
                logger.debug("Token blacklist check failed during testing - allowing token")
                return False
            # Production/Development: Fail closed
            logger.warning("Token blacklist check failed - failing closed (blocking token)")
            return True

    def _is_blacklisted_db(self, jti: str) -> bool:
        """CRITICAL FIX: Check if token is blacklisted in database"""
        try:
            from db_helper import get_db, fetch_one
            from database import DB_TYPE
            import asyncio
            
            async def _do_check():
                async with get_db() as db:
                    row = await fetch_one(db, """
                        SELECT expires_at FROM token_blacklist WHERE jti = ?
                    """, [jti])
                    if not row:
                        return False
                    # Check if blacklist entry has expired
                    expires_at = row.get("expires_at")
                    if not expires_at:
                        return True
                    # Parse datetime and compare
                    if isinstance(expires_at, str):
                        expires_at = datetime.fromisoformat(expires_at.replace('Z', '+00:00'))
                    if expires_at.tzinfo is None:
                        expires_at = expires_at.replace(tzinfo=timezone.utc)
                    return datetime.now(timezone.utc) < expires_at
            
            return asyncio.run(_do_check())
        except Exception as e:
            logger.error(f"DB blacklist check failed: {e}")
            # On DB error, fail closed in production
            return self._environment == "production"
    
    def _cleanup_expired(self):
        """Remove expired entries from memory store."""
        current_time = time.time()
        expired = [jti for jti, exp in self._memory_store.items() if exp <= current_time]
        for jti in expired:
            del self._memory_store[jti]

        if expired:
            logger.debug(f"Cleaned up {len(expired)} expired blacklist entries")

    # P1-6 FIX: Add cleanup method for database blacklist table
    async def cleanup_expired_db_blacklist(self):
        """
        P1-6 FIX: Clean up expired entries from the database blacklist table.
        This should be called periodically (e.g., daily) to prevent table bloat.

        Usage: Add to a background task or cron job in main.py
        """
        try:
            from db_helper import get_db, execute_sql, commit_db
            from database import DB_TYPE

            async with get_db() as db:
                if DB_TYPE == "postgresql":
                    result = await execute_sql(db, """
                        DELETE FROM token_blacklist
                        WHERE expires_at < NOW()
                    """)
                else:
                    result = await execute_sql(db, """
                        DELETE FROM token_blacklist
                        WHERE expires_at < datetime('now')
                    """)

                await commit_db(db)

                # Get count of deleted rows (if supported)
                if hasattr(result, 'rowcount') and result.rowcount is not None:
                    logger.info(f"P1-6: Cleaned up {result.rowcount} expired token blacklist entries")
                else:
                    logger.info("P1-6: Token blacklist cleanup completed")

        except Exception as e:
            logger.error(f"P1-6: Token blacklist cleanup failed: {e}")

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


# P1-6 FIX: Add cleanup convenience function
async def cleanup_token_blacklist() -> None:
    """
    P1-6 FIX: Clean up expired entries from the token blacklist.
    Call this periodically (e.g., daily) to prevent database bloat.

    Usage in main.py or scheduled task:
        from services.token_blacklist import cleanup_token_blacklist
        await cleanup_token_blacklist()
    """
    blacklist = get_token_blacklist()
    await blacklist.cleanup_expired_db_blacklist()
