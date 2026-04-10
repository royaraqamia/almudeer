"""
Al-Mudeer - JWT Authentication Service
Production-ready JWT authentication with access/refresh tokens

Session Management:
- Sessions are tracked in device_sessions table for admin oversight
- Only admin-initiated revocation will log users out
- No automatic session revocation for better user experience
"""

import os
import secrets
import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass

from jose import jwt, JWTError
from starlette.concurrency import run_in_threadpool

from logging_config import get_logger
from db_helper import execute_sql, commit_db

logger = get_logger(__name__)


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
    # FIX: Access tokens expire after 30 minutes (industry standard for short-lived tokens)
    # Offline grace period allows expired tokens to work briefly for offline-first UX
    access_token_expire_minutes: int = int(os.getenv("JWT_ACCESS_EXPIRE_MINUTES", "30"))
    refresh_token_expire_days: int = int(os.getenv("JWT_REFRESH_EXPIRE_DAYS", "7"))
    # Offline grace period: allow expired access tokens within this window for offline-first
    # During grace period, API calls succeed but a background refresh is triggered
    offline_grace_minutes: int = int(os.getenv("JWT_OFFLINE_GRACE_MINUTES", "60"))

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
    Create a JWT access token with proper expiration.

    Args:
        data: Payload data (should include 'sub' for subject/user ID)
        expires_delta: Custom expiration time

    Returns:
        Tuple of (encoded_token, jti, expiry_datetime)
    """
    to_encode = data.copy()
    now = datetime.now(timezone.utc)

    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=config.access_token_expire_minutes)

    # SECURITY FIX: Generate JTI with 32 bytes (256 bits) for collision resistance
    jti = secrets.token_hex(32)

    to_encode.update({
        "iat": now,
        "exp": expire,
        "type": TokenType.ACCESS,
        "jti": jti,
    })

    return jwt.encode(to_encode, config.secret_key, algorithm=config.algorithm), jti, expire


def create_refresh_token(data: Dict[str, Any], family_id: str = None) -> Tuple[str, str]:
    """
    Create a JWT refresh token with proper expiration (longer than access token).

    Args:
        data: Payload data (should include 'sub' for subject/user ID)

    Returns:
        Tuple of (encoded_token_string, jti)
    """
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=config.refresh_token_expire_days)

    # SECURITY FIX: Generate JTI with 32 bytes (256 bits) for collision resistance
    jti = secrets.token_hex(32)

    to_encode.update({
        "iat": now,
        "exp": expire,
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
    ip_address: str = None,
    family_id: str = None,
    user_agent: str = None,
    device_fingerprint: str = None,
) -> Dict[str, Any]:
    """
    Create both access and refresh tokens. Track device session for admin oversight.

    Note: Sessions are only revoked by admin action, not automatically.

    SECURITY FIX: Device fingerprint is embedded in JWT to bind tokens to a specific device.
    On refresh, the fingerprint is validated to prevent token replay from other devices.
    """
    # Fetch current token_version for the license to embed in JWT
    from database import get_db, fetch_one
    
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

    # Note: We no longer automatically revoke sessions on login
    # Admin-initiated revocation is the only way sessions are revoked
    # This provides a smoother user experience

    payload = {
        "sub": user_id,
        "license_id": license_id,
        "role": role,
        "v": token_version, # Token version for server-side kill-switch
        "family_id": family_id,
    }

    # SECURITY FIX: Bind token to device fingerprint to prevent cross-device replay
    if device_fingerprint:
        payload["dfp"] = hashlib.sha256(device_fingerprint.encode()).hexdigest()[:16]

    access_token, jti, expires_at = await create_access_token_async(payload)
    refresh_token, refresh_jti = await create_refresh_token_async(payload, family_id=family_id)

    # Session Intelligence: Resolve location and parse device name
    from services.session_intelligence import resolve_location, parse_device_info
    location = await resolve_location(ip_address)
    device_name = parse_device_info(user_agent)

    # Store session in DB for audit/admin oversight
    if license_id:
        from database import DB_TYPE
        from db_helper import execute_sql, commit_db
        try:
            async with get_db() as db:
                # Use timezone-aware datetime
                expires_db = datetime.now(timezone.utc) + timedelta(days=config.refresh_token_expire_days)

                if is_new_family:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            INSERT INTO device_sessions
                            (license_key_id, family_id, refresh_token_jti, ip_address, expires_at, device_name, location, user_agent)
                            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                        """, [license_id, family_id, refresh_jti, ip_address, expires_db, device_name, location, user_agent])
                    else:
                        await execute_sql(db, """
                            INSERT INTO device_sessions
                            (license_key_id, family_id, refresh_token_jti, ip_address, expires_at, device_name, location, user_agent)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """, [license_id, family_id, refresh_jti, ip_address, expires_db.isoformat(), device_name, location, user_agent])
                else:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            UPDATE device_sessions
                            SET refresh_token_jti = ?, last_used_at = NOW(), expires_at = ?, ip_address = COALESCE(?, ip_address),
                                device_name = COALESCE(?, device_name), location = COALESCE(?, location), user_agent = COALESCE(?, user_agent)
                            WHERE family_id = ?
                        """, [refresh_jti, expires_db, ip_address, device_name, location, user_agent, family_id])
                    else:
                        await execute_sql(db, """
                            UPDATE device_sessions
                            SET refresh_token_jti = ?, last_used_at = CURRENT_TIMESTAMP, expires_at = ?, ip_address = COALESCE(?, ip_address),
                                device_name = COALESCE(?, device_name), location = COALESCE(?, location), user_agent = COALESCE(?, user_agent)
                            WHERE family_id = ?
                        """, [refresh_jti, expires_db.isoformat(), ip_address, device_name, location, user_agent, family_id])

                await commit_db(db)

        except Exception as e:
            logger.error(f"Error updating device session: {e}")

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
    Verify and decode a JWT token with proper expiration checking.

    For access tokens, supports an offline grace period: if the token is
    expired but within the grace window, it still validates successfully.
    This enables offline-first UX — the client can make API calls while
    offline, and a background refresh will be triggered.

    Args:
        token: JWT token string
        token_type: Expected token type (access/refresh)

    Returns:
        Decoded payload or None if invalid
    """
    try:
        payload = jwt.decode(
            token,
            config.secret_key,
            algorithms=[config.algorithm],
            options={"verify_exp": True}  # FIX: Re-enable expiration verification
        )

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
        # OFFLINE-FIRST GRACE: If token is expired but within grace period,
        # still allow the request. The client should refresh in background.
        if token_type == TokenType.ACCESS:
            try:
                payload = jwt.decode(
                    token,
                    config.secret_key,
                    algorithms=[config.algorithm],
                    options={"verify_exp": False}  # Decode without verifying to check grace
                )

                exp_timestamp = payload.get("exp")
                if exp_timestamp:
                    exp_time = datetime.fromtimestamp(exp_timestamp, tz=timezone.utc)
                    now = datetime.now(timezone.utc)
                    grace = timedelta(minutes=config.offline_grace_minutes)

                    if now - exp_time <= grace:
                        # Token expired but within grace period — allow with flag
                        payload["_offline_grace"] = True
                        logger.debug(f"Access token expired but within grace period ({(now - exp_time).total_seconds():.0f}s ago)")

                        # Still check blacklist
                        jti = payload.get("jti")
                        if jti:
                            from services.token_blacklist import is_token_blacklisted
                            if is_token_blacklisted(jti):
                                return None

                        # Verify token type
                        if payload.get("type") != token_type:
                            return None

                        return payload

                # Outside grace period — reject
                logger.debug(f"Access token expired outside grace period")
                return None

            except JWTError:
                logger.debug(f"JWT verification failed (grace check): {e}")
                return None

        logger.debug(f"JWT verification failed: {e}")
        return None


