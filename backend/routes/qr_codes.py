"""
QR Code API Routes
Endpoints for QR code generation, verification, and management
"""

from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query, Response
from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Dict, Any
from collections import defaultdict
import time

from models.qr_codes import (
    generate_qr_code,
    verify_qr_code,
    get_qr_code,
    list_qr_codes,
    deactivate_qr_code,
    delete_qr_code,
    get_qr_analytics,
    QRCodeType,
    QRCodePurpose,
    QRCodeScanResult,
)
from services.jwt_auth import get_current_user
from dependencies import get_license_from_header
from database import get_db
from db_helper import fetch_one

router = APIRouter(prefix="/qr", tags=["QR Codes"])

# Simple in-memory rate limiting (for production, use Redis)
class RateLimiter:
    """Basic rate limiter using sliding window"""
    
    def __init__(self):
        self._requests: Dict[str, List[float]] = defaultdict(list)
    
    def is_allowed(self, key: str, max_requests: int = 100, window_seconds: int = 60) -> bool:
        """Check if request is allowed within rate limit"""
        now = time.time()
        window_start = now - window_seconds
        
        # Remove old requests outside the window
        self._requests[key] = [t for t in self._requests[key] if t > window_start]
        
        # Check if under limit
        if len(self._requests[key]) < max_requests:
            self._requests[key].append(now)
            return True
        return False
    
    def get_remaining(self, key: str, max_requests: int = 100, window_seconds: int = 60) -> int:
        """Get remaining requests in current window"""
        now = time.time()
        window_start = now - window_seconds
        current_count = len([t for t in self._requests[key] if t > window_start])
        return max(0, max_requests - current_count)

# Global rate limiter instance
_rate_limiter = RateLimiter()

def get_rate_limit_key(request: Request, license_key: Optional[dict] = None) -> str:
    """Generate rate limit key based on license or IP"""
    if license_key:
        return f"license:{license_key['id']}"
    return f"ip:{request.client.host if request.client else 'unknown'}"


# Request/Response Models

class QRCodeGenerateRequest(BaseModel):
    """Request model for generating a QR code"""
    code_data: str = Field(..., description="Data to encode in QR code", min_length=1, max_length=2000)
    code_type: str = Field(default="custom", description="Type of QR code")
    purpose: str = Field(default="other", description="Purpose of QR code")
    title: Optional[str] = Field(None, description="Title for the QR code", max_length=200)
    description: Optional[str] = Field(None, description="Description", max_length=500)
    expires_in_days: Optional[int] = Field(None, ge=1, le=3650, description="Days until expiration")
    max_uses: Optional[int] = Field(None, ge=1, le=10000, description="Maximum number of uses")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Additional metadata")

    @field_validator('code_type')
    @classmethod
    def validate_code_type(cls, v):
        valid_types = [QRCodeType.LICENSE_KEY, QRCodeType.SHARE_LINK,
                      QRCodeType.CUSTOMER_CARD, QRCodeType.CUSTOM]
        if v not in valid_types:
            raise ValueError(f"Invalid code_type. Must be one of: {valid_types}")
        return v

    @field_validator('purpose')
    @classmethod
    def validate_purpose(cls, v):
        valid_purposes = [QRCodePurpose.AUTHENTICATION, QRCodePurpose.SHARING,
                         QRCodePurpose.PAYMENT, QRCodePurpose.CONTACT,
                         QRCodePurpose.URL, QRCodePurpose.TEXT, QRCodePurpose.OTHER]
        if v not in valid_purposes:
            raise ValueError(f"Invalid purpose. Must be one of: {valid_purposes}")
        return v


class QRCodeResponse(BaseModel):
    """Response model for QR code"""
    id: int
    code_hash: str
    code_data: str
    code_type: str
    purpose: str
    title: Optional[str]
    description: Optional[str]
    is_active: bool
    is_used: bool
    use_count: int
    max_uses: Optional[int]
    expires_at: Optional[datetime]
    created_at: datetime
    qr_encode_data: str  # The actual data to encode in QR image


class QRCodeVerifyResponse(BaseModel):
    """Response model for QR code verification"""
    valid: bool
    error: Optional[str]
    error_code: Optional[str]
    qr_code: Optional[Dict[str, Any]]
    use_count: Optional[int]
    max_uses: Optional[int]
    expires_at: Optional[datetime]


class QRCodeListResponse(BaseModel):
    """Response model for listing QR codes"""
    qr_codes: List[QRCodeResponse]
    total: int
    limit: int
    offset: int


class QRAnalyticsResponse(BaseModel):
    """Response model for QR code analytics"""
    total_scans: int
    scans_by_result: Dict[str, int]
    recent_scans: List[Dict[str, Any]]
    period_days: int


# Routes

