"""
QR Code API Routes
Endpoints for QR code generation, verification, and management
"""

from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict, Any
from datetime import datetime, timezone

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
)
from auth import get_current_user, get_license_key
from database import get_db

router = APIRouter(prefix="/qr", tags=["QR Codes"])


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

    @validator('code_type')
    def validate_code_type(cls, v):
        valid_types = [QRCodeType.LICENSE_KEY, QRCodeType.SHARE_LINK, 
                      QRCodeType.CUSTOMER_CARD, QRCodeType.CUSTOM]
        if v not in valid_types:
            raise ValueError(f"Invalid code_type. Must be one of: {valid_types}")
        return v

    @validator('purpose')
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
    license_key: dict = Depends(get_license_key),
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
    db: dict = Depends(get_db),
):
    """
    Verify a QR code
    
    - **code_hash**: The hash of the QR code to verify
    - **device_info**: Optional device information for analytics
    
    Returns verification result and QR code details if valid.
    """
    # Get client IP and user agent
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    
    result = await verify_qr_code(
        code_hash=code_hash,
        scanned_data=None,
        device_info=device_info,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    
    return QRCodeVerifyResponse(**result)


@router.get("/{qr_code_id}", response_model=QRCodeResponse)
async def get_qr(
    qr_code_id: int,
    license_key: dict = Depends(get_license_key),
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
    license_key: dict = Depends(get_license_key),
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
    
    # Get total count
    total = len(qr_codes)  # In production, use COUNT query
    
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
    license_key: dict = Depends(get_license_key),
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
    license_key: dict = Depends(get_license_key),
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
    license_key: dict = Depends(get_license_key),
    db: dict = Depends(get_db),
):
    """
    Get analytics for a QR code
    
    - **days**: Number of days to analyze (1-365)
    
    Returns scan statistics and recent scan history.
    """
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
    }
