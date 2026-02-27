from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime

class StoryBase(BaseModel):
    title: Optional[str] = None
    type: str # text, image, video, voice, audio, file

class StoryCreateText(StoryBase):
    content: str
    type: str = "text"
    duration_hours: int = 24
    visibility: str = "all"  # 'all', 'close_friends', 'custom'
    hide_from_contacts: Optional[List[str]] = []  # List of contact IDs to hide from

class StoryUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None

class StoryResponse(StoryBase):
    id: int
    user_id: Optional[str]
    content: Optional[str]
    media_path: Optional[str]
    thumbnail_path: Optional[str]
    duration_ms: int
    created_at: datetime
    expires_at: datetime
    updated_at: datetime
    is_viewed: bool = False
    # Repost fields
    is_repost: bool = False
    reposted_from_user_id: Optional[str] = None
    reposted_from_user_name: Optional[str] = None
    background_color: Optional[str] = None
    # Privacy fields
    visibility: str = "all"
    hide_from_contacts: Optional[List[str]] = None

    class Config:
        from_attributes = True

class StoryViewerDetails(BaseModel):
    viewer_contact: str
    viewer_name: Optional[str]
    viewed_at: datetime

class HighlightCreate(BaseModel):
    title: str
    cover_media_path: Optional[str] = None
    story_ids: List[int] = []

class HighlightResponse(BaseModel):
    id: int
    user_id: str
    title: str
    cover_media_path: Optional[str]
    created_at: datetime

class StoriesListResponse(BaseModel):
    success: bool
    stories: List[StoryResponse]

class BatchViewRequest(BaseModel):
    story_ids: List[int]
    viewer_contact: str
    viewer_name: Optional[str] = None

class BatchViewResponse(BaseModel):
    success: bool
    processed_count: int = 0
