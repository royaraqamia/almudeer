"""
Al-Mudeer - Browser History and Bookmarks Models
Sync browser data across devices with end-to-end encryption support
"""

import logging
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
import json

from db_helper import (
    DB_TYPE,
    get_db,
    execute_sql,
    commit_db,
    fetch_all,
    fetch_one,
)
from db_pool import ID_PK, TIMESTAMP_NOW

# Import encryption utility
try:
    from utils.encryption import cookie_encryptor
except ImportError:
    cookie_encryptor = None

logger = logging.getLogger(__name__)


async def init_browser_tables():
    """Initialize browser history and bookmarks tables"""
    async with get_db() as db:
        # Browser History - Tracks user's browsing history
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS browser_history (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                url TEXT NOT NULL,
                title TEXT,
                visited_at TIMESTAMP NOT NULL,
                visit_count INTEGER DEFAULT 1,
                device_id TEXT,
                created_at {TIMESTAMP_NOW},
                updated_at {TIMESTAMP_NOW},
                deleted_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        # Indexes for browser history
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_history_license
            ON browser_history(license_key_id)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_history_user
            ON browser_history(user_id)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_history_visited
            ON browser_history(visited_at DESC)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_history_url
            ON browser_history(url)
        """)
        # Composite index for user's recent history
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_history_recent
            ON browser_history(license_key_id, user_id, visited_at DESC)
        """)
        # Index for soft-delete filtering
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_history_deleted
            ON browser_history(deleted_at)
        """)

        # Browser Bookmarks - User's saved bookmarks
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS browser_bookmarks (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                url TEXT NOT NULL,
                title TEXT NOT NULL,
                folder TEXT DEFAULT 'default',
                icon TEXT,
                created_at {TIMESTAMP_NOW},
                updated_at {TIMESTAMP_NOW},
                deleted_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
                UNIQUE(license_key_id, user_id, url)
            )
        """)

        # Indexes for browser bookmarks
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_license
            ON browser_bookmarks(license_key_id)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_user
            ON browser_bookmarks(user_id)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_folder
            ON browser_bookmarks(folder)
        """)
        # Composite index for user's bookmarks
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_user_folder
            ON browser_bookmarks(license_key_id, user_id, folder, created_at DESC)
        """)
        # Index for soft-delete filtering
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_deleted
            ON browser_bookmarks(deleted_at)
        """)

        # Browser Sync Metadata - Track last sync time per device/user
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS browser_sync_metadata (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                device_id TEXT,
                last_history_sync_at TIMESTAMP,
                last_bookmark_sync_at TIMESTAMP,
                updated_at {TIMESTAMP_NOW},
                UNIQUE(license_key_id, user_id, device_id),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_sync_license_user
            ON browser_sync_metadata(license_key_id, user_id)
        """)

        # Browser Cookies - Store encrypted cookies for cross-device sync
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS browser_cookies (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                device_id TEXT,
                name TEXT NOT NULL,
                value TEXT NOT NULL,
                domain TEXT NOT NULL,
                path TEXT DEFAULT '/',
                expires TIMESTAMP,
                is_secure BOOLEAN DEFAULT FALSE,
                is_http_only BOOLEAN DEFAULT FALSE,
                same_site TEXT DEFAULT 'Lax',
                created_at {TIMESTAMP_NOW},
                updated_at {TIMESTAMP_NOW},
                deleted_at TIMESTAMP,
                UNIQUE(license_key_id, user_id, domain, name),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_cookies_user_domain
            ON browser_cookies(license_key_id, user_id, domain)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_browser_cookies_deleted
            ON browser_cookies(deleted_at)
        """)

        await commit_db(db)
        print("Browser tables initialized")


# ============= Browser History Functions =============

async def add_history_entry(
    license_key_id: int,
    url: str,
    title: str,
    user_id: Optional[str] = None,
    device_id: Optional[str] = None,
    visited_at: Optional[datetime] = None,
) -> Dict[str, Any]:
    """Add or update a browser history entry"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)
        visited = visited_at or now

        # Check if entry exists for this URL and user
        existing = await fetch_one(db, """
            SELECT id, visit_count FROM browser_history
            WHERE license_key_id = ? AND user_id = ? AND url = ? AND deleted_at IS NULL
        """, (license_key_id, user_id, url))

        if existing:
            # Update existing entry - increment visit count and update timestamp
            await execute_sql(db, """
                UPDATE browser_history
                SET visited_at = ?, visit_count = visit_count + 1, updated_at = ?
                WHERE id = ?
            """, (visited, now, existing[0]))
            history_id = existing[0]
            visit_count = existing[1] + 1
        else:
            # Insert new entry
            await execute_sql(db, f"""
                INSERT INTO browser_history (license_key_id, user_id, url, title, visited_at, device_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (license_key_id, user_id, url, title, visited, device_id, now, now))
            
            # Get the inserted ID
            if DB_TYPE == "postgresql":
                result = await fetch_one(db, "SELECT LASTVAL()")
                history_id = result[0] if result else None
            else:
                result = await fetch_one(db, "SELECT last_insert_rowid()")
                history_id = result[0] if result else None
            visit_count = 1

        await commit_db(db)
        
        return {
            "id": history_id,
            "url": url,
            "title": title,
            "visited_at": visited.isoformat(),
            "visit_count": visit_count
        }


async def get_history(
    license_key_id: int,
    user_id: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    include_deleted: bool = False,
) -> List[Dict[str, Any]]:
    """Get browser history for a user"""
    async with get_db() as db:
        if include_deleted:
            rows = await fetch_all(db, """
                SELECT id, url, title, visited_at, visit_count, device_id, created_at
                FROM browser_history
                WHERE license_key_id = ? AND user_id = ?
                ORDER BY visited_at DESC
                LIMIT ? OFFSET ?
            """, (license_key_id, user_id, limit, offset))
        else:
            rows = await fetch_all(db, """
                SELECT id, url, title, visited_at, visit_count, device_id, created_at
                FROM browser_history
                WHERE license_key_id = ? AND user_id = ? AND deleted_at IS NULL
                ORDER BY visited_at DESC
                LIMIT ? OFFSET ?
            """, (license_key_id, user_id, limit, offset))

        return [
            {
                "id": row["id"],
                "url": row["url"],
                "title": row["title"],
                "visited_at": row["visited_at"],
                "visit_count": row["visit_count"],
                "device_id": row["device_id"],
                "created_at": row["created_at"]
            }
            for row in rows
        ]


async def delete_history_entry(
    license_key_id: int,
    history_id: int,
    user_id: Optional[str] = None,
    hard_delete: bool = False,
) -> bool:
    """Delete a browser history entry (soft delete by default)"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)
        
        if hard_delete:
            await execute_sql(db, """
                DELETE FROM browser_history
                WHERE id = ? AND license_key_id = ? AND user_id = ?
            """, (history_id, license_key_id, user_id))
        else:
            await execute_sql(db, """
                UPDATE browser_history
                SET deleted_at = ?, updated_at = ?
                WHERE id = ? AND license_key_id = ? AND user_id = ?
            """, (now, now, history_id, license_key_id, user_id))
        
        await commit_db(db)
        return True


async def clear_history(
    license_key_id: int,
    user_id: Optional[str] = None,
    hard_delete: bool = False,
) -> Dict[str, int]:
    """Clear all browser history for a user"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)
        
        if hard_delete:
            await execute_sql(db, """
                DELETE FROM browser_history
                WHERE license_key_id = ? AND user_id = ?
            """, (license_key_id, user_id))
        else:
            await execute_sql(db, """
                UPDATE browser_history
                SET deleted_at = ?, updated_at = ?
                WHERE license_key_id = ? AND user_id = ? AND deleted_at IS NULL
            """, (now, now, license_key_id, user_id))
        
        await commit_db(db)
        
        # Return count of affected rows
        return {"deleted": 0}  # SQLite doesn't return affected count easily


# ============= Browser Bookmarks Functions =============

async def add_bookmark(
    license_key_id: int,
    url: str,
    title: str,
    user_id: Optional[str] = None,
    folder: str = "default",
    icon: Optional[str] = None,
) -> Dict[str, Any]:
    """Add or update a bookmark"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)

        # Check if bookmark exists
        existing = await fetch_one(db, """
            SELECT id FROM browser_bookmarks
            WHERE license_key_id = ? AND user_id = ? AND url = ? AND deleted_at IS NULL
        """, (license_key_id, user_id, url))

        if existing:
            # Update existing bookmark
            await execute_sql(db, """
                UPDATE browser_bookmarks
                SET title = ?, folder = ?, icon = ?, updated_at = ?, deleted_at = NULL
                WHERE id = ?
            """, (title, folder, icon, now, existing[0]))
            bookmark_id = existing[0]
        else:
            # Check for soft-deleted bookmark and restore it
            soft_deleted = await fetch_one(db, """
                SELECT id FROM browser_bookmarks
                WHERE license_key_id = ? AND user_id = ? AND url = ? AND deleted_at IS NOT NULL
            """, (license_key_id, user_id, url))

            if soft_deleted:
                await execute_sql(db, """
                    UPDATE browser_bookmarks
                    SET title = ?, folder = ?, icon = ?, updated_at = ?, deleted_at = NULL
                    WHERE id = ?
                """, (title, folder, icon, now, soft_deleted[0]))
                bookmark_id = soft_deleted[0]
            else:
                # Insert new bookmark
                await execute_sql(db, f"""
                    INSERT INTO browser_bookmarks (license_key_id, user_id, url, title, folder, icon, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (license_key_id, user_id, url, title, folder, icon, now, now))
                
                # Get the inserted ID
                if DB_TYPE == "postgresql":
                    result = await fetch_one(db, "SELECT LASTVAL()")
                    bookmark_id = result[0] if result else None
                else:
                    result = await fetch_one(db, "SELECT last_insert_rowid()")
                    bookmark_id = result[0] if result else None

        await commit_db(db)
        
        return {
            "id": bookmark_id,
            "url": url,
            "title": title,
            "folder": folder,
            "icon": icon,
            "created_at": now.isoformat()
        }


async def get_bookmarks(
    license_key_id: int,
    user_id: Optional[str] = None,
    folder: Optional[str] = None,
    include_deleted: bool = False,
) -> List[Dict[str, Any]]:
    """Get bookmarks for a user"""
    async with get_db() as db:
        if folder:
            if include_deleted:
                rows = await fetch_all(db, """
                    SELECT id, url, title, folder, icon, created_at, updated_at
                    FROM browser_bookmarks
                    WHERE license_key_id = ? AND user_id = ? AND folder = ?
                    ORDER BY created_at DESC
                """, (license_key_id, user_id, folder))
            else:
                rows = await fetch_all(db, """
                    SELECT id, url, title, folder, icon, created_at, updated_at
                    FROM browser_bookmarks
                    WHERE license_key_id = ? AND user_id = ? AND folder = ? AND deleted_at IS NULL
                    ORDER BY created_at DESC
                """, (license_key_id, user_id, folder))
        else:
            if include_deleted:
                rows = await fetch_all(db, """
                    SELECT id, url, title, folder, icon, created_at, updated_at
                    FROM browser_bookmarks
                    WHERE license_key_id = ? AND user_id = ?
                    ORDER BY created_at DESC
                """, (license_key_id, user_id))
            else:
                rows = await fetch_all(db, """
                    SELECT id, url, title, folder, icon, created_at, updated_at
                    FROM browser_bookmarks
                    WHERE license_key_id = ? AND user_id = ? AND deleted_at IS NULL
                    ORDER BY created_at DESC
                """, (license_key_id, user_id))

        return [
            {
                "id": row["id"],
                "url": row["url"],
                "title": row["title"],
                "folder": row["folder"],
                "icon": row["icon"],
                "created_at": row["created_at"],
                "updated_at": row["updated_at"]
            }
            for row in rows
        ]


async def delete_bookmark(
    license_key_id: int,
    bookmark_id: int,
    user_id: Optional[str] = None,
    hard_delete: bool = False,
) -> bool:
    """Delete a bookmark (soft delete by default)"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)
        
        if hard_delete:
            await execute_sql(db, """
                DELETE FROM browser_bookmarks
                WHERE id = ? AND license_key_id = ? AND user_id = ?
            """, (bookmark_id, license_key_id, user_id))
        else:
            await execute_sql(db, """
                UPDATE browser_bookmarks
                SET deleted_at = ?, updated_at = ?
                WHERE id = ? AND license_key_id = ? AND user_id = ?
            """, (now, now, bookmark_id, license_key_id, user_id))
        
        await commit_db(db)
        return True


async def clear_bookmarks(
    license_key_id: int,
    user_id: Optional[str] = None,
    hard_delete: bool = False,
) -> Dict[str, int]:
    """Clear all bookmarks for a user"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)
        
        if hard_delete:
            await execute_sql(db, """
                DELETE FROM browser_bookmarks
                WHERE license_key_id = ? AND user_id = ?
            """, (license_key_id, user_id))
        else:
            await execute_sql(db, """
                UPDATE browser_bookmarks
                SET deleted_at = ?, updated_at = ?
                WHERE license_key_id = ? AND user_id = ? AND deleted_at IS NULL
            """, (now, now, license_key_id, user_id))
        
        await commit_db(db)
        
        return {"deleted": 0}


# ============= Sync Metadata Functions =============

async def update_sync_metadata(
    license_key_id: int,
    user_id: str,
    device_id: Optional[str] = None,
    last_history_sync_at: Optional[datetime] = None,
    last_bookmark_sync_at: Optional[datetime] = None,
) -> Dict[str, Any]:
    """Update sync metadata for a user/device"""
    async with get_db() as db:
        now = datetime.now(timezone.utc)

        # Check if metadata exists
        existing = await fetch_one(db, """
            SELECT id FROM browser_sync_metadata
            WHERE license_key_id = ? AND user_id = ? AND device_id IS NOT DISTINCT FROM ?
        """, (license_key_id, user_id, device_id))

        if existing:
            updates = []
            params = []
            if last_history_sync_at:
                updates.append("last_history_sync_at = ?")
                params.append(last_history_sync_at)
            if last_bookmark_sync_at:
                updates.append("last_bookmark_sync_at = ?")
                params.append(last_bookmark_sync_at)

            if updates:
                updates.append("updated_at = ?")
                params.append(now)
                params.extend([license_key_id, user_id, device_id])

                await execute_sql(db, f"""
                    UPDATE browser_sync_metadata
                    SET {', '.join(updates)}
                    WHERE license_key_id = ? AND user_id = ? AND device_id IS NOT DISTINCT FROM ?
                """, params)
        else:
            # Insert new metadata
            await execute_sql(db, f"""
                INSERT INTO browser_sync_metadata
                (license_key_id, user_id, device_id, last_history_sync_at, last_bookmark_sync_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                license_key_id,
                user_id,
                device_id,
                last_history_sync_at,
                last_bookmark_sync_at,
                now
            ))

        await commit_db(db)

        return {
            "license_key_id": license_key_id,
            "user_id": user_id,
            "device_id": device_id,
        }


async def get_sync_metadata(
    license_key_id: int,
    user_id: str,
    device_id: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """Get sync metadata for a user/device"""
    async with get_db() as db:
        row = await fetch_one(db, """
            SELECT last_history_sync_at, last_bookmark_sync_at, updated_at
            FROM browser_sync_metadata
            WHERE license_key_id = ? AND user_id = ? AND device_id IS NOT DISTINCT FROM ?
        """, (license_key_id, user_id, device_id))

        if row:
            return {
                "last_history_sync_at": row["last_history_sync_at"],
                "last_bookmark_sync_at": row["last_bookmark_sync_at"],
                "updated_at": row["updated_at"]
            }
        return None


# ============= Browser Cookie Functions =============

async def save_user_cookies(
    license_key_id: int,
    user_id: str,
    cookies: List[Dict[str, Any]],
    device_id: Optional[str] = None,
) -> int:
    """
    Save user cookies for cross-device sync.
    Returns the number of cookies saved.
    """
    if not cookies:
        return 0

    async with get_db() as db:
        now = datetime.now(timezone.utc)
        saved_count = 0

        for cookie in cookies:
            try:
                # Parse expires timestamp
                expires = None
                if cookie.get('expires'):
                    try:
                        expires = datetime.fromisoformat(
                            cookie['expires'].replace('Z', '+00:00')
                        )
                    except:
                        expires = None

                # Check if cookie exists
                existing = await fetch_one(db, """
                    SELECT id FROM browser_cookies
                    WHERE license_key_id = ? AND user_id = ? AND domain = ? AND name = ?
                """, (license_key_id, user_id, cookie['domain'], cookie['name']))

                if existing:
                    # Encrypt cookie value if encryption is enabled
                    cookie_value = cookie['value']
                    if cookie_encryptor and cookie_encryptor.is_enabled:
                        cookie_value = cookie_encryptor.encrypt(cookie['value'])
                    
                    # Update existing cookie
                    await execute_sql(db, """
                        UPDATE browser_cookies
                        SET value = ?, path = ?, expires = ?, is_secure = ?,
                            is_http_only = ?, same_site = ?, updated_at = ?,
                            deleted_at = NULL
                        WHERE id = ?
                    """, (
                        cookie_value,
                        cookie.get('path', '/'),
                        expires,
                        cookie.get('is_secure', False),
                        cookie.get('is_http_only', False),
                        cookie.get('same_site', 'Lax'),
                        now,
                        existing[0]
                    ))
                else:
                    # Encrypt cookie value if encryption is enabled
                    cookie_value = cookie['value']
                    if cookie_encryptor and cookie_encryptor.is_enabled:
                        cookie_value = cookie_encryptor.encrypt(cookie['value'])
                    
                    # Insert new cookie
                    await execute_sql(db, f"""
                        INSERT INTO browser_cookies
                        (license_key_id, user_id, device_id, name, value, domain, path,
                         expires, is_secure, is_http_only, same_site, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        license_key_id,
                        user_id,
                        device_id,
                        cookie['name'],
                        cookie_value,
                        cookie['domain'],
                        cookie.get('path', '/'),
                        expires,
                        cookie.get('is_secure', False),
                        cookie.get('is_http_only', False),
                        cookie.get('same_site', 'Lax'),
                        now,
                        now
                    ))

                saved_count += 1
            except Exception as e:
                logger.error(f"Error saving cookie {cookie.get('name')}: {e}")
                continue

        await commit_db(db)
        return saved_count


async def get_user_cookies(
    license_key_id: int,
    user_id: str,
    domain: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """
    Get user cookies for cross-device sync.
    Optionally filter by domain.
    Supports pagination for large cookie sets.
    """
    async with get_db() as db:
        if domain:
            rows = await fetch_all(db, """
                SELECT name, value, domain, path, expires, is_secure, is_http_only, same_site
                FROM browser_cookies
                WHERE license_key_id = ? AND user_id = ? AND domain = ?
                AND deleted_at IS NULL
                ORDER BY domain, name
                LIMIT ? OFFSET ?
            """, (license_key_id, user_id, domain, limit, offset))
        else:
            rows = await fetch_all(db, """
                SELECT name, value, domain, path, expires, is_secure, is_http_only, same_site
                FROM browser_cookies
                WHERE license_key_id = ? AND user_id = ?
                AND deleted_at IS NULL
                ORDER BY domain, name
                LIMIT ? OFFSET ?
            """, (license_key_id, user_id, limit, offset))

        cookies = []
        for row in rows:
            # Decrypt cookie value if encryption is enabled
            cookie_value = row["value"]
            if cookie_encryptor and cookie_encryptor.is_enabled:
                cookie_value = cookie_encryptor.decrypt(row["value"])

            cookie = {
                "name": row["name"],
                "value": cookie_value,
                "domain": row["domain"],
                "path": row["path"] or "/",
                "expires": row["expires"].isoformat() if row["expires"] else None,
                "is_secure": row["is_secure"] or False,
                "is_http_only": row["is_http_only"] or False,
                "same_site": row["same_site"] or "Lax",
            }

            # Filter out expired cookies
            if cookie["expires"]:
                try:
                    expiry = datetime.fromisoformat(cookie["expires"])
                    if expiry < datetime.now(timezone.utc):
                        continue
                except:
                    pass

            cookies.append(cookie)

        return cookies


async def clear_user_cookies(
    license_key_id: int,
    user_id: str,
) -> int:
    """
    Clear all user cookies (soft delete).
    Returns the number of cookies cleared.
    """
    async with get_db() as db:
        now = datetime.now(timezone.utc)

        # Get count of cookies to be deleted
        count_result = await fetch_one(db, """
            SELECT COUNT(*) FROM browser_cookies
            WHERE license_key_id = ? AND user_id = ? AND deleted_at IS NULL
        """, (license_key_id, user_id))

        count = count_result[0] if count_result else 0

        # Soft delete all cookies
        await execute_sql(db, """
            UPDATE browser_cookies
            SET deleted_at = ?, updated_at = ?
            WHERE license_key_id = ? AND user_id = ? AND deleted_at IS NULL
        """, (now, now, license_key_id, user_id))

        await commit_db(db)
        return count
