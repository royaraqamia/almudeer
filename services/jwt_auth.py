"""
Al-Mudeer - JWT Authentication Service
Production-ready JWT authentication with access/refresh tokens
"""

import os
import secrets
import hashlib
import hmac
import uuid
import time
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass

from jose import jwt, JWTError
from starlette.concurrency import run_in_threadpool

from logging_config import get_logger

logger = get_logger(__name__)


# ============ Session Revocation Cache ============
# Short-lived cache to reduce DB load for session revocation checks

class SessionRevocationCache:
    """Simple in-memory cache for session revocation status"""

    def __init__(self, ttl_seconds: int = 2):  # SECURITY FIX: Reduced from 10s to 2s
        self._cache: Dict[str, Tuple[bool, float]] = {}  # family_id -> (is_revoked, expires_at)
        self._ttl = ttl_seconds

    def get(self, family_id: str) -> Optional[bool]:
        """Get cached revocation status. Returns None if not cached."""
        if family_id in self._cache:
            is_revoked, expires_at = self._cache[family_id]
            if time.time() < expires_at:
                return is_revoked
            else:
                del self._cache[family_id]
        return None

    def set(self, family_id: str, is_revoked: bool):
        """Cache revocation status"""
        self._cache[family_id] = (is_revoked, time.time() + self._ttl)

    def invalidate(self, family_id: str):
        """Invalidate cached entry"""
        if family_id in self._cache:
            del self._cache[family_id]


# Global session revocation cache (2 second TTL - SECURITY FIX: reduced from 10s)
_session_revocation_cache = SessionRevocationCache(ttl_seconds=2)


# ============ Configuration ============

def _get_jwt_secret_key() -> str:
    """Get JWT secret key from environment. FAILS FAST if not set."""
    key = os.getenv("JWT_SECRET_KEY")
    if key:
        return key
    
    # SECURITY: No fallback - fail fast in ALL environments
    # This prevents accidental use of weak secrets
    logger.error(
        "JWT_SECRET_KEY is NOT set! "
        "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
    )
    raise ValueError(
        "JWT_SECRET_KEY must be set! "
        "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
    )


@dataclass
class JWTConfig:
    """JWT configuration from environment"""
    secret_key: str = None  # Set in __post_init__
    algorithm: str = "HS256"
    access_token_expire_minutes: int = int(os.getenv("JWT_ACCESS_EXPIRE_MINUTES", "30"))
    refresh_token_expire_days: int = int(os.getenv("JWT_REFRESH_EXPIRE_DAYS", "7"))
    
    def __post_init__(self):
        if self.secret_key is None:
            self.secret_key = _get_jwt_secret_key()


config = JWTConfig()



# ============ Token Types ============

class TokenType:
    ACCESS = "access"
    REFRESH = "refresh"


# ============ Token Operations ============

def create_access_token(data: Dict[str, Any], expires_delta: timedelta = None) -> Tuple[str, str, datetime]:
    """
    Create a JWT access token.

    Args:
        data: Payload data (should include 'sub' for subject/user ID)
        expires_delta: Custom expiration time

    Returns:
        Tuple of (encoded_token, jti, expiry_datetime)
    """
    to_encode = data.copy()
    # SECURITY FIX: Use timezone-aware datetime instead of deprecated datetime.utcnow()
    now = datetime.now(timezone.utc)
    expire = now + (expires_delta or timedelta(minutes=config.access_token_expire_minutes))
    
    # SECURITY FIX: Generate JTI with 32 bytes (256 bits) for collision resistance
    jti = secrets.token_hex(32)

    to_encode.update({
        "exp": expire,
        "iat": now,
        "type": TokenType.ACCESS,
        "jti": jti,
    })

    return jwt.encode(to_encode, config.secret_key, algorithm=config.algorithm), jti, expire


