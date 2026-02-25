"""
Al-Mudeer - File Storage Service
Handles saving media files to the local filesystem and generating accessible URLs.

Fixes applied:
- Issue #28: Path traversal vulnerability prevention with secure_filename
"""

import os
import re
import uuid
import logging
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

# Base directory for uploads (configurable for persistence, e.g. Railway volume)
UPLOAD_DIR = os.getenv("UPLOAD_DIR", os.path.join(os.getcwd(), "static", "uploads"))

# Base URL prefix for accessing files
UPLOAD_URL_PREFIX = os.getenv("UPLOAD_URL_PREFIX", "/static/uploads")

# Issue #28: Secure filename pattern (alphanumeric, dash, underscore, dot)
SECURE_FILENAME_PATTERN = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$')


def secure_filename(filename: str) -> str:
    """
    Issue #28: Sanitize filename to prevent path traversal attacks.
    
    Removes path separators and dangerous characters.
    Returns a safe filename or generates a new one if completely unsafe.
    """
    if not filename:
        return uuid.uuid4().hex
    
    # Replace path separators with underscores
    filename = filename.replace('/', '_').replace('\\', '_')
    
    # Remove any leading/trailing dots and spaces (Windows issues)
    filename = filename.strip('. ')
    
    # Remove consecutive dots (Windows issues)
    while '..' in filename:
        filename = filename.replace('..', '.')
    
    # Check if filename matches secure pattern
    if not SECURE_FILENAME_PATTERN.match(filename):
        # Extract extension and sanitize base
        base, ext = os.path.splitext(filename)
        # Remove dangerous characters from base
        base = re.sub(r'[^\w\-_]', '', base)
        ext = re.sub(r'[^\w]', '', ext)
        filename = f"{base}{ext}"
    
    # If filename is empty after sanitization, generate UUID
    if not filename or filename in ['.', '..']:
        return uuid.uuid4().hex
    
    return filename


