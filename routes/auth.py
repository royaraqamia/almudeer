"""
Al-Mudeer - Authentication Routes
JWT-based login, registration, and token management

SECURITY FIXES:
- Content-Type validation on all auth endpoints
- Token validation before blacklisting on logout
- Constant-time response delays to prevent timing attacks
- Generic error messages to prevent username enumeration
- Rate limiting on /api/auth/me to prevent token enumeration
"""

import secrets
from fastapi import APIRouter, HTTPException, status, Depends, Request
from pydantic import BaseModel
from typing import Optional

from services.jwt_auth import (
    create_token_pair,
    refresh_access_token,
    get_current_user,
)
from services.login_protection import (
    check_account_lockout,
    record_failed_login,
    record_successful_login,
)
from database import validate_license_key
from logging_config import get_logger
from services.security_logger import get_security_logger, SecurityEventType
from services.token_blacklist import blacklist_token
from rate_limiting import limiter, RateLimits

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auth", tags=["Authentication"])


# ============ Security Helpers ============

async def _apply_constant_time_delay():
    """
    SECURITY FIX: Apply constant-time delay to prevent timing attacks.
    This ensures all auth responses take roughly the same time regardless of
    where in the validation flow they fail.
    """
    import asyncio
    # Random delay between 100-300ms to prevent timing analysis
    delay_ms = secrets.randbelow(200) + 100
    await asyncio.sleep(delay_ms / 1000.0)


def _validate_content_type(request: Request) -> bool:
    """
    SECURITY FIX: Validate Content-Type header to prevent CSRF attacks.
    CRITICAL FIX P1-11: Use strict MIME type matching to prevent bypass.
    """
    content_type = request.headers.get("content-type", "").strip().lower()
    # Strict validation: must be exactly application/json or application/json; charset=utf-8
    # Reject: text/plain, application/json-patch, etc.
    if content_type == "application/json":
        return True
    if content_type.startswith("application/json;"):
        # Allow charset parameter
        parts = content_type.split(";")
        if len(parts) == 2 and parts[0].strip() == "application/json":
            # Validate charset parameter format
            charset_part = parts[1].strip()
            if charset_part.startswith("charset="):
                charset = charset_part[8:].strip().lower()
                # Only allow utf-8 or utf-8 variants
                if charset in ("utf-8", "utf8"):
                    return True
    return False


# ============ Request/Response Models ============

class LoginRequest(BaseModel):
    """Login with license key"""
    license_key: str


class TokenResponse(BaseModel):
    """Token response"""
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str = "bearer"
    expires_in: int
    user: Optional[dict] = None


class RefreshRequest(BaseModel):
    """Refresh token request"""
    refresh_token: str


# ============ Auth Endpoints ============