def create_refresh_token(data: Dict[str, Any], family_id: str = None) -> Tuple[str, str]:
    """
    Create a JWT refresh token (longer expiration).

    Args:
        data: Payload data (should include 'sub' for subject/user ID)

    Returns:
        Tuple of (encoded_token_string, jti)
    """
    to_encode = data.copy()
    # SECURITY FIX: Use timezone-aware datetime
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=config.refresh_token_expire_days)
    
    # SECURITY FIX: Generate JTI with 32 bytes (256 bits) for collision resistance
    jti = secrets.token_hex(32)

    to_encode.update({
        "exp": expire,
        "iat": now,
        "type": TokenType.REFRESH,
        "jti": jti,
    })

    if family_id:
        to_encode["family_id"] = family_id

    return jwt.encode(to_encode, config.secret_key, algorithm=config.algorithm), jti


# ============ Async Performance Wrappers ============

async def create_access_token_async(data: Dict[str, Any], expires_delta: timedelta = None) -> Tuple[str, str, datetime]:
    """Async wrapper for create_access_token to avoid event loop blocking."""
    # FIX: Use asyncio.to_thread for better performance in Python 3.9+
    # This reduces thread pool saturation under high load
    try:
        import asyncio
        return await asyncio.to_thread(create_access_token, data, expires_delta)
    except AttributeError:
        # Fallback for Python < 3.9
        return await run_in_threadpool(create_access_token, data, expires_delta)

async def create_refresh_token_async(data: Dict[str, Any], family_id: str = None) -> Tuple[str, str]:
    """Async wrapper for create_refresh_token to avoid event loop blocking."""
    try:
        import asyncio
        return await asyncio.to_thread(create_refresh_token, data, family_id)
    except AttributeError:
        return await run_in_threadpool(create_refresh_token, data, family_id)

async def verify_token_async(token: str, token_type: str = TokenType.ACCESS) -> Optional[Dict[str, Any]]:
    """Async wrapper for verify_token to avoid event loop blocking."""
    try:
        import asyncio
        return await asyncio.to_thread(verify_token, token, token_type)
    except AttributeError:
        return await run_in_threadpool(verify_token, token, token_type)


