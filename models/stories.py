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

        # 5. Story Drafts Table (for saving drafts before publishing)
        await execute_sql(
            db,
            f"""
            CREATE TABLE IF NOT EXISTS story_drafts (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                type TEXT NOT NULL,
                title TEXT,
                content TEXT,
                media_path TEXT,
                thumbnail_path TEXT,
                visibility TEXT DEFAULT 'all',
                hide_from_contacts TEXT,
                duration_hours INTEGER DEFAULT 24,
                background_color TEXT,
                created_at {TIMESTAMP_NOW},
                updated_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
            """
        )
        
        # Create index for drafts lookup
        if DB_TYPE == "postgresql":
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_story_drafts_user ON story_drafts(license_key_id, user_id)")
        else:
            await execute_sql(db, "CREATE INDEX IF NOT EXISTS idx_story_drafts_user ON story_drafts(license_key_id, user_id)")

        # Add highlight_id and is_archived columns if they don't exist
        try:
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS highlight_id INTEGER")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE")
                # Repost functionality columns
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS is_repost BOOLEAN DEFAULT FALSE")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS reposted_from_user_id TEXT")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS reposted_from_user_name TEXT")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS background_color TEXT")
                # Privacy controls columns
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'all'")
                await execute_sql(db, "ALTER TABLE stories ADD COLUMN IF NOT EXISTS hide_from_contacts TEXT")
            else:
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN highlight_id INTEGER")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN is_archived BOOLEAN DEFAULT FALSE")
                except Exception: pass
                # Repost functionality columns
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN is_repost BOOLEAN DEFAULT FALSE")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN reposted_from_user_id TEXT")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN reposted_from_user_name TEXT")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN background_color TEXT")
                except Exception: pass
                # Privacy controls columns
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN visibility TEXT DEFAULT 'all'")
                except Exception: pass
                try: await execute_sql(db, "ALTER TABLE stories ADD COLUMN hide_from_contacts TEXT")
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
    duration_hours: int = 24,
    visibility: str = 'all',  # 'all', 'close_friends', 'custom'
    hide_from_contacts: Optional[List[str]] = None  # List of contact IDs to hide from
) -> dict:
    """Publish a new story and return the created object atomically."""
    now = datetime.utcnow()
    expires_at = now + timedelta(hours=duration_hours)

    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    ts_expires = expires_at if DB_TYPE == "postgresql" else expires_at.strftime('%Y-%m-%d %H:%M:%S')
    
    # Convert hide_from_contacts to JSON string for storage
    hide_from_json = None
    if hide_from_contacts:
        import json
        hide_from_json = json.dumps(hide_from_contacts)

    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # Atomic return in PostgreSQL
            query = """
                INSERT INTO stories
                (license_key_id, user_id, user_name, type, title, content, media_path, thumbnail_path, duration_ms, 
                 created_at, expires_at, updated_at, visibility, hide_from_contacts)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                RETURNING *
            """
            row = await fetch_one(db, query, [license_id, user_id, user_name, story_type, title, content, media_path, thumbnail_path, duration_ms, ts_now, ts_expires, ts_now, visibility, hide_from_json])
            await commit_db(db)
            return dict(row) if row else {}
        else:
            # SQLite insertion
            await execute_sql(
                db,
                """
                INSERT INTO stories
                (license_key_id, user_id, user_name, type, title, content, media_path, thumbnail_path, duration_ms, 
                 created_at, expires_at, updated_at, visibility, hide_from_contacts)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [license_id, user_id, user_name, story_type, title, content, media_path, thumbnail_path, duration_ms, ts_now, ts_expires, ts_now, visibility, hide_from_json]
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
    limit: int = 50,
    offset: int = 0,
    viewer_contact: Optional[str] = None
) -> List[dict]:
    """
    Get active stories (last 24h) for a license with pagination.
    If viewer_contact is provided, includes 'is_viewed' join status and filters by privacy.
    
    Privacy filtering:
    - visibility = 'all': Show to everyone
    - visibility = 'close_friends': Show only to close friends (treated as all for now)
    - visibility = 'custom': Show to everyone EXCEPT those in hide_from_contacts
    """
    if DB_TYPE == "postgresql":
        time_filter = "expires_at > NOW()"
    else:
        time_filter = "expires_at > datetime('now')"

    # Privacy filter - exclude stories hidden from this viewer
    privacy_filter = ""
    if viewer_contact:
        privacy_filter = """
            AND (
                s.visibility = 'all' 
                OR s.visibility = 'close_friends'
                OR (s.visibility = 'custom' AND (s.hide_from_contacts IS NULL OR s.hide_from_contacts NOT LIKE ?))
            )
        """
    
    query = f"""
        SELECT s.*,
               (CASE WHEN sv.id IS NOT NULL THEN 1 ELSE 0 END) as is_viewed
        FROM stories s
        LEFT JOIN story_views sv ON s.id = sv.story_id AND sv.viewer_contact = ?
        WHERE s.license_key_id = ? AND s.deleted_at IS NULL AND {time_filter}
        {privacy_filter}
        ORDER BY s.created_at DESC
        LIMIT ? OFFSET ?
    """

    async with get_db() as db:
        if viewer_contact:
            # Use LIKE with contact ID to check if viewer is in hide_from_contacts JSON array
            rows = await fetch_all(db, query, [viewer_contact, license_id, f'%"{viewer_contact}"%', limit, offset])
        else:
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


async def update_highlight(highlight_id: int, license_id: int, user_id: str, title: Optional[str] = None, cover_media_path: Optional[str] = None) -> Optional[dict]:
    """Update a highlight's title or cover image."""
    now = datetime.utcnow()
    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    
    async with get_db() as db:
        # Verify ownership
        check_query = "SELECT id FROM story_highlights WHERE id = ? AND license_key_id = ? AND user_id = ? AND deleted_at IS NULL"
        highlight = await fetch_one(db, check_query, [highlight_id, license_id, user_id])
        if not highlight:
            return None
        
        # Build update query
        updates = []
        params = []
        if title is not None:
            updates.append("title = ?")
            params.append(title)
        if cover_media_path is not None:
            updates.append("cover_media_path = ?")
            params.append(cover_media_path)
        
        if not updates:
            return None
        
        params.append(highlight_id)
        update_query = f"UPDATE story_highlights SET {', '.join(updates)} WHERE id = ?"
        await execute_sql(db, update_query, params)
        await commit_db(db)
        
        row = await fetch_one(db, "SELECT * FROM story_highlights WHERE id = ?", [highlight_id])
        return dict(row) if row else None


async def delete_highlight(highlight_id: int, license_id: int, user_id: str) -> bool:
    """Delete a highlight (soft delete). Stories remain but are unlinked."""
    now = datetime.utcnow()
    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    
    async with get_db() as db:
        # Verify ownership
        check_query = "SELECT id FROM story_highlights WHERE id = ? AND license_key_id = ? AND user_id = ? AND deleted_at IS NULL"
        highlight = await fetch_one(db, check_query, [highlight_id, license_id, user_id])
        if not highlight:
            return False
        
        # Unlink stories from this highlight
        await execute_sql(db, "UPDATE stories SET highlight_id = NULL WHERE highlight_id = ?", [highlight_id])
        
        # Soft delete the highlight
        if DB_TYPE == "postgresql":
            await execute_sql(db, "UPDATE story_highlights SET deleted_at = ? WHERE id = ?", [ts_now, highlight_id])
        else:
            await execute_sql(db, "UPDATE story_highlights SET deleted_at = ? WHERE id = ?", [ts_now, highlight_id])
        
        await commit_db(db)
        return True


async def remove_story_from_highlight(story_id: int, license_id: int, user_id: str) -> bool:
    """Remove a story from its highlight."""
    async with get_db() as db:
        # Verify story ownership
        check_query = "SELECT id FROM stories WHERE id = ? AND license_key_id = ? AND user_id = ?"
        story = await fetch_one(db, check_query, [story_id, license_id, user_id])
        if not story:
            return False
        
        await execute_sql(db, "UPDATE stories SET highlight_id = NULL WHERE id = ?", [story_id])
        await commit_db(db)
        return True


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

async def repost_story(
    story_id: int,
    license_id: int,
    user_id: str,
    user_name: str,
    duration_hours: int = 24
) -> Optional[dict]:
    """
    Repost an existing story to the current user's profile.
    Creates a new story with is_repost flag and references to original author.
    Returns the created story or None if source not found.
    """
    now = datetime.utcnow()
    expires_at = now + timedelta(hours=duration_hours)
    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    ts_expires = expires_at if DB_TYPE == "postgresql" else expires_at.strftime('%Y-%m-%d %H:%M:%S')

    async with get_db() as db:
        # Fetch the original story
        original = await fetch_one(
            db,
            "SELECT * FROM stories WHERE id = ? AND deleted_at IS NULL",
            [story_id]
        )
        
        if not original:
            return None
        
        # Verify story is not expired
        if DB_TYPE == "postgresql":
            is_active = "expires_at > NOW()"
        else:
            is_active = "expires_at > datetime('now')"
        
        active_check = await fetch_one(
            db,
            f"SELECT id FROM stories WHERE id = ? AND {is_active}",
            [story_id]
        )
        
        if not active_check:
            return None
        
        # Create repost with same media/content
        if DB_TYPE == "postgresql":
            query = """
                INSERT INTO stories
                (license_key_id, user_id, user_name, type, title, content, media_path, 
                 thumbnail_path, duration_ms, created_at, expires_at, updated_at,
                 is_repost, reposted_from_user_id, reposted_from_user_name, background_color)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                RETURNING *
            """
            row = await fetch_one(db, query, [
                license_id,
                user_id,
                user_name,
                original['type'],
                f"إعادة نشر من {original.get('user_name', 'مستخدم')}",
                original.get('content'),
                original.get('media_path'),
                original.get('thumbnail_path'),
                original.get('duration_ms', 0),
                ts_now,
                ts_expires,
                ts_now,
                True,  # is_repost
                original.get('user_id'),  # reposted_from_user_id
                original.get('user_name'),  # reposted_from_user_name
                original.get('background_color')
            ])
            await commit_db(db)
            return dict(row) if row else {}
        else:
            await execute_sql(
                db,
                """
                INSERT INTO stories
                (license_key_id, user_id, user_name, type, title, content, media_path,
                 thumbnail_path, duration_ms, created_at, expires_at, updated_at,
                 is_repost, reposted_from_user_id, reposted_from_user_name, background_color)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    license_id,
                    user_id,
                    user_name,
                    original['type'],
                    f"إعادة نشر من {original.get('user_name', 'مستخدم')}",
                    original.get('content'),
                    original.get('media_path'),
                    original.get('thumbnail_path'),
                    original.get('duration_ms', 0),
                    ts_now,
                    ts_expires,
                    ts_now,
                    True,  # is_repost
                    original.get('user_id'),  # reposted_from_user_id
                    original.get('user_name'),  # reposted_from_user_name
                    original.get('background_color')
                ]
            )
            row = await fetch_one(db, "SELECT * FROM stories WHERE id = last_insert_rowid()")
            await commit_db(db)
            return dict(row) if row else {}


async def get_story_analytics(
    license_id: int,
    user_id: Optional[str] = None,
    days: int = 7
) -> Dict[str, Any]:
    """
    Get comprehensive analytics for stories.
    
    Returns:
        - total_stories: Total stories posted
        - total_views: Total views across all stories
        - unique_viewers: Count of unique viewers
        - avg_views_per_story: Average views per story
        - top_stories: Top performing stories by views
        - views_by_day: Daily view counts
        - engagement_rate: Percentage of viewers who view multiple stories
    """
    async with get_db() as db:
        # Date filter
        if DB_TYPE == "postgresql":
            date_filter = f"created_at > NOW() - INTERVAL '{days} days'"
            view_date_filter = f"viewed_at > NOW() - INTERVAL '{days} days'"
        else:
            date_filter = f"created_at > datetime('now', '-{days} days')"
            view_date_filter = f"viewed_at > datetime('now', '-{days} days')"
        
        # Basic stats
        if user_id:
            user_filter = "AND user_id = ?"
            params = [license_id, user_id]
        else:
            user_filter = ""
            params = [license_id]
        
        # Total stories
        total_stories_query = f"""
            SELECT COUNT(*) as count FROM stories
            WHERE license_key_id = ? {user_filter} AND deleted_at IS NULL AND {date_filter}
        """
        total_stories_row = await fetch_one(db, total_stories_query, params)
        total_stories = total_stories_row['count'] if total_stories_row else 0
        
        # Total views
        total_views_query = f"""
            SELECT COUNT(*) as count FROM story_views sv
            JOIN stories s ON sv.story_id = s.id
            WHERE s.license_key_id = ? {user_filter} AND s.deleted_at IS NULL AND {view_date_filter}
        """
        total_views_row = await fetch_one(db, total_views_query, params)
        total_views = total_views_row['count'] if total_views_row else 0
        
        # Unique viewers
        unique_viewers_query = f"""
            SELECT COUNT(DISTINCT sv.viewer_contact) as count FROM story_views sv
            JOIN stories s ON sv.story_id = s.id
            WHERE s.license_key_id = ? {user_filter} AND s.deleted_at IS NULL AND {view_date_filter}
        """
        unique_viewers_row = await fetch_one(db, unique_viewers_query, params)
        unique_viewers = unique_viewers_row['count'] if unique_viewers_row else 0
        
        # Top stories by views
        top_stories_query = f"""
            SELECT s.id, s.title, s.type, s.user_name, s.created_at,
                   COUNT(sv.id) as view_count
            FROM stories s
            LEFT JOIN story_views sv ON s.id = sv.story_id
            WHERE s.license_key_id = ? {user_filter} AND s.deleted_at IS NULL AND {date_filter}
            GROUP BY s.id, s.title, s.type, s.user_name, s.created_at
            ORDER BY view_count DESC
            LIMIT 10
        """
        top_stories_rows = await fetch_all(db, top_stories_query, params)
        top_stories = [dict(row) for row in top_stories_rows]
        
        # Views by day
        if DB_TYPE == "postgresql":
            views_by_day_query = f"""
                SELECT DATE(sv.viewed_at) as date, COUNT(*) as views
                FROM story_views sv
                JOIN stories s ON sv.story_id = s.id
                WHERE s.license_key_id = ? {user_filter} AND s.deleted_at IS NULL AND {view_date_filter}
                GROUP BY DATE(sv.viewed_at)
                ORDER BY date DESC
            """
        else:
            views_by_day_query = f"""
                SELECT DATE(sv.viewed_at) as date, COUNT(*) as views
                FROM story_views sv
                JOIN stories s ON sv.story_id = s.id
                WHERE s.license_key_id = ? {user_filter} AND s.deleted_at IS NULL AND {view_date_filter}
                GROUP BY DATE(sv.viewed_at)
                ORDER BY date DESC
            """
        views_by_day_rows = await fetch_all(db, views_by_day_query, params)
        views_by_day = [dict(row) for row in views_by_day_rows]
        
        # Engagement rate (viewers who viewed more than 1 story)
        engagement_query = f"""
            SELECT COUNT(*) as engaged FROM (
                SELECT sv.viewer_contact, COUNT(DISTINCT sv.story_id) as story_count
                FROM story_views sv
                JOIN stories s ON sv.story_id = s.id
                WHERE s.license_key_id = ? {user_filter} AND s.deleted_at IS NULL AND {view_date_filter}
                GROUP BY sv.viewer_contact
                HAVING COUNT(DISTINCT sv.story_id) > 1
            )
        """
        engaged_row = await fetch_one(db, engagement_query, params)
        engaged_viewers = engaged_row['engaged'] if engaged_row else 0
        
        engagement_rate = 0.0
        if unique_viewers > 0:
            engagement_rate = round((engaged_viewers / unique_viewers) * 100, 2)
        
        avg_views = 0.0
        if total_stories > 0:
            avg_views = round(total_views / total_stories, 2)
        
        return {
            "total_stories": total_stories,
            "total_views": total_views,
            "unique_viewers": unique_viewers,
            "avg_views_per_story": avg_views,
            "engagement_rate": engagement_rate,
            "top_stories": top_stories,
            "views_by_day": views_by_day,
            "period_days": days
        }


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


# ============================================================================
# STORY DRAFTS FUNCTIONS
# ============================================================================

async def save_story_draft(
    license_id: int,
    user_id: str,
    story_type: str,
    title: Optional[str] = None,
    content: Optional[str] = None,
    media_path: Optional[str] = None,
    thumbnail_path: Optional[str] = None,
    visibility: str = 'all',
    hide_from_contacts: Optional[List[str]] = None,
    duration_hours: int = 24,
    background_color: Optional[str] = None
) -> dict:
    """Save or update a story draft."""
    now = datetime.utcnow()
    ts_now = now if DB_TYPE == "postgresql" else now.strftime('%Y-%m-%d %H:%M:%S')
    
    import json
    hide_from_json = json.dumps(hide_from_contacts) if hide_from_contacts else None
    
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            query = """
                INSERT INTO story_drafts
                (license_key_id, user_id, type, title, content, media_path, thumbnail_path,
                 visibility, hide_from_contacts, duration_hours, background_color, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (license_key_id, user_id) DO UPDATE SET
                    type = EXCLUDED.type,
                    title = EXCLUDED.title,
                    content = EXCLUDED.content,
                    media_path = EXCLUDED.media_path,
                    thumbnail_path = EXCLUDED.thumbnail_path,
                    visibility = EXCLUDED.visibility,
                    hide_from_contacts = EXCLUDED.hide_from_contacts,
                    duration_hours = EXCLUDED.duration_hours,
                    background_color = EXCLUDED.background_color,
                    updated_at = EXCLUDED.updated_at
                RETURNING *
            """
            # For PostgreSQL, we need a unique constraint first
            try:
                row = await fetch_one(db, query, [
                    license_id, user_id, story_type, title, content, media_path, thumbnail_path,
                    visibility, hide_from_json, duration_hours, background_color, ts_now, ts_now
                ])
                await commit_db(db)
                return dict(row) if row else {}
            except Exception:
                # If constraint doesn't exist, try regular insert
                pass
        
        # Fallback for SQLite or if PostgreSQL constraint missing
        # Check if draft exists
        existing = await fetch_one(db, "SELECT id FROM story_drafts WHERE license_key_id = ? AND user_id = ?", [license_id, user_id])
        
        if existing:
            # Update existing draft
            update_query = """
                UPDATE story_drafts SET
                    type = ?, title = ?, content = ?, media_path = ?, thumbnail_path = ?,
                    visibility = ?, hide_from_contacts = ?, duration_hours = ?,
                    background_color = ?, updated_at = ?
                WHERE license_key_id = ? AND user_id = ?
            """
            await execute_sql(db, update_query, [
                story_type, title, content, media_path, thumbnail_path,
                visibility, hide_from_json, duration_hours, background_color, ts_now,
                license_id, user_id
            ])
            row = await fetch_one(db, "SELECT * FROM story_drafts WHERE license_key_id = ? AND user_id = ?", [license_id, user_id])
            await commit_db(db)
            return dict(row) if row else {}
        else:
            # Insert new draft
            insert_query = """
                INSERT INTO story_drafts
                (license_key_id, user_id, type, title, content, media_path, thumbnail_path,
                 visibility, hide_from_contacts, duration_hours, background_color, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            await execute_sql(db, insert_query, [
                license_id, user_id, story_type, title, content, media_path, thumbnail_path,
                visibility, hide_from_json, duration_hours, background_color, ts_now, ts_now
            ])
            if DB_TYPE == "postgresql":
                row = await fetch_one(db, "SELECT * FROM story_drafts WHERE license_key_id = ? AND user_id = ?", [license_id, user_id])
            else:
                row = await fetch_one(db, "SELECT * FROM story_drafts WHERE license_key_id = ? AND user_id = ? ORDER BY id DESC LIMIT 1", [license_id, user_id])
            await commit_db(db)
            return dict(row) if row else {}


async def get_story_draft(license_id: int, user_id: str) -> Optional[dict]:
    """Get the current draft for a user."""
    async with get_db() as db:
        row = await fetch_one(db, "SELECT * FROM story_drafts WHERE license_key_id = ? AND user_id = ?", [license_id, user_id])
        return dict(row) if row else None


async def delete_story_draft(license_id: int, user_id: str) -> bool:
    """Delete a user's draft."""
    async with get_db() as db:
        await execute_sql(db, "DELETE FROM story_drafts WHERE license_key_id = ? AND user_id = ?", [license_id, user_id])
        await commit_db(db)
        return True


async def search_stories(
    license_id: int,
    user_id: Optional[str] = None,
    query: Optional[str] = None,
    story_type: Optional[str] = None,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """
    Search archived stories by content, type, and date range.
    """
    async with get_db() as db:
        # Build query dynamically based on filters
        conditions = ["license_key_id = ?"]
        params = [license_id]
        
        if user_id:
            conditions.append("user_id = ?")
            params.append(user_id)
        
        if query:
            conditions.append("(content LIKE ? OR title LIKE ?)")
            params.extend([f'%{query}%', f'%{query}%'])
        
        if story_type:
            conditions.append("type = ?")
            params.append(story_type)
        
        if date_from:
            ts_from = date_from if DB_TYPE == "postgresql" else date_from.strftime('%Y-%m-%d %H:%M:%S')
            conditions.append("created_at >= ?")
            params.append(ts_from)
        
        if date_to:
            ts_to = date_to if DB_TYPE == "postgresql" else date_to.strftime('%Y-%m-%d %H:%M:%S')
            conditions.append("created_at <= ?")
            params.append(ts_to)
        
        where_clause = " AND ".join(conditions)
        
        search_query = f"""
            SELECT * FROM stories
            WHERE {where_clause} AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        
        rows = await fetch_all(db, search_query, params)
        return [dict(row) for row in rows]


async def export_stories(
    license_id: int,
    user_id: Optional[str] = None,
    include_archived: bool = True,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None
) -> List[dict]:
    """
    Export stories for backup. Returns all stories with their metadata.
    """
    async with get_db() as db:
        conditions = ["license_key_id = ?", "deleted_at IS NULL"]
        params = [license_id]
        
        if user_id:
            conditions.append("user_id = ?")
            params.append(user_id)
        
        if not include_archived:
            if DB_TYPE == "postgresql":
                conditions.append("expires_at > NOW()")
            else:
                conditions.append("expires_at > datetime('now')")
        
        if date_from:
            ts_from = date_from if DB_TYPE == "postgresql" else date_from.strftime('%Y-%m-%d %H:%M:%S')
            conditions.append("created_at >= ?")
            params.append(ts_from)
        
        if date_to:
            ts_to = date_to if DB_TYPE == "postgresql" else date_to.strftime('%Y-%m-%d %H:%M:%S')
            conditions.append("created_at <= ?")
            params.append(ts_to)
        
        where_clause = " AND ".join(conditions)
        
        export_query = f"""
            SELECT * FROM stories
            WHERE {where_clause}
            ORDER BY created_at DESC
        """
        
        rows = await fetch_all(db, export_query, params)
        return [dict(row) for row in rows]