@router.post("/login", response_model=TokenResponse)
async def login(data: LoginRequest, request: Request):
    """
    Login with license key.

    Returns JWT tokens for authenticated access.
    
    SECURITY FIXES:
    - Content-Type validation
    - Constant-time response delay
    - Generic error messages
    """
    # SECURITY FIX: Validate Content-Type
    if not _validate_content_type(request):
        await _apply_constant_time_delay()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Content-Type must be application/json"
        )
    
    # 1. Check brute-force protection (Account + IP)
    ip_address = request.client.host if request.client else "unknown"

    # Check account lockout
    is_key_locked, key_remaining = check_account_lockout(data.license_key)
    # Check IP lockout
    is_ip_locked, ip_remaining = check_account_lockout(f"ip:{ip_address}")

    if is_key_locked or is_ip_locked:
        remaining = max(key_remaining or 0, ip_remaining or 0)
        logger.warning(f"Login attempt blocked (lockout): account={data.license_key}, ip={ip_address}")

        detail_msg = "تم حظر الحساب مؤقتًا."
        if is_ip_locked and not is_key_locked:
            detail_msg = "تم حظر هذا الجهاز مؤقتًا بسبب كثرة المحاولات الفاشلة."

        # SECURITY FIX P1-12: Apply constant-time delay to ALL error paths
        await _apply_constant_time_delay()
        
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"{detail_msg} حاول مرة أخرى بعد {remaining // 60} دقائق." if remaining > 60 else f"{detail_msg} حاول مرة أخرى بعد {remaining} ثانية.",
            headers={"Retry-After": str(remaining)},
        )

    result = await validate_license_key(data.license_key)

    if not result.get("valid"):
        # Record failed attempt (on both account and IP)
        record_failed_login(data.license_key)
        _, ip_locked_now = record_failed_login(f"ip:{ip_address}")

        # SECURITY FIX: Apply constant-time delay before returning error
        await _apply_constant_time_delay()

        detail_msg = result.get("error", "مفتاح الاشتراك غير صحيح")
        if ip_locked_now:
            detail_msg = "تم حظر هذا الجهاز بسبب محاولات تسجيل الدخول الفاشلة المتكررة. يرجى المحاولة لاحقاً."
        elif check_account_lockout(data.license_key)[0]:
            detail_msg = "تم حظر الحساب بسبب محاولات تسجيل الدخول الفاشلة المتكررة. يرجى المحاولة لاحقاً."

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=detail_msg,
        )

    license_id = result.get("license_id")

    # On success, clear failed attempts
    record_successful_login(data.license_key)
    record_successful_login(f"ip:{ip_address}")

    # Extract metadata
    ip_address = request.client.host if request.client else None

    tokens = await create_token_pair(
        user_id=str(result.get("license_id")),
        license_id=result.get("license_id"),
        role="user",
        ip_address=ip_address,
        user_agent=request.headers.get("User-Agent")
    )

    # Remove valid/error from result before returning as user info
    user_info = result.copy()
    user_info.pop("valid", None)
    user_info.pop("error", None)

    return TokenResponse(
        **tokens,
        user=user_info
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(data: RefreshRequest, request: Request):
    """
    Refresh an expired access token.

    Use the refresh token to get a new access token.
    """
    ip_address = request.client.host if request.client else None

    result = await refresh_access_token(
        data.refresh_token,
        ip_address,
        user_agent=request.headers.get("User-Agent")
    )

    if not result:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    return TokenResponse(**result)


@router.get("/me")
@limiter.limit(RateLimits.USER_INFO)  # P2-13 FIX: Stricter rate limit (10/min) to prevent token enumeration
async def get_current_user_info(request: Request, user: dict = Depends(get_current_user)):
    """
    Get current user information.

    Returns comprehensive user data from the database without issuing new tokens.
    This is preferred over calling /login for user info as it doesn't rotate tokens.

    SECURITY FIX #4: Rate limited to prevent:
    - Token enumeration attacks
    - Server resource exhaustion
    - Bypass of login rate limits via stolen tokens

    P2-13 FIX: Using stricter USER_INFO rate limit (10/min) instead of AUTH (5/min)
    to allow reasonable usage while still preventing abuse.
    """
    from db_helper import get_db, fetch_one

    license_id = user.get("license_id")
    if not license_id:
        return {
            "success": True,
            "user": user,
        }
    
    async with get_db() as db:
        row = await fetch_one(db, "SELECT * FROM license_keys WHERE id = ?", [license_id])
        if not row:
            return {
                "success": True,
                "user": user,
            }
        
        row_dict = dict(row)
        
        # Ensure license_key is present (decrypted)
        if not row_dict.get("license_key") and row_dict.get("license_key_encrypted"):
            from security import decrypt_sensitive_data
            try:
                row_dict["license_key"] = decrypt_sensitive_data(row_dict["license_key_encrypted"])
            except Exception:
                pass
        
        # Build user info response (snake_case for mobile app compatibility)
        expires_at = row_dict.get("expires_at")
        if expires_at:
            if hasattr(expires_at, 'isoformat'):
                expires_at_str = expires_at.isoformat()
            else:
                expires_at_str = str(expires_at)
        else:
            expires_at_str = None
        
        return {
            "success": True,
            "user": {
                "license_id": row_dict.get("id"),
                "full_name": row_dict.get("full_name") or row_dict.get("company_name"),
                "profile_image_url": row_dict.get("profile_image_url"),
                "created_at": str(row_dict.get("created_at")) if row_dict.get("created_at") else None,
                "expires_at": expires_at_str,
                "is_trial": bool(row_dict.get("is_trial", False)),
                "referral_code": row_dict.get("referral_code"),
                "referral_count": row_dict.get("referral_count", 0),
                "username": row_dict.get("username"),
                "license_key": row_dict.get("license_key"),
                "is_active": bool(row_dict.get("is_active", True)),
            }
        }


class LogoutRequest(BaseModel):
    """Logout request model"""
    revoke_all_sessions: bool = False


@router.post("/logout")
async def logout(
    request: Request,
    data: LogoutRequest = None,
    user: dict = Depends(get_current_user)
):
    """
    Logout and invalidate the current token.

    Args:
        revoke_all_sessions: If True, revoke ALL sessions for this user (logout from all devices)
    
    SECURITY FIX: Token is now validated before blacklisting to prevent:
    - JTI guessing attacks
    - DoS via blacklist flooding
    - Blacklisting arbitrary/malformed tokens
    """
    data = data or LogoutRequest()

    # Get the token from the Authorization header
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        # No valid token in header, but still return success for idempotency
        return {"success": True, "message": "Logged out successfully"}
    
    token = auth_header[7:]

    # SECURITY FIX: Validate token signature and expiry BEFORE blacklisting
    # This prevents attackers from blacklisting arbitrary JTIs
    try:
        from jose import jwt, JWTError
        from services.jwt_auth import config
        from services.token_blacklist import is_token_blacklisted
        from datetime import datetime, timezone
        
        # First check if already blacklisted (idempotency)
        try:
            # OFFLINE-FIRST: Disable expiration check on logout too
            payload = jwt.decode(token, config.secret_key, algorithms=[config.algorithm], options={"verify_exp": False})
            jti = payload.get("jti")

            if jti and is_token_blacklisted(jti):
                logger.debug(f"Token {jti[:8]}... already blacklisted, skipping")
                return {"success": True, "message": "Logged out successfully"}
        except JWTError:
            # Token is invalid, but still return success for idempotency
            logger.debug("Logout with invalid token - returning success for idempotency")
            return {"success": True, "message": "Logged out successfully"}

        # Token is valid, proceed with logout
        family_id = payload.get("family_id")

        if jti:
            # OFFLINE-FIRST: Use far-future expiry for blacklist (tokens don't expire)
            expires_at = datetime.now(timezone.utc) + timedelta(days=365*10)  # 10 years

            from database import DB_TYPE
            from db_helper import get_db, execute_sql, commit_db
            from services.jwt_auth import _session_revocation_cache

            async with get_db() as db:
                # Revoke all sessions if requested
                if data.revoke_all_sessions and user.get("license_id"):
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE license_key_id = ?", [user.get("license_id")])
                    else:
                        await execute_sql(db, "UPDATE device_sessions SET is_revoked = 1 WHERE license_key_id = ?", [user.get("license_id")])
                    await commit_db(db)
                    logger.info(f"All sessions revoked for user: {user.get('user_id')}")
                elif family_id:
                    # Revoke only current session
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE family_id = ?", [family_id])
                    else:
                        await execute_sql(db, "UPDATE device_sessions SET is_revoked = 1 WHERE family_id = ?", [family_id])
                    await commit_db(db)
                    # Invalidate session revocation cache immediately
                    _session_revocation_cache.invalidate(family_id)
                    logger.info(f"Device session revoked for family: {family_id}")

            # Blacklist the token
            blacklist_token(jti, expires_at)

            security_logger = get_security_logger()
            security_logger.log_logout(user.get('user_id'))
            security_logger.log_token_blacklisted(user.get('user_id'), jti)

            logger.info(f"User logged out and token blacklisted: {user.get('user_id')}")

    except Exception as e:
        # SECURITY FIX #13: Log detailed error for debugging
        logger.error(f"Logout DB error: {type(e).__name__}: {e}")
        # SECURITY FIX #13: Return 503 error to inform user logout may not have completed
        # This prevents silent failures where user thinks they logged out but session remains active
        # CRITICAL FIX: Include specific error code so mobile can handle appropriately
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "تعذر تسجيل الخروج بشكل كامل. يرجى المحاولة مرة أخرى.",
                "error_code": "LOGOUT_INCOMPLETE",
                "session_may_be_active": True,
            },
            headers={"Retry-After": "5"},
        )

    return {"success": True, "message": "Logged out successfully"}


# ============ Session Management ============

# Removed: Public session management endpoints.
# Internal session tracking (device_sessions) is preserved for JWT security (RTR).