async def create_token_pair(
    user_id: str,
    license_id: int = None,
    role: str = "user",
    device_fingerprint: str = None,
    ip_address: str = None,
    family_id: str = None,
    device_secret_hash: str = None,
    user_agent: str = None
) -> Dict[str, Any]:
    """
    Create both access and refresh tokens. Track device session.
    
    SECURITY FIX #7: Enforce concurrent session limits per license.
    """
    # Fetch current token_version for the license to embed in JWT
    from database import get_db, fetch_one
    
    # SECURITY FIX #7: Check concurrent session limit
    max_sessions = int(os.getenv("MAX_CONCURRENT_SESSIONS", "0"))  # 0 = unlimited
    
    token_version = 1
    if license_id:
        try:
            async with get_db() as db:
                row = await fetch_one(db, "SELECT token_version, is_active FROM license_keys WHERE id = ?", [license_id])
                if row:
                    token_version = row.get("token_version", 1)
                    if not row.get("is_active", True):
                        logger.warning(f"Denying token creation for deactivated license {license_id}")
                        raise ValueError("Account is deactivated")
        except Exception as e:
            logger.error(f"Error fetching token version for JWT: {e}")
            pass

    is_new_family = False
    if not family_id:
        family_id = str(uuid.uuid4())
        is_new_family = True

    payload = {
        "sub": user_id,
        "license_id": license_id,
        "role": role,
        "v": token_version, # Token version for server-side kill-switch
        "family_id": family_id,
    }
    
    access_token, jti, expires_at = await create_access_token_async(payload)
    refresh_token, refresh_jti = await create_refresh_token_async(payload, family_id=family_id)
    
    # Session Intelligence: Resolve location and parse device name
    from services.session_intelligence import resolve_location, parse_device_info
    location = await resolve_location(ip_address)
    device_name = parse_device_info(user_agent)
    
    # Store session in DB for RTR
    if license_id:
        from database import DB_TYPE
        from db_helper import execute_sql, commit_db
        try:
            async with get_db() as db:
                # SECURITY FIX: Use timezone-aware datetime
                expires_db = datetime.now(timezone.utc) + timedelta(days=config.refresh_token_expire_days)

                if is_new_family:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            INSERT INTO device_sessions
                            (license_key_id, family_id, refresh_token_jti, device_fingerprint, ip_address, expires_at, device_secret_hash, device_name, location, user_agent)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, [license_id, family_id, refresh_jti, device_fingerprint, ip_address, expires_db, device_secret_hash, device_name, location, user_agent])
                    else:
                        await execute_sql(db, """
                            INSERT INTO device_sessions
                            (license_key_id, family_id, refresh_token_jti, device_fingerprint, ip_address, expires_at, device_secret_hash, device_name, location, user_agent)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, [license_id, family_id, refresh_jti, device_fingerprint, ip_address, expires_db.isoformat(), device_secret_hash, device_name, location, user_agent])
                else:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            UPDATE device_sessions
                            SET refresh_token_jti = ?, last_used_at = NOW(), expires_at = ?, ip_address = COALESCE(?, ip_address), device_secret_hash = ?,
                                device_name = COALESCE(?, device_name), location = COALESCE(?, location), user_agent = COALESCE(?, user_agent)
                            WHERE family_id = ?
                        """, [refresh_jti, expires_db, ip_address, device_secret_hash, device_name, location, user_agent, family_id])
                    else:
                        await execute_sql(db, """
                            UPDATE device_sessions
                            SET refresh_token_jti = ?, last_used_at = CURRENT_TIMESTAMP, expires_at = ?, ip_address = COALESCE(?, ip_address), device_secret_hash = ?,
                                device_name = COALESCE(?, device_name), location = COALESCE(?, location), user_agent = COALESCE(?, user_agent)
                            WHERE family_id = ?
                        """, [refresh_jti, expires_db.isoformat(), ip_address, device_secret_hash, device_name, location, user_agent, family_id])

                await commit_db(db)
                
                # SECURITY FIX #7: Enforce concurrent session limit
                if max_sessions > 0 and is_new_family:
                    # Count active sessions for this license
                    sessions_result = await fetch_one(
                        db,
                        "SELECT COUNT(*) as session_count FROM device_sessions WHERE license_key_id = ? AND is_revoked = 0",
                        [license_id]
                    )
                    session_count = sessions_result.get("session_count", 0) if sessions_result else 0
                    
                    if session_count > max_sessions:
                        # Revoke oldest sessions to stay within limit
                        sessions_to_revoke = session_count - max_sessions
                        logger.info(f"Revoking {sessions_to_revoke} oldest session(s) for license {license_id} (limit: {max_sessions})")
                        
                        if DB_TYPE == "postgresql":
                            await execute_sql(db, """
                                UPDATE device_sessions
                                SET is_revoked = TRUE
                                WHERE license_key_id = ? AND is_revoked = 0
                                AND id IN (
                                    SELECT id FROM device_sessions
                                    WHERE license_key_id = ? AND is_revoked = 0
                                    ORDER BY last_used_at ASC
                                    LIMIT ?
                                )
                            """, [license_id, license_id, sessions_to_revoke])
                        else:
                            await execute_sql(db, """
                                UPDATE device_sessions
                                SET is_revoked = 1
                                WHERE license_key_id = ? AND is_revoked = 0
                                AND id IN (
                                    SELECT id FROM device_sessions
                                    WHERE license_key_id = ? AND is_revoked = 0
                                    ORDER BY last_used_at ASC
                                    LIMIT ?
                                )
                            """, [license_id, license_id, sessions_to_revoke])
                        
                        await commit_db(db)
                        
        except Exception as e:
            logger.error(f"Error updating device session or enforcing session limit: {e}")

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": config.access_token_expire_minutes * 60,  # seconds
        "jti": jti,
        "expires_at": expires_at,
    }


def verify_token(token: str, token_type: str = TokenType.ACCESS) -> Optional[Dict[str, Any]]:
    """
    Verify and decode a JWT token.
    
    Args:
        token: JWT token string
        token_type: Expected token type (access/refresh)
    
    Returns:
        Decoded payload or None if invalid
    """
    try:
        payload = jwt.decode(token, config.secret_key, algorithms=[config.algorithm])
        
        # Verify token type
        if payload.get("type") != token_type:
            logger.warning(f"Token type mismatch: expected {token_type}, got {payload.get('type')}")
            return None
        
        # Check if token is blacklisted (for access tokens)
        if token_type == TokenType.ACCESS:
            jti = payload.get("jti")
            if jti:
                from services.token_blacklist import is_token_blacklisted
                if is_token_blacklisted(jti):
                    logger.info(f"Token {jti[:8]}... is blacklisted")
                    return None
            
            # Note: For production performance, this should be cached in Redis
            # Senior Engineering Note: Version check is performed in the async 
            # get_current_user dependency. verify_token remains sync for 
            # basic field parsing/decoding.
            pass
        
        return payload
        
    except JWTError as e:
        logger.debug(f"JWT verification failed: {e}")
        return None


