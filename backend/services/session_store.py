"""
Al-Mudeer - Session Store (Redis-backed)
Enables horizontal scaling by storing sessions in Redis instead of memory
"""

import os
import json
import secrets
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

from logging_config import get_logger

logger = get_logger(__name__)


class SessionStore:
    """
    Redis-backed session store for horizontal scaling.
    
    When running multiple instances, sessions must be shared.
    This store uses Redis (if available) or falls back to in-memory.
    """
    
    def __init__(self):
        self._redis_client = None
        self._use_redis = False
        self._memory_store: Dict[str, Dict[str, Any]] = {}
        self._session_ttl = int(os.getenv("SESSION_TTL_HOURS", "24")) * 3600
    
    async def initialize(self):
        """Initialize Redis connection if available"""
        redis_url = os.getenv("REDIS_URL")
        
        if redis_url:
            try:
                import redis.asyncio as redis
                self._redis_client = redis.from_url(redis_url, decode_responses=True)
                await self._redis_client.ping()
                self._use_redis = True
                logger.info("Session store: Redis connected (horizontal scaling enabled)")
            except Exception as e:
                logger.warning(f"Session store: Redis unavailable, using memory ({e})")
                self._use_redis = False
        else:
            logger.info("Session store: Using in-memory (single instance only)")
    
    async def create_session(self, user_data: Dict[str, Any]) -> str:
        """Create a new session and return session ID"""
        session_id = secrets.token_urlsafe(32)
        
        session_data = {
            "user": user_data,
            "created_at": datetime.utcnow().isoformat(),
            "last_access": datetime.utcnow().isoformat(),
        }
        
        if self._use_redis and self._redis_client:
            await self._redis_client.setex(
                f"session:{session_id}",
                self._session_ttl,
                json.dumps(session_data)
            )
        else:
            self._memory_store[session_id] = session_data
        
        return session_id
    
    async def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data by ID"""
        if self._use_redis and self._redis_client:
            data = await self._redis_client.get(f"session:{session_id}")
            if data:
                session = json.loads(data)
                # Update last access
                session["last_access"] = datetime.utcnow().isoformat()
                await self._redis_client.setex(
                    f"session:{session_id}",
                    self._session_ttl,
                    json.dumps(session)
                )
                return session
        else:
            if session_id in self._memory_store:
                self._memory_store[session_id]["last_access"] = datetime.utcnow().isoformat()
                return self._memory_store[session_id]
        
        return None
    
    async def delete_session(self, session_id: str):
        """Delete a session (logout)"""
        if self._use_redis and self._redis_client:
            await self._redis_client.delete(f"session:{session_id}")
        else:
            self._memory_store.pop(session_id, None)
    
    async def cleanup_expired(self):
        """Clean up expired sessions (memory store only)"""
        if not self._use_redis:
            now = datetime.utcnow()
            expired = []
            for sid, data in self._memory_store.items():
                last_access = datetime.fromisoformat(data["last_access"])
                if (now - last_access).total_seconds() > self._session_ttl:
                    expired.append(sid)
            for sid in expired:
                del self._memory_store[sid]


# Global session store
_session_store: Optional[SessionStore] = None


async def get_session_store() -> SessionStore:
    """Get or create the global session store"""
    global _session_store
    if _session_store is None:
        _session_store = SessionStore()
        await _session_store.initialize()
    return _session_store