@router.post("/generate", response_model=QRCodeResponse, status_code=status.HTTP_201_CREATED)
async def create_qr_code(
    request: QRCodeGenerateRequest,
    current_user: dict = Depends(get_current_user),
    license_key: dict = Depends(get_license_from_header),
    db: dict = Depends(get_db),
):
    """
    Generate a new QR code

    - **code_data**: The data to encode in the QR code
    - **code_type**: Type of QR code (license_key, share_link, customer_card, custom)
    - **purpose**: Purpose (authentication, sharing, payment, contact, url, text, other)
    - **expires_in_days**: Optional expiration in days (1-3650)
    - **max_uses**: Optional maximum number of uses (1-10000)

    Returns the QR code details including the data to encode.
    """
    # Rate limiting for QR generation
    rate_limit_key = get_rate_limit_key(Request(scope={"client": None}), license_key)
    if not _rate_limiter.is_allowed(rate_limit_key, max_requests=50, window_seconds=60):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded. Please try again later.",
        )
    
    try:
        qr_code = await generate_qr_code(
            license_key_id=license_key["id"],
            code_data=request.code_data,
            code_type=request.code_type,
            purpose=request.purpose,
            title=request.title,
            description=request.description,
            expires_in_days=request.expires_in_days,
            max_uses=request.max_uses,
            created_by=current_user.get("id"),
            metadata=request.metadata,
        )

        return QRCodeResponse(**qr_code)

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate QR code: {str(e)}"
        )


@router.post("/verify/{code_hash}", response_model=QRCodeVerifyResponse)
async def verify_qr(
    code_hash: str,
    request: Request,
    device_info: Optional[str] = Query(None, description="Device information"),
    latitude: Optional[float] = Query(None, ge=-90.0, le=90.0, description="GPS latitude coordinate"),
    longitude: Optional[float] = Query(None, ge=-180.0, le=180.0, description="GPS longitude coordinate"),
    app_version: Optional[str] = Query(None, description="App version string"),
    # Optional authentication - allows public verification but tracks authenticated users
    current_user: Optional[dict] = Depends(get_current_user),
    license_key: Optional[dict] = Depends(get_license_from_header),
    db: dict = Depends(get_db),
):
    """
    Verify a QR code

    - **code_hash**: The hash of the QR code to verify
    - **device_info**: Optional device information for analytics
    - **latitude**: Optional GPS latitude coordinate (-90 to 90)
    - **longitude**: Optional GPS longitude coordinate (-180 to 180)
    - **app_version**: Optional app version string

    Authentication is optional - QR codes can be verified without authentication,
    but authenticated requests get better rate limits and tracking.

    Returns verification result and QR code details if valid.
    """
    # Rate limiting - stricter for unauthenticated requests
    rate_limit_key = get_rate_limit_key(request, license_key)
    max_requests = 30 if not license_key else 100  # 30/min for public, 100/min for authenticated

    if not _rate_limiter.is_allowed(rate_limit_key, max_requests=max_requests, window_seconds=60):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded. Please try again later.",
            headers={"Retry-After": "60"}
        )

    # Get client IP and user agent
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    result = await verify_qr_code(
        code_hash=code_hash,
        scanned_data=None,
        device_info=device_info,
        ip_address=ip_address,
        user_agent=user_agent,
        latitude=latitude,
        longitude=longitude,
        app_version=app_version,
    )

    # Add rate limiting headers
    response = Response(content_type="application/json")
    remaining = _rate_limiter.get_remaining(rate_limit_key, max_requests=max_requests, window_seconds=60)
    response.headers["X-RateLimit-Limit"] = str(max_requests)
    response.headers["X-RateLimit-Remaining"] = str(remaining)
    response.headers["X-RateLimit-Reset"] = str(int(time.time()) + 60)
    
    # Set response content
    from starlette.responses import JSONResponse
    return JSONResponse(
        content=QRCodeVerifyResponse(**result).model_dump(),
        headers={
            "X-RateLimit-Limit": str(max_requests),
            "X-RateLimit-Remaining": str(remaining),
            "X-RateLimit-Reset": str(int(time.time()) + 60),
        }
    )


@router.get("/{qr_code_id}", response_model=QRCodeResponse)
async def get_qr(
    qr_code_id: int,
    license_key: dict = Depends(get_license_from_header),
    db: dict = Depends(get_db),
):
    """
    Get a specific QR code by ID
    
    Returns the QR code details if it exists and belongs to the license.
    """
    qr_code = await get_qr_code(qr_code_id, license_key["id"])
    
    if not qr_code:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="QR code not found"
        )
    
    # Add qr_encode_data for consistency
    qr_code["qr_encode_data"] = qr_code["code_data"]
    
    return QRCodeResponse(**qr_code)