async def refresh_access_token(
    refresh_token: str, 
    device_fingerprint: str = None, 
    ip_address: str = None,
    device_secret: str = None,
    user_agent: str = None
) -> Optional[Dict[str, Any]]:
    """
    Use a refresh token to get a new access token and rotate the refresh token.
    """
    payload = await verify_token_async(refresh_token, TokenType.REFRESH)
    
    if not payload:
        return None
        
    jti = payload.get("jti")
    family_id = payload.get("family_id")
    license_id = payload.get("license_id")
    family_id = payload.get("family_id")

    # Real-time Session Revocation Check
    if family_id:
        from db_helper import get_db, fetch_one
        try:
            async with get_db() as db:
                session = await fetch_one(db, "SELECT is_revoked FROM device_sessions WHERE family_id = ?", [family_id])
                if session and session.get("is_revoked"):
                    logger.warning(f"Rejecting access token for revoked session: {family_id}")
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Session has been revoked",
                        headers={"WWW-Authenticate": "Bearer"},
                    )
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Error checking session revocation: {e}")
            pass
    
    if not license_id or not jti:
        return None
    
    # CRITICAL FIX #1: Add token version check to prevent refresh after revocation
    # This ensures that even with a valid refresh token, if the token version has
    # changed (e.g., admin forced logout), the refresh will fail
    from database import validate_license_by_id
    validation = await validate_license_by_id(
        license_id, 
        required_version=payload.get("v")
    )
    if not validation.get("valid"):
        logger.warning(f"Token version mismatch or account inactive for license {license_id} during refresh")
        return None
        
    if not family_id:
        # Legacy support
        return await create_token_pair(
            user_id=payload.get("sub"),
            license_id=license_id,
            role=payload.get("role", "user"),
            device_fingerprint=device_fingerprint,
            ip_address=ip_address,
        )
        
    # RTR Logic
    from db_helper import get_db, fetch_one, execute_sql, commit_db
    from database import DB_TYPE

    try:
        async with get_db() as db:
            # CRITICAL SECURITY FIX: Use SELECT FOR UPDATE to prevent race conditions
            # This ensures atomic check-and-update for token theft detection
            # Without this, concurrent refresh requests could bypass the theft detection
            if DB_TYPE == "postgresql":
                # Use FOR UPDATE with SKIP LOCKED to prevent deadlocks
                session = await fetch_one(
                    db,
                    "SELECT * FROM device_sessions WHERE family_id = ? FOR UPDATE SKIP LOCKED",
                    [family_id]
                )
            else:
                # SQLite doesn't support FOR UPDATE, use immediate transaction
                await execute_sql(db, "BEGIN IMMEDIATE")
                session = await fetch_one(db, "SELECT * FROM device_sessions WHERE family_id = ?", [family_id])

            if not session:
                logger.warning(f"Device session {family_id} not found or locked.")
                return None

            if session["is_revoked"]:
                logger.warning(f"Session {family_id} is revoked.")
                return None

            # Security Hardening: Device Secret Binding Verification
            stored_hash = session.get("device_secret_hash")
            if stored_hash: # Enforce only if session was created with a secret (backwards compat)
                if not device_secret:
                    logger.warning(f"Refresh failed: Missing device_secret for bound session {family_id}")
                    return None
                # SECURITY FIX: Use peppered hash for device secret verification
                from security import hash_device_secret
                computed_hash = hash_device_secret(device_secret)
                if not hmac.compare_digest(computed_hash, stored_hash):
                    logger.warning(f"Refresh failed: Invalid device_secret for session {family_id}")
                    return None

            if session["refresh_token_jti"] != jti:
                # TOKEN THEFT DETECTED
                # Race condition is now prevented by SELECT FOR UPDATE
                logger.warning(f"Token theft detected for family {family_id}. Revoking entire session chain.")
                if DB_TYPE == "postgresql":
                    await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE family_id = ?", [family_id])
                else:
                    await execute_sql(db, "UPDATE device_sessions SET is_revoked = 1 WHERE family_id = ?", [family_id])
                await commit_db(db)
                # Invalidate cache
                _session_revocation_cache.invalidate(family_id)
                return None

            # FIX: Upgrade legacy sessions to bound sessions if device_secret provided
            effective_device_hash = stored_hash
            if not stored_hash and device_secret:
                # This is a legacy session upgrading to device-bound
                # SECURITY FIX: Use peppered hash for device binding
                from security import hash_device_secret
                effective_device_hash = hash_device_secret(device_secret)
                # Update the session with the new binding
                await execute_sql(
                    db,
                    "UPDATE device_sessions SET device_secret_hash = ? WHERE family_id = ?",
                    [effective_device_hash, family_id]
                )
                await commit_db(db)
                logger.info(f"Upgraded legacy session {family_id} to device-bound")

            # Valid rotation
            return await create_token_pair(
                user_id=payload.get("sub"),
                license_id=license_id,
                role=payload.get("role", "user"),
                device_fingerprint=device_fingerprint,
                ip_address=ip_address,
                family_id=family_id,
                device_secret_hash=effective_device_hash, # Keep the binding alive on rotation
                user_agent=user_agent
            )

    except Exception as e:
        logger.error(f"Error during RTR check: {e}")
        return None


