"""
Al-Mudeer - Knowledge Base API Routes
Handling text and file uploads for RAG and LLM context
"""

import os
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query, Request
from pydantic import BaseModel

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user_optional
from models.knowledge import (
    get_knowledge_documents,
    add_knowledge_document,
    delete_knowledge_document
)
from services.file_storage_service import get_file_storage
from security import sanitize_string

router = APIRouter(prefix="/api/knowledge", tags=["Knowledge Base"])

# File storage service instance
file_storage = get_file_storage()

class DocumentMetadata(BaseModel):
    source: Optional[str] = 'manual'
    created_at: Optional[str] = None

class DocumentCreate(BaseModel):
    text: str
    metadata: Optional[DocumentMetadata] = None

@router.get("/documents")
async def list_documents(
    page: int = 1,
    page_size: int = 50,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """List knowledge documents for the current license to display in the mobile app."""
    user_id = user.get("user_id") if user else None
    offset = (page - 1) * page_size
    
    items = await get_knowledge_documents(
        license_id=license["license_id"],
        user_id=user_id,
        limit=page_size,
        offset=offset
    )
    
    # Format according to what the mobile app expects
    formatted_docs = []
    for item in items:
        # Reconstruct exactly what the app's `KnowledgeDocument.fromJson` needs
        formatted_docs.append({
            "id": str(item["id"]),
            "text": item["text"] or item["file_path"],
            "metadata": {
                "source": item["source"],
                "created_at": str(item["created_at"])
            }
        })
        
    return {
        "success": True,
        "documents": formatted_docs,
        "page": page,
        "page_size": page_size
    }

@router.post("/documents")
async def create_text_document(
    data: DocumentCreate,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Create a new text knowledge document."""
    user_id = user.get("user_id") if user else None
    source = data.metadata.source if data.metadata else 'manual'
    
    try:
        item = await add_knowledge_document(
            license_id=license["license_id"],
            user_id=user_id,
            source=source,
            text=sanitize_string(data.text, max_length=15000)
        )
        return {"success": True, "document": {
            "id": str(item["id"]),
            "text": item["text"],
            "metadata": {
                "source": item["source"],
                "created_at": str(item["created_at"])
            }
        }}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/upload")
async def upload_knowledge_file(
    file: UploadFile = File(...),
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Upload a file document to the knowledge base."""
    user_id = user.get("user_id") if user else None
    content_type = file.content_type or "application/octet-stream"
        
    try:
        content = await file.read()
        relative_path, public_url = file_storage.save_file(
            content=content,
            filename=file.filename,
            mime_type=content_type,
            subfolder="knowledge"
        )
        
        file_size = len(content)
        
        # Since it's a file, we can save its name/url in the 'text' column for mobile app compatibility
        # Or you can adapt the mobile app later, but currently it displays `doc.text`
        
        item = await add_knowledge_document(
            license_id=license["license_id"],
            user_id=user_id,
            source='file',
            text=f"ملف: {file.filename}",
            file_path=public_url,
            file_size=file_size,
            mime_type=content_type
        )
        
        return {"success": True, "document": {
            "id": str(item["id"]),
            "text": item["text"],
            "metadata": {
                "source": item["source"],
                "created_at": str(item["created_at"])
            }
        }}
    except ValueError as e:
        # DB level errors (e.g. limit reached)
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"حدث خطأ أثناء الرفع: {str(e)}")

@router.delete("/documents/{document_id}")
async def delete_document(
    document_id: int,
    license: dict = Depends(get_license_from_header),
    user: Optional[dict] = Depends(get_current_user_optional)
):
    """Delete a knowledge document."""
    user_id = user.get("user_id") if user else None
    success = await delete_knowledge_document(
        license_id=license["license_id"], 
        document_id=document_id, 
        user_id=user_id
    )
    if not success:
        raise HTTPException(status_code=404, detail="المستند غير موجود")
    return {"success": True}
