"""
Al-Mudeer - Library Schemas
Pydantic models for library API requests/responses
"""

from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import datetime


class ShareItemRequest(BaseModel):
    """Request to share a library item with another user"""
    shared_with_user_id: str = Field(..., description="Email or user ID of the recipient")
    permission: str = Field(default="read", description="Permission level: read, edit, admin")
    expires_in_days: Optional[int] = Field(None, description="Number of days until share expires")
    
    @validator('permission')
    def validate_permission(cls, v):
        if v not in ('read', 'edit', 'admin'):
            raise ValueError('Permission must be one of: read, edit, admin')
        return v
    
    @validator('expires_in_days')
    def validate_expires_in_days(cls, v):
        if v is not None and v <= 0:
            raise ValueError('expires_in_days must be a positive integer')
        return v


class ShareItemResponse(BaseModel):
    """Response after sharing a library item"""
    item_id: int
    shared_with: str
    permission: str
    expires_at: Optional[datetime]
    created_at: datetime
    created_by: str


class ShareInfo(BaseModel):
    """Information about a single share"""
    id: int
    item_id: int
    shared_with_user_id: str
    permission: str
    created_at: datetime
    created_by: Optional[str]
    expires_at: Optional[datetime]
    deleted_at: Optional[datetime]


class ListSharesResponse(BaseModel):
    """Response for listing shares of an item"""
    success: bool
    shares: List[ShareInfo]
    total: int


class SharedWithMeResponse(BaseModel):
    """Response for items shared with the current user"""
    success: bool
    items: List[dict]  # LibraryItem objects
    total: int


class RemoveShareResponse(BaseModel):
    """Response after removing a share"""
    success: bool
    message: str


class UpdateSharePermissionRequest(BaseModel):
    """Request to update share permission"""
    permission: str = Field(..., description="New permission level: read, edit, admin")
    
    @validator('permission')
    def validate_permission(cls, v):
        if v not in ('read', 'edit', 'admin'):
            raise ValueError('Permission must be one of: read, edit, admin')
        return v


class DevicePairRequest(BaseModel):
    """Request to pair with another device"""
    device_id: str = Field(..., description="Device ID to pair with")
    device_name: str = Field(..., description="Human-readable device name")
    pairing_code: Optional[str] = Field(None, description="Optional pairing code for verification")


class DevicePairResponse(BaseModel):
    """Response after device pairing"""
    success: bool
    pairing_id: int
    device_id: str
    device_name: str
    paired_at: datetime
    is_trusted: bool


class PairedDevice(BaseModel):
    """Information about a paired device"""
    pairing_id: int
    device_id: str
    device_name: str
    paired_at: datetime
    is_trusted: bool
    last_connected_at: Optional[datetime]


class ListPairedDevicesResponse(BaseModel):
    """Response for listing paired devices"""
    success: bool
    devices: List[PairedDevice]
    total: int


class UnpairDeviceResponse(BaseModel):
    """Response after unpairing a device"""
    success: bool
    message: str
