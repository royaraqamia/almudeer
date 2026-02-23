from pydantic import BaseModel, Field
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
    title: str = Field(..., min_length=1)
    description: Optional[str] = None
    is_completed: bool = False
    due_date: Optional[datetime] = None
    alarm_enabled: bool = False
    alarm_time: Optional[datetime] = None
    recurrence: Optional[str] = None
    sub_tasks: Optional[List[SubTask]] = []
    category: Optional[str] = None
    order_index: float = 0.0
    created_by: Optional[str] = None
    assigned_to: Optional[str] = None
    attachments: Optional[List[Attachment]] = []
    visibility: str = "shared" # shared, private

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
