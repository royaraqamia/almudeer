"""
Al-Mudeer - Stories Models
DB table creation and CRUD for stories and views
"""

import os
import logging
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any

logger = logging.getLogger(__name__)

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from services.file_storage_service import get_file_storage

file_storage = get_file_storage()

# Story expiration (default 24 hours, but we keep them in DB and can filter by date)
STORY_EXPIRATION_HOURS = int(os.getenv("STORY_EXPIRATION_HOURS", 24))

async def init_stories_tables():
    """Create stories and story_views tables if they don't exist."""
    
    # helper for cross-DB compatibility
    ID_PK = "SERIAL PRIMARY KEY" if DB_TYPE == "postgresql" else "INTEGER PRIMARY KEY AUTOINCREMENT"
    TIMESTAMP_NOW = "TIMESTAMP DEFAULT NOW()" if DB_TYPE == "postgresql" else "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
    TEXT_TYPE = "TEXT"
    INT_TYPE = "INTEGER"

    async with get_db() as db:
        # 1. Stories Table
        await execute_sql(
            db,
            f"""
            CREATE TABLE IF NOT EXISTS stories (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                user_name TEXT, -- Added for display
                type TEXT NOT NULL, -- text, image, video, voice, audio, file
                title TEXT,
                content TEXT,
                media_path TEXT,
                thumbnail_path TEXT,
                duration_ms INTEGER DEFAULT 0,
                created_at {TIMESTAMP_NOW},
                expires_at {TIMESTAMP_NOW}, -- Added for custom duration
                updated_at {TIMESTAMP_NOW}, -- Added for tracking edits
                deleted_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
            """
        )

        # Migration: add user_name, expires_at, updated_at if they don't exist
        try:
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS user_name TEXT")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP")
            else:
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN user_name TEXT")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN expires_at TIMESTAMP")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN updated_at TIMESTAMP")
                except Exception: pass
        except Exception:
            pass
        
        # 2. Story Views Table (tracking who viewed what)
        await execute_sql(
            db,
            f"""
            CREATE TABLE IF NOT EXISTS story_views (
                id {ID_PK},
                story_id INTEGER NOT NULL,
                viewer_contact TEXT NOT NULL, -- phone number or contact unique ID
                viewer_name TEXT,
                viewed_at {TIMESTAMP_NOW},
                UNIQUE(story_id, viewer_contact),
                FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE
            )
            """
        )
        
        # 3. Create Indexes
        if DB_TYPE == "postgresql":
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_stories_license ON stories(license_key_id)")
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_stories_created ON stories(created_at)")
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_story_views_contact ON story_views(viewer_contact)")
        else:
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_stories_license ON stories(license_key_id)")
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_stories_created ON stories(created_at)")
        
        # 4. Highlights Table
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS story_highlights (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                title TEXT,
                cover_media_path TEXT,
                created_at {TIMESTAMP_NOW},
                deleted_at TIMESTAMP
            )
        """)
        
        # Add highlight_id and is_archived columns if they don't exist
        try:
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS highlight_id INTEGER")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE")
            else:
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN highlight_id INTEGER")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN is_archived BOOLEAN DEFAULT FALSE")
                except Exception: pass
        except Exception:
            pass
        
        await commit_db(db)

async def add_story(
    license_id: int,
    story_type: str,
    user_id: Optional[str] = None,
    user_name: Optional[str] = None,
    title: Optional[str] = None,
    content: Optional[str] = None,
    media_path: Optional[str] = None,
    thumbnail_path: Optional[str] = None,
    duration_ms: int = 0,
    duration_hours: int = 24
) -> dict:
    """Publish a new story and return the created object atomically."""
    now = datetime.utcnow()
    expires_at = now + timedelta(hours=duration_hours)
    
    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    ts_expires = expires_at if DB_TYPE == "postgresql" else expires_at.strftime('%Y-%m-%d %H:%M:%S')
    
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # Atomic return in PostgreSQL
            query = """
                INSERT INTO stories 
                (license_key_id, user_id, user_name, type, title, content, media_path, thumbnail_path, duration_ms, created_at, expires_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                RETURNING *
            """
            row = await fetch_one(db, query, [license_id, user_id, user_name, story_type, title, content, media_path, thumbnail_path, duration_ms, ts_now, ts_expires, ts_now])
            await commit_db(db)
            return dict(row) if row else {}
        else:
            # SQLite insertion
            await execute_sql(
                db,
                """
                INSERT INTO stories 
                (license_key_id, user_id, user_name, type, title, content, media_path, thumbnail_path, duration_ms, created_at, expires_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [license_id, user_id, user_name, story_type, title, content, media_path, thumbnail_path, duration_ms, ts_now, ts_expires, ts_now]
            )
            # Use last_insert_rowid() inside the same connection context
            row = await fetch_one(db, "SELECT * FROM stories WHERE id = last_insert_rowid()")
            await commit_db(db)
            return dict(row) if row else {}

async def update_story(
    story_id: int,
    license_id: int,
    user_id: str,
    title: Optional[str] = None,
    content: Optional[str] = None
) -> Optional[dict]:
    """Update story title and content. Returns the updated story or None if not found/unauthorized."""
    now = datetime.utcnow()
    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    
    async with get_db() as db:
        # Check ownership
        check_query = "SELECT id FROM stories WHERE id = ? AND license_key_id = ? AND user_id = ?"
        story = await fetch_one(db, check_query, [story_id, license_id, user_id])
        if not story:
            return None
            
        update_query = """
            UPDATE stories 
            SET title = ?, content = ?, updated_at = ?
            WHERE id = ?
        """
        await execute_sql(db, update_query, [title, content, ts_now, story_id])
        await commit_db(db)
        
        row = await fetch_one(db, "SELECT * FROM stories WHERE id = ?", [story_id])
        return dict(row) if row else None

async def get_active_stories(
    license_id: int, 
    viewer_contact: Optional[str] = None,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """
    Get active stories (last 24h) for a license with pagination.
    If viewer_contact is provided, includes 'is_viewed' join status.
    """
    if DB_TYPE == "postgresql":
        time_filter = "expires_at > NOW()"
    else:
        time_filter = "expires_at > datetime('now')"

    query = f"""
        SELECT s.*, 
               (CASE WHEN sv.id IS NOT NULL THEN 1 ELSE 0 END) as is_viewed
        FROM stories s
        LEFT JOIN story_views sv ON s.id = sv.story_id AND sv.viewer_contact = ?
        WHERE s.license_key_id = ? AND s.deleted_at IS NULL AND {time_filter}
        ORDER BY s.created_at DESC
        LIMIT ? OFFSET ?
    """
    
    async with get_db() as db:
        rows = await fetch_all(db, query, [viewer_contact, license_id, limit, offset])
        return [dict(row) for row in rows]

async def mark_story_viewed(story_id: int, viewer_contact: str, viewer_name: Optional[str] = None) -> bool:
    """Record that a contact viewed a story."""
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    
    # Use INSERT OR IGNORE / ON CONFLICT depending on DB
    if DB_TYPE == "postgresql":
        query = """
            INSERT INTO story_views (story_id, viewer_contact, viewer_name, viewed_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (story_id, viewer_contact) DO NOTHING
        """
    else:
        query = """
            INSERT OR IGNORE INTO story_views (story_id, viewer_contact, viewer_name, viewed_at)
            VALUES (?, ?, ?, ?)
        """

    async with get_db() as db:
        try:
            await execute_sql(db, query, [story_id, viewer_contact, viewer_name, ts_value])
            await commit_db(db)
            return True
        except Exception:
            return False

async def mark_stories_viewed_batch(story_ids: List[int], viewer_contact: str, viewer_name: Optional[str] = None, license_id: int = None) -> bool:
    """Record that a contact viewed multiple stories in a batch."""
    if not story_ids:
        return True
        
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    
    async with get_db() as db:
        try:
            # Verify all stories belong to this license and are active
            if license_id:
                if DB_TYPE == "postgresql":
                    time_filter = "expires_at > NOW()"
                else:
                    time_filter = "expires_at > datetime('now')"
                    
                placeholders = ','.join(['?' for _ in story_ids])
                verify_query = f"""
                    SELECT id FROM stories 
                    WHERE id IN ({placeholders}) 
                    AND license_key_id = ? 
                    AND deleted_at IS NULL 
                    AND {time_filter}
                """
                valid_stories = await fetch_all(db, verify_query, story_ids + [license_id])
                valid_ids = [row['id'] for row in valid_stories]
            else:
                valid_ids = story_ids
                
            if not valid_ids:
                return True
                
            # Batch insert views
            if DB_TYPE == "postgresql":
                for story_id in valid_ids:
                    query = """
                        INSERT INTO story_views (story_id, viewer_contact, viewer_name, viewed_at)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (story_id, viewer_contact) DO NOTHING
                    """
                    await execute_sql(db, query, [story_id, viewer_contact, viewer_name, ts_value])
            else:
                placeholders = ','.join(['(?, ?, ?, ?)' for _ in valid_ids])
                values = []
                for story_id in valid_ids:
                    values.extend([story_id, viewer_contact, viewer_name, ts_value])
                query = f"""
                    INSERT OR IGNORE INTO story_views (story_id, viewer_contact, viewer_name, viewed_at)
                    VALUES {placeholders}
                """
                await execute_sql(db, query, values)
                
            await commit_db(db)
            return True
        except Exception as e:
            logger.error(f"Error in batch mark stories viewed: {e}")
            return False

async def get_archived_stories(license_id: int, user_id: Optional[str] = None) -> List[dict]:
    """Retrieve expired or archived stories for the archive view."""
    if DB_TYPE == "postgresql":
        condition = "(expires_at <= NOW() OR is_archived = TRUE)"
    else:
        condition = "(expires_at <= datetime('now') OR is_archived = 1)"
        
    query = f"""
        SELECT * FROM stories 
        WHERE license_key_id = ? AND deleted_at IS NULL AND {condition}
    """
    params = [license_id]
    if user_id:
        query += " AND user_id = ?"
        params.append(user_id)
        
    query += " ORDER BY created_at DESC"
    
    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        return [dict(row) for row in rows]

async def create_highlight(license_id: int, user_id: str, title: str, cover_media_path: Optional[str] = None) -> dict:
    """Create a new story highlight group."""
    query = """
        INSERT INTO story_highlights (license_key_id, user_id, title, cover_media_path)
        VALUES (?, ?, ?, ?)
    """
    if DB_TYPE == "postgresql":
        query += " RETURNING *"
        async with get_db() as db:
            row = await fetch_one(db, query, [license_id, user_id, title, cover_media_path])
            await commit_db(db)
            return dict(row) if row else {}
    else:
        async with get_db() as db:
            await execute_sql(db, query, [license_id, user_id, title, cover_media_path])
            row = await fetch_one(db, "SELECT * FROM story_highlights WHERE id = last_insert_rowid()")
            await commit_db(db)
            return dict(row) if row else {}

async def get_highlights(license_id: int, user_id: Optional[str] = None) -> List[dict]:
    """List all highlights for a license/user."""
    query = "SELECT * FROM story_highlights WHERE license_key_id = ? AND deleted_at IS NULL"
    params = [license_id]
    if user_id:
        query += " AND user_id = ?"
        params.append(user_id)
        
    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        return [dict(row) for row in rows]

async def add_story_to_highlight(story_id: int, highlight_id: int) -> bool:
    """Assign a story to a highlight group."""
    query = "UPDATE stories SET highlight_id = ? WHERE id = ?"
    async with get_db() as db:
        try:
            await execute_sql(db, query, [highlight_id, story_id])
            await commit_db(db)
            return True
        except Exception:
            return False

async def get_story_viewers(story_id: int, license_id: int) -> List[dict]:
    """List details of who viewed a specific story."""
    query = """
        SELECT sv.viewer_contact, sv.viewer_name, sv.viewed_at, s.license_key_id
        FROM story_views sv
        JOIN stories s ON sv.story_id = s.id
        WHERE sv.story_id = ? AND s.license_key_id = ?
        ORDER BY sv.viewed_at DESC
    """
    async with get_db() as db:
        rows = await fetch_all(db, query, [story_id, license_id])
        return [dict(row) for row in rows]

async def get_story_view_count(story_id: int, license_id: int) -> int:
    """Get the view count for a specific story."""
    query = """
        SELECT COUNT(*) as count
        FROM story_views sv
        JOIN stories s ON sv.story_id = s.id
        WHERE sv.story_id = ? AND s.license_key_id = ?
    """
    async with get_db() as db:
        row = await fetch_one(db, query, [story_id, license_id])
        return row['count'] if row else 0

import asyncio

async def _delete_file_safely(file_path: str):
    """Utility to delete file from disk if it exists, using file_storage service."""
    if not file_path:
        return
        
    try:
        # Use common service for robust URL/Path -> Disk resolution
        await asyncio.to_thread(file_storage.delete_file, file_path)
    except Exception:
        pass # Best effort

async def delete_story(story_id: int, license_id: int, user_id: Optional[str] = None) -> bool:
    """Immediate deletion of a story and its media. Ensures only owner or admin can delete."""
    async with get_db() as db:
        query = "SELECT media_path, thumbnail_path FROM stories WHERE id = ? AND license_key_id = ?"
        params = [story_id, license_id]
        if user_id:
            query += " AND user_id = ?"
            params.append(user_id)
            
        story = await fetch_one(db, query, params)
        
        if story:
            await _delete_file_safely(story.get('media_path'))
            await _delete_file_safely(story.get('thumbnail_path'))
            
            # Now delete from DB
            delete_query = "DELETE FROM stories WHERE id = ? AND license_key_id = ?"
            delete_params = [story_id, license_id]
            if user_id:
                delete_query += " AND user_id = ?"
                delete_params.append(user_id)
            
            await execute_sql(db, delete_query, delete_params)
            await commit_db(db)
            return True
    return False

async def cleanup_expired_stories():
    """Permanent deletion of stories older than expiry hours or soft-deleted items, 
    EXCEPT if they are archived or in a highlight.
    """
    async with get_db() as db:
        # We only delete if it's NOT archived and NOT in a highlight
        if DB_TYPE == "postgresql":
            condition = "(expires_at < NOW() AND is_archived = FALSE AND highlight_id IS NULL) OR deleted_at IS NOT NULL"
        else:
            condition = "(expires_at < datetime('now') AND is_archived = 0 AND highlight_id IS NULL) OR deleted_at IS NOT NULL"
            
        select_query = f"SELECT media_path, thumbnail_path FROM stories WHERE {condition}"
        expired_stories = await fetch_all(db, select_query)
        
        # 2. Delete files from disk async
        for story in expired_stories:
            await _delete_file_safely(story.get('media_path'))
            await _delete_file_safely(story.get('thumbnail_path'))

        # 3. Delete from DB
        delete_query = f"DELETE FROM stories WHERE {condition}"
        await execute_sql(db, delete_query)
        await commit_db(db)
