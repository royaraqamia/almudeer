"""
Al-Mudeer - Integration Schemas
Shared Pydantic models for integration routes
"""

from pydantic import BaseModel, Field
from typing import Optional, List


class WorkerStatusResponse(BaseModel):
    telegram_polling: dict


class IntegrationAccount(BaseModel):
    id: str
    channel_type: str
    display_name: str
    is_active: bool
    details: Optional[str] = None


class InboxCustomerResponse(BaseModel):
    customer: Optional[dict]
