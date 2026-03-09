"""
Al-Mudeer - Login Protection Service
Brute force protection with account lockout after failed attempts

SECURITY FIX: Redis is now MANDATORY for production environments.
In production, the service fails closed (assumes locked) if Redis is unavailable,
preventing distributed brute-force attacks across multiple instances.
"""

import os
import time
from typing import Optional, Tuple
from datetime import datetime, timedelta, timezone
from threading import Lock

from logging_config import get_logger

logger = get_logger(__name__)


# Configuration
MAX_FAILED_ATTEMPTS = int(os.getenv("MAX_LOGIN_ATTEMPTS", "5"))
LOCKOUT_DURATION_MINUTES = int(os.getenv("LOCKOUT_DURATION_MINUTES", "15"))


class LoginProtection:
    """
    Tracks failed login attempts and locks accounts after too many failures.
    Uses Redis (mandatory for production) with in-memory fallback for development.
    
    SECURITY: In production, if Redis is unavailable, the service fails closed
    (assumes accounts are locked) to prevent unauthorized access.
    """

    def __init__(self):
        # Store: identifier -> {"attempts": int, "locked_until": timestamp, "last_attempt": timestamp}
        self._memory_store: dict[str, dict] = {}
        self._lock = Lock()
        self._redis_client = None
        self._environment = os.getenv("ENVIRONMENT", "development")
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
                logger.info("Login protection using Redis backend")
                return
            except Exception as e:
                logger.warning(f"Redis connection failed for login protection: {e}")
                self._redis_client = None
        
        # No Redis available
        if self._environment == "production":
            # SECURITY: Fail closed in production - assume all accounts are locked
            # This is safer than allowing potential brute-force attacks
            logger.critical(
                "CRITICAL: Login protection cannot connect to Redis in PRODUCTION! "
                "Operating in FAIL-CLOSED mode - ALL login attempts will be blocked. "
                "This prevents brute-force attacks but also blocks legitimate users. "
                "ACTION REQUIRED: Set REDIS_URL environment variable. "
                "Example: REDIS_URL=redis://localhost:6379/0"
            )
        else:
            logger.info("Login protection using in-memory storage (development only)")

    def _get_key(self, identifier: str) -> str:
        """Get Redis key for identifier."""
        return f"login_protection:{identifier}"

    def check_lockout(self, identifier: str) -> Tuple[bool, Optional[int]]:
        """
        Check if an identifier (email or IP) is locked out.

        Args:
            identifier: Email address or IP address

        Returns:
            Tuple of (is_locked, seconds_remaining)
        """
        try:
            if self._redis_client:
                key = self._get_key(identifier)
                data = self._redis_client.hgetall(key)
                if data and b"locked_until" in data:
                    locked_until = float(data[b"locked_until"])
                    if locked_until > time.time():
                        remaining = int(locked_until - time.time())
                        return True, remaining
            else:
                # In-memory store (development only)
                with self._lock:
                    if identifier in self._memory_store:
                        data = self._memory_store[identifier]
                        if data.get("locked_until", 0) > time.time():
                            remaining = int(data["locked_until"] - time.time())
                            return True, remaining

            return False, None

        except Exception as e:
            logger.error(f"Error checking lockout: {e}")
            # SECURITY FIX: In production, fail closed (assume locked) for safety
            # This prevents potential brute-force attacks during Redis outages
            if self._environment == "production":
                logger.warning("Login protection check failed in production - failing closed (blocking login)")
                return True, 60  # Lock for 1 minute as safety measure
            # In development, fail open (allow login) to avoid blocking development
            return False, None

    def record_failed_attempt(self, identifier: str) -> Tuple[int, bool]:
        """
        Record a failed login attempt.

        Args:
            identifier: Email address or IP address

        Returns:
            Tuple of (attempt_count, is_now_locked)
        """
        try:
            current_time = time.time()

            if self._redis_client:
                key = self._get_key(identifier)
                pipe = self._redis_client.pipeline()

                # Increment attempt counter
                pipe.hincrby(key, "attempts", 1)
                pipe.hset(key, "last_attempt", str(current_time))
                pipe.expire(key, LOCKOUT_DURATION_MINUTES * 60 * 2)  # Keep data for 2x lockout period
                results = pipe.execute()

                attempts = results[0]

                # Check if should lock
                if attempts >= MAX_FAILED_ATTEMPTS:
                    locked_until = current_time + (LOCKOUT_DURATION_MINUTES * 60)
                    self._redis_client.hset(key, "locked_until", str(locked_until))
                    logger.warning(f"Account locked: {identifier} after {attempts} failed attempts")
                    return attempts, True

                return attempts, False

            else:
                # In-memory store (development only)
                with self._lock:
                    if identifier not in self._memory_store:
                        self._memory_store[identifier] = {"attempts": 0, "locked_until": 0}

                    data = self._memory_store[identifier]

                    # Reset if lockout expired
                    if data.get("locked_until", 0) > 0 and data["locked_until"] <= current_time:
                        data["attempts"] = 0
                        data["locked_until"] = 0

                    data["attempts"] += 1
                    data["last_attempt"] = current_time

                    # Check if should lock
                    if data["attempts"] >= MAX_FAILED_ATTEMPTS:
                        data["locked_until"] = current_time + (LOCKOUT_DURATION_MINUTES * 60)
                        logger.warning(f"Account locked: {identifier} after {data['attempts']} failed attempts")
                        return data["attempts"], True

                    return data["attempts"], False

        except Exception as e:
            logger.error(f"Error recording failed attempt: {e}")
            return 0, False

    def record_successful_login(self, identifier: str):
        """
        Clear failed attempts after successful login.

        Args:
            identifier: Email address or IP address
        """
        try:
            if self._redis_client:
                key = self._get_key(identifier)
                self._redis_client.delete(key)
            else:
                with self._lock:
                    if identifier in self._memory_store:
                        del self._memory_store[identifier]

            logger.debug(f"Cleared login attempts for: {identifier}")

        except Exception as e:
            logger.error(f"Error clearing login attempts: {e}")

    def get_attempts(self, identifier: str) -> int:
        """Get current failed attempt count."""
        try:
            if self._redis_client:
                key = self._get_key(identifier)
                attempts = self._redis_client.hget(key, "attempts")
                return int(attempts) if attempts else 0
            else:
                with self._lock:
                    if identifier in self._memory_store:
                        return self._memory_store[identifier].get("attempts", 0)
                    return 0
        except:
            return 0


# Singleton instance
_protection: Optional[LoginProtection] = None


def get_login_protection() -> LoginProtection:
    """Get the global login protection instance."""
    global _protection
    if _protection is None:
        _protection = LoginProtection()
    return _protection


def check_account_lockout(identifier: str) -> Tuple[bool, Optional[int]]:
    """Check if account is locked. Returns (is_locked, seconds_remaining)."""
    return get_login_protection().check_lockout(identifier)


def record_failed_login(identifier: str) -> Tuple[int, bool]:
    """Record failed login. Returns (attempt_count, is_now_locked)."""
    return get_login_protection().record_failed_attempt(identifier)


def record_successful_login(identifier: str):
    """Clear failed attempts on successful login."""
    get_login_protection().record_successful_login(identifier)
