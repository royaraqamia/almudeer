from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import datetime, timezone
from constants.tasks import MAX_ALARMS_PER_TASK, ALARM_SNOOZE_MINUTES, MAX_SNOOZE_COUNT

class SubTask(BaseModel):
    id: str
    title: str
    is_completed: bool = False

class Attachment(BaseModel):
    url: str
    type: str = "file" # image, video, audio, file
    mime_type: Optional[str] = None
    file_name: Optional[str] = None
    file_size: Optional[int] = None

class TaskBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = Field(default=None, max_length=5000)
    is_completed: bool = False
    due_date: Optional[datetime] = None
    alarm_enabled: bool = False
    alarm_time: Optional[datetime] = None
    recurrence: Optional[str] = Field(default=None, description="daily, weekly, monthly")
    sub_tasks: Optional[List[SubTask]] = []
    category: Optional[str] = Field(default=None, max_length=100)
    color: Optional[int] = Field(default=None, description="Hex color as integer (e.g. 0xFF0000 for red)")
    order_index: float = 0.0
    created_by: Optional[str] = None
    assigned_to: Optional[str] = None
    attachments: Optional[List[Attachment]] = []
    visibility: str = "shared" # shared, private
    role: Optional[str] = None  # owner, assignee, viewer (computed, not stored)
    # FIX BUG-005: Priority field with proper validation
    priority: str = "medium"  # low, medium, high, urgent
    # Alarm snooze tracking
    snooze_count: int = Field(default=0, ge=0, le=MAX_SNOOZE_COUNT)

    @field_validator('recurrence')
    @classmethod
    def validate_recurrence(cls, v):
        if v is not None and v.lower() not in ('daily', 'weekly', 'monthly'):
            raise ValueError('recurrence must be daily, weekly, or monthly')
        return v

    @field_validator('visibility')
    @classmethod
    def validate_visibility(cls, v):
        if v not in ('shared', 'private'):
            raise ValueError('visibility must be shared or private')
        return v

    # FIX BUG-005: Validate priority field to accept only valid values
    @field_validator('priority')
    @classmethod
    def validate_priority(cls, v):
        if v not in ('low', 'medium', 'high', 'urgent'):
            raise ValueError('priority must be low, medium, high, or urgent')
        return v

    @field_validator('alarm_time')
    @classmethod
    def validate_alarm_time(cls, v):
        """Validate alarm time is not too far in the future (max 1 year) and normalize to UTC"""
        if v is not None:
            now = datetime.now(timezone.utc)
            max_alarm = now.replace(year=now.year + 1)
            # Normalize naive datetime to UTC (assume client sends UTC)
            if v.tzinfo is None:
                v = v.replace(tzinfo=timezone.utc)
            if v > max_alarm:
                raise ValueError('alarm_time cannot be more than 1 year in the future')
        return v

    @field_validator('due_date')
    @classmethod
    def validate_due_date(cls, v):
        """Normalize due_date to UTC if timezone-naive"""
        if v is not None and v.tzinfo is None:
            v = v.replace(tzinfo=timezone.utc)
        return v

class TaskCreate(TaskBase):
    id: str = Field(..., description="UUID from client")
    updated_at: Optional[datetime] = None

class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    is_completed: Optional[bool] = None
    due_date: Optional[datetime] = None
    alarm_enabled: Optional[bool] = None
    alarm_time: Optional[datetime] = None
    recurrence: Optional[str] = None
    sub_tasks: Optional[List[SubTask]] = None
    category: Optional[str] = None
    color: Optional[int] = None  # FIX: Add color field
    order_index: Optional[float] = None
    assigned_to: Optional[str] = None
    attachments: Optional[List[Attachment]] = None
    visibility: Optional[str] = None
    removed_attachments: Optional[List[str]] = None  # FIX: Add support for removing attachments
    priority: Optional[str] = None
    is_deleted: Optional[bool] = None
    snooze_count: Optional[int] = Field(default=None, ge=0, le=MAX_SNOOZE_COUNT)

    @field_validator('alarm_time')
    @classmethod
    def validate_alarm_time(cls, v):
        """Validate alarm time is not too far in the future (max 1 year) and normalize to UTC"""
        if v is not None:
            now = datetime.now(timezone.utc)
            max_alarm = now.replace(year=now.year + 1)
            # Normalize naive datetime to UTC (assume client sends UTC)
            if v.tzinfo is None:
                v = v.replace(tzinfo=timezone.utc)
            if v > max_alarm:
                raise ValueError('alarm_time cannot be more than 1 year in the future')
        return v

class TaskResponse(TaskBase):
    id: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True

class TaskCommentCreate(BaseModel):
    content: Optional[str] = Field(None)
    attachments: Optional[List[Attachment]] = []

class TaskCommentResponse(BaseModel):
    id: str
    task_id: str
    user_id: str
    user_name: Optional[str] = None
    content: str
    attachments: Optional[List[Attachment]] = []
    created_at: datetime

    class Config:
        from_attributes = True