async def refresh_access_token(
    refresh_token: str,
    ip_address: str = None,
    user_agent: str = None,
    device_fingerprint: str = None,
) -> Optional[Dict[str, Any]]:
    """
    Use a refresh token to get a new access token and rotate the refresh token.

    SECURITY FIXES:
    - Device fingerprint validation: prevents token replay from different devices
    - IP change detection: flags suspicious refresh patterns for admin review
    - Token version check: handles admin-initiated license-level revocation

    Note: Session revocation is only checked at the license level (admin action).
    Individual device sessions are NOT automatically revoked for better UX.
    """
    payload = await verify_token_async(refresh_token, TokenType.REFRESH)

    if not payload:
        return None

    jti = payload.get("jti")
    family_id = payload.get("family_id")
    license_id = payload.get("license_id")
    stored_fingerprint = payload.get("dfp")

    if not license_id:
        return None

    # SECURITY FIX: Validate device fingerprint
    if device_fingerprint and stored_fingerprint:
        provided_hash = hashlib.sha256(device_fingerprint.encode()).hexdigest()[:16]
        if provided_hash != stored_fingerprint:
            logger.warning(
                f"Device fingerprint mismatch on refresh for license {license_id}. "
                f"Token issued for dfp={stored_fingerprint}, got dfp={provided_hash}. "
                f"Possible token replay attack."
            )
            # Reject refresh from different device — force re-authentication
            return None
    elif stored_fingerprint and not device_fingerprint:
        # Token has fingerprint but refresh request doesn't provide one
        # This is a migration path — allow but log
        logger.info(
            f"Refresh without device fingerprint for license {license_id} "
            f"(token has dfp={stored_fingerprint}). Consider client update."
        )

    # SECURITY FIX: Detect suspicious IP changes (different geographic location)
    if ip_address and family_id:
        from database import DB_TYPE
        from db_helper import get_db, fetch_one
        try:
            async with get_db() as db:
                session = await fetch_one(
                    db,
                    "SELECT ip_address FROM device_sessions WHERE family_id = ?",
                    [family_id]
                )
                if session and session.get("ip_address"):
                    original_ip = session.get("ip_address")
                    if original_ip != ip_address:
                        logger.warning(
                            f"IP change detected on refresh for license {license_id}, "
                            f"family {family_id}: {original_ip} -> {ip_address}"
                        )
                        # Log as suspicious activity for admin review
                        from services.security_logger import get_security_logger, SecurityEventType
                        get_security_logger().log_event(
                            SecurityEventType.SUSPICIOUS_ACTIVITY,
                            identifier=f"license:{license_id}",
                            ip_address=ip_address,
                            details={
                                "action": "ip_change_on_refresh",
                                "original_ip": original_ip,
                                "new_ip": ip_address,
                                "family_id": family_id,
                            },
                            severity="WARNING"
                        )
                        # NOTE: We don't reject the refresh here — IP changes can be legitimate
                        # (mobile networks, travel). Admin can review and revoke if needed.
        except Exception as e:
            logger.error(f"Error checking IP during refresh: {e}")

    # Token version check - this handles admin-initiated license-level revocation
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
            ip_address=ip_address,
            device_fingerprint=device_fingerprint,
        )

    # Update session metadata (last used, IP, device info)
    from database import DB_TYPE
    from db_helper import get_db, fetch_one, execute_sql, commit_db

    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                session = await fetch_one(
                    db,
                    "SELECT * FROM device_sessions WHERE family_id = ?",
                    [family_id]
                )
            else:
                session = await fetch_one(db, "SELECT * FROM device_sessions WHERE family_id = ?", [family_id])

            if not session:
                # Session not found - create new session entry
                logger.info(f"Device session {family_id} not found. Creating new session entry.")
                from services.session_intelligence import resolve_location, parse_device_info
                location = await resolve_location(ip_address)
                device_name = parse_device_info(user_agent)
                expires_db = datetime.now(timezone.utc) + timedelta(days=config.refresh_token_expire_days)
                
                if DB_TYPE == "postgresql":
                    await execute_sql(db, """
                        INSERT INTO device_sessions
                        (license_key_id, family_id, refresh_token_jti, ip_address, expires_at, device_name, location, user_agent)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    """, [license_id, family_id, jti, ip_address, expires_db, device_name, location, user_agent])
                else:
                    await execute_sql(db, """
                        INSERT INTO device_sessions
                        (license_key_id, family_id, refresh_token_jti, ip_address, expires_at, device_name, location, user_agent)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [license_id, family_id, jti, ip_address, expires_db.isoformat(), device_name, location, user_agent])
                await commit_db(db)

            # Update refresh token JTI for session tracking
            if DB_TYPE == "postgresql":
                await execute_sql(db, "UPDATE device_sessions SET refresh_token_jti = $1, last_used_at = NOW() WHERE family_id = $2", [jti, family_id])
            else:
                await execute_sql(db, "UPDATE device_sessions SET refresh_token_jti = ?, last_used_at = CURRENT_TIMESTAMP WHERE family_id = ?", [jti, family_id])
            await commit_db(db)

    except Exception as e:
        logger.error(f"Error updating device session: {e}")

    # Issue new token pair
    return await create_token_pair(
        user_id=payload.get("sub"),
        license_id=license_id,
        role=payload.get("role", "user"),
        ip_address=ip_address,
        family_id=family_id,
        user_agent=user_agent,
        device_fingerprint=device_fingerprint,
    )


# ============ FastAPI Dependencies ============

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
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

    # License-level validation (handles admin-initiated account deactivation)
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
        "offline_grace": payload.get("_offline_grace", False),
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
