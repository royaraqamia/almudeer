"""
Al-Mudeer - Authentication Routes
JWT-based login, registration, and token management
"""

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
from services.security_logger import get_security_logger
from services.token_blacklist import blacklist_token

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auth", tags=["Authentication"])


# ============ Request/Response Models ============

class LoginRequest(BaseModel):
    """Login with license key"""
    license_key: str
    device_secret_hash: Optional[str] = None


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
    device_secret: Optional[str] = None


# ============ Auth Endpoints ============

@router.post("/login", response_model=TokenResponse)
async def login(data: LoginRequest, request: Request):
    """
    Login with license key.
    
    Returns JWT tokens for authenticated access.
    """
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
        
        detail_msg = result.get("error", "مفتاح الاشتراك غير صحيح")
        if ip_locked_now:
            detail_msg = "تم حظر هذا الجهاز بسبب محاولات تسجيل الدخول الفاشلة المتكررة. يرجى المحاولة لاحقاً."
        elif check_account_lockout(data.license_key)[0]:
            detail_msg = "تم حظر الحساب بسبب محاولات تسجيل الدخول الفاشلة المتكررة. يرجى المحاولة لاحقاً."
            
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=detail_msg,
        )
        
    # On success, clear failed attempts
    record_successful_login(data.license_key)
    record_successful_login(f"ip:{ip_address}")
    
    # Extract metadata
    ip_address = request.client.host if request.client else None
    device_fingerprint = request.headers.get("User-Agent", "Unknown Device")
    
    tokens = await create_token_pair(
        user_id=str(result.get("license_id")),
        license_id=result.get("license_id"),
        role="user",
        device_fingerprint=device_fingerprint,
        ip_address=ip_address,
        device_secret_hash=data.device_secret_hash,
        user_agent=request.headers.get("User-Agent")
    )
    
    # Remove valid/error from result before returning as user info
    user_info = result.copy()
    user_info.pop("valid", None)
    user_info.pop("error", None)
    # Rename for frontend compatibility if needed (company_name -> full_name handled by UserInfo.fromJson)
    
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
    device_fingerprint = request.headers.get("User-Agent", "Unknown Device")
    
    result = await refresh_access_token(
        data.refresh_token, 
        device_fingerprint, 
        ip_address,
        data.device_secret,
        user_agent=request.headers.get("User-Agent")
    )
    
    if not result:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )
    
    return TokenResponse(**result)


@router.get("/me")
async def get_current_user_info(user: dict = Depends(get_current_user)):
    """Get current user information"""
    return {
        "success": True,
        "user": user,
    }


@router.post("/logout")
async def logout(
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Logout and invalidate the current token.
    """
    
    # Get the token from the Authorization header
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
        
        # Decode to get JTI and expiry
        try:
            from jose import jwt
            from services.jwt_auth import config
            payload = jwt.decode(token, config.secret_key, algorithms=[config.algorithm])
            jti = payload.get("jti")
            exp = payload.get("exp")
            
            if jti and exp:
                from datetime import datetime
                expires_at = datetime.utcfromtimestamp(exp)
                
                from database import DB_TYPE
                from db_helper import get_db, execute_sql, commit_db
                
                family_id = payload.get("family_id")
                if family_id:
                    async with get_db() as db:
                        if DB_TYPE == "postgresql":
                            await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE family_id = ?", [family_id])
                        else:
                            await execute_sql(db, "UPDATE device_sessions SET is_revoked = 1 WHERE family_id = ?", [family_id])
                        await commit_db(db)
                        logger.info(f"Device session revoked for family: {family_id}")

                blacklist_token(jti, expires_at)
                
                security_logger = get_security_logger()
                security_logger.log_logout(user.get('user_id'))
                security_logger.log_token_blacklisted(user.get('user_id'), jti)
                
                logger.info(f"User logged out and token blacklisted: {user.get('user_id')}")
        except Exception as e:
            logger.warning(f"Could not blacklist token or revoke session on logout: {e}")
    
    return {"success": True, "message": "Logged out successfully"}


# ============ Session Management ============

@router.get("/sessions")
async def get_active_sessions(user: dict = Depends(get_current_user)):
    """Get all active sessions for the current user."""
    license_id = user.get("license_id")
    if not license_id:
        return {"success": True, "sessions": []}
        
    from database import DB_TYPE
    from db_helper import get_db, fetch_all
    
    current_time_sql = "NOW()" if DB_TYPE == "postgresql" else "CURRENT_TIMESTAMP"
    
    async with get_db() as db:
        rows = await fetch_all(db, f"""
            SELECT family_id, device_fingerprint, ip_address, created_at, last_used_at 
            FROM device_sessions 
            WHERE license_key_id = ? 
            AND is_revoked = {'FALSE' if DB_TYPE == 'postgresql' else '0'} 
            AND expires_at > {current_time_sql}
            ORDER BY last_used_at DESC
        """, [license_id])
        return {
            "success": True,
            "sessions": [dict(row) for row in rows]
        }


class RevokeSessionRequest(BaseModel):
    family_id: str


@router.post("/sessions/revoke")
async def revoke_session(data: RevokeSessionRequest, user: dict = Depends(get_current_user)):
    """Revoke a specific device session."""
    license_id = user.get("license_id")
    if not license_id:
        raise HTTPException(status_code=400, detail="Invalid user session")
        
    from database import DB_TYPE
    from db_helper import get_db, execute_sql, commit_db
    
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE family_id = ? AND license_key_id = ?", [data.family_id, license_id])
        else:
            await execute_sql(db, "UPDATE device_sessions SET is_revoked = 1 WHERE family_id = ? AND license_key_id = ?", [data.family_id, license_id])
        await commit_db(db)
        
    return {"success": True, "message": "تم تسجيل الخروج من الجهاز بنجاح"}
