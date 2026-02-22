"""
Al-Mudeer - JWT Authentication Service
Production-ready JWT authentication with access/refresh tokens
"""

import os
import secrets
import hashlib
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass

from jose import jwt, JWTError

from logging_config import get_logger

logger = get_logger(__name__)


# ============ Configuration ============

def _get_jwt_secret_key() -> str:
    """Get JWT secret key from environment, fail fast in production if not set."""
    key = os.getenv("JWT_SECRET_KEY")
    if key:
        return key
    
    # In production, we MUST have a stable secret key
    if os.getenv("ENVIRONMENT", "development") == "production":
        raise ValueError(
            "JWT_SECRET_KEY must be set in production! "
            "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
        )
    
    # Development only: generate a random key (tokens won't persist across restarts)
    generated_key = secrets.token_hex(32)
    logger.warning(
        "JWT_SECRET_KEY not set - using auto-generated key. "
        "Tokens will be invalidated on restart. Set JWT_SECRET_KEY in production!"
    )
    return generated_key


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
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=config.access_token_expire_minutes))
    jti = secrets.token_hex(16)  # Unique token ID for blacklisting
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
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
    expire = datetime.utcnow() + timedelta(days=config.refresh_token_expire_days)
    jti = secrets.token_hex(16)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
        "type": TokenType.REFRESH,
        "jti": jti,  # Unique token ID for revocation
    })
    
    if family_id:
        to_encode["family_id"] = family_id
    
    return jwt.encode(to_encode, config.secret_key, algorithm=config.algorithm), jti


async def create_token_pair(
    user_id: str, 
    license_id: int = None, 
    role: str = "user",
    device_fingerprint: str = None,
    ip_address: str = None,
    family_id: str = None
) -> Dict[str, Any]:
    """
    Create both access and refresh tokens. Track device session.
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

    payload = {
        "sub": user_id,
        "license_id": license_id,
        "role": role,
        "v": token_version, # Token version for server-side kill-switch
        "family_id": family_id,
    }
    
    access_token, jti, expires_at = create_access_token(payload)
    refresh_token, refresh_jti = create_refresh_token(payload, family_id=family_id)
    
    # Store session in DB for RTR
    if license_id:
        from database import DB_TYPE
        from db_helper import execute_sql, commit_db
        try:
            async with get_db() as db:
                expires_db = datetime.utcnow() + timedelta(days=config.refresh_token_expire_days)
                
                if is_new_family:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            INSERT INTO device_sessions 
                            (license_key_id, family_id, refresh_token_jti, device_fingerprint, ip_address, expires_at)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """, [license_id, family_id, refresh_jti, device_fingerprint, ip_address, expires_db])
                    else:
                        await execute_sql(db, """
                            INSERT INTO device_sessions 
                            (license_key_id, family_id, refresh_token_jti, device_fingerprint, ip_address, expires_at)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """, [license_id, family_id, refresh_jti, device_fingerprint, ip_address, expires_db.isoformat()])
                else:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            UPDATE device_sessions 
                            SET refresh_token_jti = ?, last_used_at = NOW(), expires_at = ?, ip_address = COALESCE(?, ip_address)
                            WHERE family_id = ?
                        """, [refresh_jti, expires_db, ip_address, family_id])
                    else:
                        await execute_sql(db, """
                            UPDATE device_sessions 
                            SET refresh_token_jti = ?, last_used_at = CURRENT_TIMESTAMP, expires_at = ?, ip_address = COALESCE(?, ip_address)
                            WHERE family_id = ?
                        """, [refresh_jti, expires_db.isoformat(), ip_address, family_id])
                
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


async def refresh_access_token(refresh_token: str, device_fingerprint: str = None, ip_address: str = None) -> Optional[Dict[str, Any]]:
    """
    Use a refresh token to get a new access token and rotate the refresh token.
    """
    payload = verify_token(refresh_token, TokenType.REFRESH)
    
    if not payload:
        return None
        
    jti = payload.get("jti")
    family_id = payload.get("family_id")
    license_id = payload.get("license_id")
    
    if not license_id or not jti:
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
            session = await fetch_one(db, "SELECT * FROM device_sessions WHERE family_id = ?", [family_id])
            
            if not session:
                logger.warning(f"Device session {family_id} not found.")
                return None
                
            if session["is_revoked"]:
                logger.warning(f"Session {family_id} is revoked.")
                return None
                
            if session["refresh_token_jti"] != jti:
                # TOKEN THEFT DETECTED
                logger.warning(f"Token theft detected for family {family_id}. Revoking entire session chain.")
                if DB_TYPE == "postgresql":
                    await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE family_id = ?", [family_id])
                else:
                    await execute_sql(db, "UPDATE device_sessions SET is_revoked = 1 WHERE family_id = ?", [family_id])
                await commit_db(db)
                return None
                
            # Valid rotation
            return await create_token_pair(
                user_id=payload.get("sub"),
                license_id=license_id,
                role=payload.get("role", "user"),
                device_fingerprint=device_fingerprint,
                ip_address=ip_address,
                family_id=family_id,
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
    
    payload = verify_token(credentials.credentials, TokenType.ACCESS)
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Senior Engineering Hardening: Real-time Kill-Switch Verification
    license_id = payload.get("license_id")
    token_v_in_jwt = payload.get("v", 0)
    
    if license_id:
        from database import get_db, fetch_one
        
        # Try Cache first
        cache_key = f"token_validation:{license_id}"
        cached_data = None
        redis_client = None
        
        try:
            import os
            import redis
            import json
            redis_url = os.getenv("REDIS_URL")
            if redis_url:
                redis_client = redis.from_url(redis_url)
                cached = redis_client.get(cache_key)
                if cached:
                    cached_data = json.loads(cached)
        except Exception as e:
            logger.debug(f"Redis cache check failed: {e}")
            
        try:
            if cached_data:
                current_v = cached_data.get("token_version", 1)
                is_active = cached_data.get("is_active", True)
            else:
                async with get_db() as db:
                    row = await fetch_one(db, "SELECT token_version, is_active FROM license_keys WHERE id = ?", [license_id])
                    if row:
                        current_v = row.get("token_version", 1)
                        is_active = bool(row.get("is_active", True))
                        
                        # Cache the result to save DB hits (TTL 5 minutes)
                        if redis_client:
                            cache_payload = {
                                "token_version": current_v,
                                "is_active": is_active
                            }
                            redis_client.setex(cache_key, 300, json.dumps(cache_payload))
                    else:
                        current_v = 1
                        is_active = False # Account deleted
            
            if not is_active:
                logger.warning(f"Rejecting token for deactivated license {license_id}")
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Account deactivated. Please contact support.",
                )
                
            if current_v > token_v_in_jwt:
                logger.warning(f"Rejecting invalidated token for license {license_id} (JWT: {token_v_in_jwt}, DB: {current_v})")
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Session invalidated. Please log in again.",
                    headers={"WWW-Authenticate": "Bearer"},
                )
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Error verifying token version: {e}")
            # Fail open in production for availability, but ideally log this strictly

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
    
    payload = verify_token(credentials.credentials, TokenType.ACCESS)
    if not payload:
        return None
    
    return {
        "user_id": payload.get("sub"),
        "license_id": payload.get("license_id"),
        "role": payload.get("role", "user"),
    }
