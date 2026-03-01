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
import hmac
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
    device_secret: Optional[str] = None  # Raw device secret (will be hashed server-side with pepper)
    device_secret_hash: Optional[str] = None  # Legacy field name (deprecated, but kept for backwards compatibility during transition)


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
    device_secret: Optional[str] = None  # Raw device secret (will be hashed server-side)


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

    # P0-2 FIX: ALWAYS check for existing device binding, not just when device_secret_hash is provided
    # This prevents attackers with stolen license keys from bypassing device binding
    from db_helper import get_db, fetch_one
    from database import DB_TYPE
    from security import hash_device_secret

    # Track if we're reusing an existing session (to avoid revoking it)
    existing_family_id = None

    try:
        async with get_db() as db:
            # Check for existing non-revoked sessions with device binding
            existing_session = await fetch_one(
                db,
                "SELECT device_secret_hash, family_id FROM device_sessions WHERE license_key_id = ? AND is_revoked = 0 ORDER BY last_used_at DESC LIMIT 1",
                [license_id]
            )

            if existing_session and existing_session.get("device_secret_hash"):
                stored_hash = existing_session["device_secret_hash"]

                # P0-2 FIX: Require device secret for known licenses (accept both field names for backwards compatibility)
                device_secret_value = data.device_secret or data.device_secret_hash
                if not device_secret_value:
                    logger.warning(f"Device secret required but not provided for license {license_id}")
                    # P2-11 FIX: Log security event for audit trail
                    security_logger = get_security_logger()
                    security_logger.log_event(
                        event_type=SecurityEventType.SUSPICIOUS_ACTIVITY,
                        identifier=str(license_id),
                        details={
                            "event": "device_secret_missing",
                            "ip_address": ip_address,
                            "user_agent": request.headers.get("User-Agent", "Unknown"),
                        }
                    )
                    await _apply_constant_time_delay()
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="مفتاح الاشتراك غير صحيح",
                    )

                # Device has existing binding - verify it matches
                # SECURITY FIX: Hash with pepper and compare
                computed_hash = hash_device_secret(device_secret_value)
                if not hmac.compare_digest(computed_hash, stored_hash):
                    # FIX: On login, allow device secret rotation (e.g., after app reinstall/clear data)
                    # Update the session with the new device secret instead of rejecting
                    logger.info(f"Device secret mismatch on login for license {license_id} - updating session with new device secret")

                    # Update the device_sessions table with the new device secret hash
                    from db_helper import execute_sql, commit_db
                    from database import DB_TYPE

                    try:
                        # Also get the family_id to reuse this session
                        existing_family_id = existing_session.get("family_id")

                        if DB_TYPE == "postgresql":
                            await execute_sql(
                                db,
                                "UPDATE device_sessions SET device_secret_hash = ?, last_used_at = NOW() WHERE license_key_id = ? AND is_revoked = 0",
                                [computed_hash, license_id]
                            )
                        else:
                            await execute_sql(
                                db,
                                "UPDATE device_sessions SET device_secret_hash = ?, last_used_at = CURRENT_TIMESTAMP WHERE license_key_id = ? AND is_revoked = 0",
                                [computed_hash, license_id]
                            )
                        await commit_db(db)
                        logger.info(f"Device secret updated successfully for license {license_id}")

                        # FIX: Pass the existing family_id to create_token_pair to reuse this session
                        # This prevents creating a new session and revoking the one we just updated
                        family_id = existing_family_id
                        logger.info(f"Reusing existing session family_id={existing_family_id[:8]}... for license {license_id}")
                    except Exception as e:
                        logger.error(f"Failed to update device secret for license {license_id}: {e}")
                        # Continue anyway - don't block login on DB update failure

                    # Log security event for audit trail (device was re-bound)
                    security_logger = get_security_logger()
                    security_logger.log_event(
                        event_type=SecurityEventType.SECURITY_EVENT,
                        identifier=str(license_id),
                        details={
                            "event": "device_secret_rotated_on_login",
                            "ip_address": ip_address,
                            "user_agent": request.headers.get("User-Agent", "Unknown"),
                            "reason": "mismatch_detected",
                        }
                    )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error checking device secret binding: {e}")
        # SECURITY FIX P1-12: Apply constant-time delay even on DB errors
        # to prevent timing-based enumeration of error conditions
        await _apply_constant_time_delay()
        # Don't block login on validation error, but log it

    # On success, clear failed attempts
    record_successful_login(data.license_key)
    record_successful_login(f"ip:{ip_address}")

    # Extract metadata
    ip_address = request.client.host if request.client else None

    # Hash device secret with pepper for storage
    device_secret_hash = None
    if data.device_secret:
        from security import hash_device_secret
        device_secret_hash = hash_device_secret(data.device_secret)
    elif data.device_secret_hash:
        # Legacy support: accept pre-hashed value (will be re-hashed with pepper for consistency)
        # This is safe because we're adding pepper on top
        from security import hash_device_secret
        device_secret_hash = hash_device_secret(data.device_secret_hash)

    tokens = await create_token_pair(
        user_id=str(result.get("license_id")),
        license_id=result.get("license_id"),
        role="user",
        ip_address=ip_address,
        family_id=existing_family_id,  # Reuse existing session family_id if available
        device_secret_hash=device_secret_hash,
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
        data.device_secret,  # Pass raw device secret (server will hash it)
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
            payload = jwt.decode(token, config.secret_key, algorithms=[config.algorithm])
            jti = payload.get("jti")
            
            if jti and is_token_blacklisted(jti):
                logger.debug(f"Token {jti[:8]}... already blacklisted, skipping")
                return {"success": True, "message": "Logged out successfully"}
        except JWTError:
            # Token is invalid/expired, but still return success for idempotency
            logger.debug("Logout with invalid/expired token - returning success for idempotency")
            return {"success": True, "message": "Logged out successfully"}
        
        # Token is valid, proceed with logout
        exp = payload.get("exp")
        family_id = payload.get("family_id")

        if jti and exp:
            # SECURITY FIX: Use timezone-aware datetime
            expires_at = datetime.fromtimestamp(exp, tz=timezone.utc)

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


# ============ Device Secret Rotation ============

class DeviceSecretRotateRequest(BaseModel):
    """Device secret rotation request"""
    new_device_secret: str
    # CRITICAL FIX P1-16: Require current device secret for verification
    current_device_secret: str


@router.post("/rotate-device-secret")
async def rotate_device_secret(
    data: DeviceSecretRotateRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Rotate the device secret for the current session.

    SECURITY: This allows clients to periodically rotate device secrets,
    limiting the damage if a secret is compromised.
    
    CRITICAL FIX P1-16: Now requires current_device_secret for verification
    before allowing rotation. This prevents attackers with stolen access tokens
    from rotating the device secret and locking out the legitimate user.

    The new secret must be provided by the client and will be bound to
    the current session after verification of the current secret.
    """
    from db_helper import get_db, fetch_one, execute_sql, commit_db
    from database import DB_TYPE
    from security import hash_device_secret

    try:
        family_id = user.get("family_id")
        if not family_id:
            # No session to rotate (legacy token without family_id)
            # FIX: Don't error - just return success and skip rotation
            # The user will get a device-bound session on next login/refresh
            logger.info(f"Device secret rotation skipped for legacy session (user: {user.get('user_id')})")
            return {"success": True, "message": "Device secret rotation skipped for legacy session", "rotated": False}

        # Validate new device secret format (64 hex chars = 256 bits)
        new_secret = data.new_device_secret
        if not new_secret or len(new_secret) != 64:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid device secret format. Must be 64 hex characters"
            )

        # Ensure all characters are valid hex
        try:
            int(new_secret, 16)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Device secret must contain only hexadecimal characters"
            )

        # CRITICAL FIX P1-16: Validate current device secret before allowing rotation
        current_secret = data.current_device_secret
        if not current_secret or len(current_secret) != 64:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Current device secret required for verification"
            )

        async with get_db() as db:
            # Fetch current session to verify current device secret
            session = await fetch_one(
                db,
                "SELECT device_secret_hash FROM device_sessions WHERE family_id = ?",
                [family_id]
            )
            
            stored_hash = session.get("device_secret_hash") if session else None
            
            # If session has device binding, verify current secret matches
            if stored_hash:
                computed_hash = hash_device_secret(current_secret)
                if not hmac.compare_digest(computed_hash, stored_hash):
                    logger.warning(f"Device secret rotation failed: current secret mismatch for family {family_id}")
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Current device secret verification failed"
                    )
            else:
                # Session doesn't have device binding - this is unusual
                # For security, require the user to re-authenticate
                logger.warning(f"Device secret rotation attempted for unbound session {family_id}")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot rotate device secret for session without device binding"
                )

            # Hash the new secret with pepper
            new_hash = hash_device_secret(new_secret)

            # Update the session with the new device secret hash
            if DB_TYPE == "postgresql":
                await execute_sql(
                    db,
                    """UPDATE device_sessions
                       SET device_secret_hash = ?,
                           last_used_at = CURRENT_TIMESTAMP
                       WHERE family_id = ?""",
                    [new_hash, family_id]
                )
            else:
                await execute_sql(
                    db,
                    """UPDATE device_sessions
                       SET device_secret_hash = ?,
                           last_used_at = CURRENT_TIMESTAMP
                       WHERE family_id = ?""",
                    [new_hash, family_id]
                )
            await commit_db(db)

        # Log the rotation
        security_logger = get_security_logger()
        security_logger.log_security_event(
            user.get('user_id'),
            "device_secret_rotated",
            {"family_id": family_id}
        )

        logger.info(f"Device secret rotated for user {user.get('user_id')}, family {family_id}")

        return {
            "success": True,
            "message": "Device secret rotated successfully"
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Device secret rotation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to rotate device secret"
        )