# ============ FastAPI Dependencies ============

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> Dict[str, Any]:
    """
    FastAPI dependency to get current authenticated user.
    
    Usage:
        @app.get("/protected")
        async def protected_route(user: dict = Depends(get_current_user)):
            return {"user": user}
    """
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    payload = await verify_token_async(credentials.credentials, TokenType.ACCESS)
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Real-time Session Revocation Check (Specific to this device/session)
    # FIX: Added caching to reduce DB load
    family_id = payload.get("family_id")
    if family_id:
        # Check cache first
        cached_revoked = _session_revocation_cache.get(family_id)
        if cached_revoked is not None:
            if cached_revoked:
                logger.warning(f"Blocking access token for revoked session (cached): {family_id}")
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Session has been revoked",
                    headers={"WWW-Authenticate": "Bearer"},
                )
        else:
            # Cache miss - check database and update cache
            from db_helper import get_db, fetch_one
            try:
                async with get_db() as db:
                    session = await fetch_one(db, "SELECT is_revoked FROM device_sessions WHERE family_id = ?", [family_id])
                    is_revoked = session.get("is_revoked") if session else False
                    _session_revocation_cache.set(family_id, is_revoked)
                    
                    if is_revoked:
                        logger.warning(f"Blocking access token for revoked session: {family_id}")
                        raise HTTPException(
                            status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Session has been revoked",
                            headers={"WWW-Authenticate": "Bearer"},
                        )
            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"Error checking session revocation in get_current_user: {e}")
                pass
    
    # Senior Engineering Hardening: Atomic Validation via Database Layer
    license_id = payload.get("license_id")
    if license_id:
        from database import validate_license_by_id
        
        # This one call handles: Redis Cache, DB Fallback, Account Activity, and Token Versioning
        validation = await validate_license_by_id(
            license_id, 
            required_version=payload.get("v")
        )
        
        if not validation.get("valid"):
            status_code = status.HTTP_401_UNAUTHORIZED
            if validation.get("code") == "ACCOUNT_DEACTIVATED":
                status_code = status.HTTP_403_FORBIDDEN
                
            raise HTTPException(
                status_code=status_code,
                detail=validation.get("error", "Invalid session"),
                headers={"WWW-Authenticate": "Bearer"},
            )

    return {
        "user_id": payload.get("sub"),
        "license_id": payload.get("license_id"),
        "role": payload.get("role", "user"),
    }


async def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> Optional[Dict[str, Any]]:
    """Optional authentication - returns None if not authenticated"""
    if not credentials:
        return None
    
    payload = await verify_token_async(credentials.credentials, TokenType.ACCESS)
    if not payload:
        return None
    
    return {
        "user_id": payload.get("sub"),
        "license_id": payload.get("license_id"),
        "role": payload.get("role", "user"),
    }