class FileStorageService:
    """Service for managing media file storage"""

    def __init__(self, upload_dir: str = UPLOAD_DIR):
        self.upload_dir = upload_dir
        self.url_prefix = UPLOAD_URL_PREFIX.rstrip("/")

        # Ensure upload directory exists
        if not os.path.exists(self.upload_dir):
            os.makedirs(self.upload_dir, exist_ok=True)
            logger.info(f"Created upload directory: {self.upload_dir}")

    def save_file(self, content: bytes, filename: str, mime_type: str, subfolder: str = None) -> Tuple[str, str]:
        """
        Save bytes to a file and return (relative_path, accessible_url)

        Args:
            content: Raw file bytes
            filename: Original filename
            mime_type: MIME type of the file
            subfolder: Optional subfolder (e.g. 'library', 'voice')

        Returns:
            Tuple of (relative_file_path, public_url)
        """
        try:
            # Determine subfolder if not provided
            if not subfolder:
                if mime_type.startswith("image/"):
                    subfolder = "images"
                elif mime_type.startswith("audio/"):
                    subfolder = "audio"
                elif mime_type.startswith("video/"):
                    subfolder = "video"
                else:
                    subfolder = "docs"

            # Create subfolder inside upload_dir
            target_dir = os.path.join(self.upload_dir, subfolder)
            os.makedirs(target_dir, exist_ok=True)

            # Issue #28: Sanitize filename to prevent path traversal
            safe_filename = secure_filename(filename)
            
            # Unique filename to avoid collisions
            unique_id = uuid.uuid4().hex
            ext = os.path.splitext(safe_filename)[1] or ".bin"
            unique_filename = f"{unique_id}{ext}"

            # Full path for saving
            file_path = os.path.join(target_dir, unique_filename)

            # Issue #28: Security check - ensure path is inside target_dir
            abs_file_path = os.path.abspath(file_path)
            abs_target_dir = os.path.abspath(target_dir)
            if not abs_file_path.startswith(abs_target_dir):
                logger.error(f"Security: Path traversal attempt detected: {file_path}")
                raise ValueError("Invalid file path")

            with open(file_path, "wb") as f:
                f.write(content)

            # Relative path for standard serving (forward slashes)
            relative_path = os.path.join(subfolder, unique_filename).replace("\\", "/")
            public_url = f"{self.url_prefix}/{relative_path}"

            logger.info(f"Saved file: {relative_path} (URL: {public_url})")
            return relative_path, public_url

        except Exception as e:
            logger.error(f"Failed to save file: {e}")
            raise

    async def save_upload_file_async(self, upload_file, filename: str, mime_type: str, subfolder: str = None) -> Tuple[str, str]:
        """
        Save an UploadFile to disk asynchronously in chunks to prevent OOM
        and return (relative_path, accessible_url)
        
        Issue #28: Sanitizes filename to prevent path traversal attacks.
        """
        try:
            if not subfolder:
                if mime_type.startswith("image/"):
                    subfolder = "images"
                elif mime_type.startswith("audio/"):
                    subfolder = "audio"
                elif mime_type.startswith("video/"):
                    subfolder = "video"
                else:
                    subfolder = "docs"

            target_dir = os.path.join(self.upload_dir, subfolder)
            os.makedirs(target_dir, exist_ok=True)

            # Issue #28: Sanitize filename
            safe_filename = secure_filename(filename)
            
            unique_id = uuid.uuid4().hex
            ext = os.path.splitext(safe_filename)[1] or ".bin"
            unique_filename = f"{unique_id}{ext}"

            file_path = os.path.join(target_dir, unique_filename)

            # Issue #28: Security check
            abs_file_path = os.path.abspath(file_path)
            abs_target_dir = os.path.abspath(target_dir)
            if not abs_file_path.startswith(abs_target_dir):
                logger.error(f"Security: Path traversal attempt detected: {file_path}")
                raise ValueError("Invalid file path")

            import aiofiles
            async with aiofiles.open(file_path, 'wb') as out_file:
                while content := await upload_file.read(1024 * 1024):  # 1MB chunks
                    await out_file.write(content)

            relative_path = os.path.join(subfolder, unique_filename).replace("\\", "/")
            public_url = f"{self.url_prefix}/{relative_path}"

            logger.info(f"Saved file async: {relative_path} (URL: {public_url})")
            return relative_path, public_url

        except Exception as e:
            logger.error(f"Failed to save file async: {e}")
            raise

    def delete_file(self, path_or_url: str) -> bool:
        """
        Delete a file from storage by its relative path or public URL.

        Args:
            path_or_url: Relative path (e.g. 'stories/file.pkg') or public URL

        Returns:
            bool: True if deleted successfully, False otherwise
        """
        if not path_or_url:
            return False

        try:
            relative_path = path_or_url

            # If it's a URL, extract the part after the prefix
            if "://" in path_or_url or path_or_url.startswith("/"):
                if self.url_prefix in path_or_url:
                    relative_path = path_or_url.split(self.url_prefix)[-1].lstrip("/")
                elif "/static/" in path_or_url: # Fallback for old style URLs
                    relative_path = path_or_url.split("/static/")[-1].lstrip("/")
                    # Handle if the prefix was /static/ instead of /static/uploads
                    if relative_path.startswith("uploads/"):
                        relative_path = relative_path.replace("uploads/", "", 1)

            # Issue #28: Sanitize relative path
            relative_path = secure_filename(relative_path)
            
            # Construct absolute path
            abs_path = os.path.join(self.upload_dir, relative_path)

            # Security check: ensure path is inside upload_dir
            abs_upload_dir = os.path.abspath(self.upload_dir)
            if not os.path.abspath(abs_path).startswith(abs_upload_dir):
                logger.warning(f"Security: Attempted to delete file outside upload directory: {abs_path}")
                return False

            if os.path.exists(abs_path):
                os.remove(abs_path)
                logger.info(f"Deleted file from storage: {abs_path}")
                return True

            return False
        except Exception as e:
            logger.error(f"Error deleting file {path_or_url}: {e}")
            return False

# Singleton instance
_instance = None

def get_file_storage() -> FileStorageService:
    global _instance
    if _instance is None:
        _instance = FileStorageService()
    return _instance