@router.get("", response_model=QRCodeListResponse)
async def list_qr(
    code_type: Optional[str] = Query(None, description="Filter by code type"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    limit: int = Query(50, ge=1, le=100, description="Number of items to return"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    license_key: dict = Depends(get_license_from_header),
    db: dict = Depends(get_db),
):
    """
    List all QR codes for the license
    
    - **code_type**: Optional filter by code type
    - **is_active**: Optional filter by active status
    - **limit**: Number of items (1-100)
    - **offset**: Pagination offset
    
    Returns a paginated list of QR codes.
    """
    qr_codes = await list_qr_codes(
        license_key_id=license_key["id"],
        code_type=code_type,
        is_active=is_active,
        limit=limit,
        offset=offset,
    )

    # Get total count with proper COUNT query for accurate pagination
    count_query = """
        SELECT COUNT(*) as count FROM qr_codes
        WHERE license_key_id = ? AND deleted_at IS NULL
    """
    count_params: List[Any] = [license_key["id"]]
    
    if code_type:
        count_query += " AND code_type = ?"
        count_params.append(code_type)
    
    if is_active is not None:
        count_query += " AND is_active = ?"
        count_params.append(is_active)
    
    total_result = await fetch_one(db, count_query, count_params)
    total = total_result["count"] if total_result else 0
    
    # Format QR codes
    formatted_codes = []
    for code in qr_codes:
        formatted_codes.append(QRCodeResponse(
            id=code["id"],
            code_hash=code["code_hash"],
            code_data=code["code_data"],
            code_type=code["code_type"],
            purpose=code["purpose"],
            title=code["title"],
            description=code["description"],
            is_active=code["is_active"],
            is_used=code["is_used"],
            use_count=code["use_count"],
            max_uses=code["max_uses"],
            expires_at=code["expires_at"],
            created_at=code["created_at"],
            qr_encode_data=code["code_data"],
        ))
    
    return QRCodeListResponse(
        qr_codes=formatted_codes,
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post("/{qr_code_id}/deactivate")
async def deactivate_qr(
    qr_code_id: int,
    license_key: dict = Depends(get_license_from_header),
    db: dict = Depends(get_db),
):
    """
    Deactivate a QR code
    
    Deactivated QR codes cannot be verified but are kept in the database.
    """
    success = await deactivate_qr_code(qr_code_id, license_key["id"])
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="QR code not found"
        )
    
    return {"message": "QR code deactivated successfully"}


@router.delete("/{qr_code_id}")
async def delete_qr(
    qr_code_id: int,
    license_key: dict = Depends(get_license_from_header),
    db: dict = Depends(get_db),
):
    """
    Delete a QR code (soft delete)
    
    Deleted QR codes are marked and hidden from normal queries.
    """
    success = await delete_qr_code(qr_code_id, license_key["id"])
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="QR code not found"
        )
    
    return {"message": "QR code deleted successfully"}


@router.get("/{qr_code_id}/analytics", response_model=QRAnalyticsResponse)
async def get_qr_analytics_endpoint(
    qr_code_id: int,
    days: int = Query(30, ge=1, le=365, description="Number of days to analyze"),
    license_key: dict = Depends(get_license_from_header),
    db: dict = Depends(get_db),
    request: Request = None,
):
    """
    Get analytics for a QR code

    - **days**: Number of days to analyze (1-365)

    Returns scan statistics and recent scan history.
    """
    # Rate limiting for analytics (expensive query)
    if request:
        rate_limit_key = get_rate_limit_key(request, license_key)
        if not _rate_limiter.is_allowed(rate_limit_key, max_requests=20, window_seconds=60):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Rate limit exceeded. Please try again later.",
            )

    analytics = await get_qr_analytics(
        qr_code_id=qr_code_id,
        license_key_id=license_key["id"],
        days=days,
    )

    return QRAnalyticsResponse(**analytics)


@router.get("/types")
async def get_qr_types():
    """Get available QR code types"""
    return {
        "types": [
            {"value": QRCodeType.LICENSE_KEY, "label": "License Key"},
            {"value": QRCodeType.SHARE_LINK, "label": "Share Link"},
            {"value": QRCodeType.CUSTOMER_CARD, "label": "Customer Card"},
            {"value": QRCodeType.CUSTOM, "label": "Custom"},
        ],
        "purposes": [
            {"value": QRCodePurpose.AUTHENTICATION, "label": "Authentication"},
            {"value": QRCodePurpose.SHARING, "label": "Sharing"},
            {"value": QRCodePurpose.PAYMENT, "label": "Payment"},
            {"value": QRCodePurpose.CONTACT, "label": "Contact"},
            {"value": QRCodePurpose.URL, "label": "URL"},
            {"value": QRCodePurpose.TEXT, "label": "Text"},
            {"value": QRCodePurpose.OTHER, "label": "Other"},
        ],
        "scan_results": [
            {"value": QRCodeScanResult.SUCCESS, "label": "Success"},
            {"value": QRCodeScanResult.FAILED, "label": "Failed"},
            {"value": QRCodeScanResult.EXPIRED, "label": "Expired"},
            {"value": QRCodeScanResult.INVALID, "label": "Invalid"},
            {"value": QRCodeScanResult.INACTIVE, "label": "Inactive"},
            {"value": QRCodeScanResult.MAX_USES_REACHED, "label": "Max Uses Reached"},
        ],
    }
