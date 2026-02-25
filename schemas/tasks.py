from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import datetime

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
    order_index: float = 0.0
    created_by: Optional[str] = None
    assigned_to: Optional[str] = None
    attachments: Optional[List[Attachment]] = []
    visibility: str = "shared" # shared, private
    role: Optional[str] = None  # owner, assignee, viewer (computed, not stored)

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
    order_index: Optional[float] = None
    assigned_to: Optional[str] = None
    attachments: Optional[List[Attachment]] = None
    visibility: Optional[str] = None

class TaskResponse(TaskBase):
    id: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True

class TaskCommentCreate(BaseModel):
    content: str = Field(..., min_length=1)
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
