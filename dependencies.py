"""
Shared FastAPI dependency helpers for Al-Mudeer.

These functions centralize repeated header-based auth logic without
changing any response shapes that the frontend relies on.
"""

from fastapi import Header, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Dict, Optional

from database import validate_license_key, validate_license_by_id

# Re-use the security scheme and dependencies from services.jwt_auth
from services.jwt_auth import security, get_current_user, get_current_user_optional

async def get_license_from_header(
    x_license_key: Optional[str] = Header(None, alias="X-License-Key"),
    auth: Optional[HTTPAuthorizationCredentials] = Depends(security)
) -> Dict:
    """
    Resolve and validate a license from either:
    1. JWT Bearer token in 'Authorization' header
    2. Legacy 'X-License-Key' header
    """
    # 1. Try JWT first (Post-login state)
    if auth:
        from services.jwt_auth import verify_token_async, TokenType
        payload = await verify_token_async(auth.credentials, TokenType.ACCESS)
        
        if payload and payload.get("license_id"):
            result = await validate_license_by_id(payload["license_id"])
            if result.get("valid"):
                # Add user_id to result for compatibility with routes that expect it
                result["user_id"] = payload.get("sub")
                return result
            else:
                # If JWT points to an expired/invalid license, fail fast
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED, 
                    detail=result.get("error", "جلسة العمل منتهية")
                )

    # 2. Fallback to legacy license key (Pre-login or manual API usage)
    if not x_license_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, 
            detail="مفتاح الاشتراك مطلوب للمتابعة"
        )

    result = await validate_license_key(x_license_key)
    if not result.get("valid"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, 
            detail=result.get("error", "مفتاح الاشتراك غير صالح")
        )

    return result


async def get_optional_license_from_header(
    x_license_key: Optional[str] = Header(None, alias="X-License-Key"),
    auth: Optional[HTTPAuthorizationCredentials] = Depends(security)
) -> Optional[Dict]:
    """
    Version of get_license_from_header that never raises.
    """
    # 1. Try JWT
    if auth:
        from services.jwt_auth import verify_token_async, TokenType
        payload = await verify_token_async(auth.credentials, TokenType.ACCESS)
        if payload and payload.get("license_id"):
            result = await validate_license_by_id(payload["license_id"])
            if result.get("valid"):
                result["user_id"] = payload.get("sub")
                return result

    # 2. Try license key
    if not x_license_key:
        return None

    result = await validate_license_key(x_license_key)
    if not result.get("valid"):
        return None

    return result


