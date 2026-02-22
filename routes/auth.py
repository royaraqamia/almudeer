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
async def login(data: LoginRequest):
    """
    Login with license key.
    
    Returns JWT tokens for authenticated access.
    """
    result = await validate_license_key(data.license_key)
    
    if not result.get("valid"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=result.get("error", "Invalid license key"),
        )
    
    tokens = await create_token_pair(
        user_id=data.license_key[:20],
        license_id=result.get("license_id"),
        role="user",
    )
    
    return TokenResponse(
        **tokens,
        user={
            "license_id": result.get("license_id"),
            "company_name": result.get("full_name"),
            "username": result.get("username"),
        }
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(data: RefreshRequest):
    """
    Refresh an expired access token.
    
    Use the refresh token to get a new access token.
    """
    result = await refresh_access_token(data.refresh_token)
    
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
    
    The token will be blacklisted and cannot be used again.
    """
    from fastapi import Request
    
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
                blacklist_token(jti, expires_at)
                
                security_logger = get_security_logger()
                security_logger.log_logout(user.get('user_id'))
                security_logger.log_token_blacklisted(user.get('user_id'), jti)
                
                logger.info(f"User logged out and token blacklisted: {user.get('user_id')}")
        except Exception as e:
            logger.warning(f"Could not blacklist token on logout: {e}")
    
    return {"success": True, "message": "Logged out successfully"}
