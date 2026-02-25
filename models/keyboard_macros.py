"""
Al-Mudeer - Keyboard Macros Models
Support for cloud-synced keyboard macros/shortcuts
"""

import sqlite3
from typing import Optional, List, Dict, Any
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


def get_keyboard_macros(
    license_id: int,
    user_id: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """
    Get keyboard macros for a license (including global macros where license_key_id = 0)
    """
    from database import get_db_connection
    
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    try:
        query = """
            SELECT id, title, content, license_key_id, user_id, created_at, updated_at
            FROM keyboard_macros
            WHERE (license_key_id = ? OR license_key_id = 0)
              AND deleted_at IS NULL
            ORDER BY 
              CASE WHEN license_key_id = 0 THEN 1 ELSE 0 END,
              created_at DESC
            LIMIT ? OFFSET ?
        """
        
        cursor.execute(query, (license_id, limit, offset))
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    except Exception as e:
        logger.error(f"Error getting keyboard macros: {e}")
        return []
    finally:
        conn.close()


def get_keyboard_macro(license_id: int, macro_id: int, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Get a specific keyboard macro (including global macros)
    """
    from database import get_db_connection
    
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    try:
        query = """
            SELECT id, title, content, license_key_id, user_id, created_at, updated_at
            FROM keyboard_macros
            WHERE id = ? 
              AND (license_key_id = ? OR license_key_id = 0)
              AND deleted_at IS NULL
        """
        
        cursor.execute(query, (macro_id, license_id))
        row = cursor.fetchone()
        
        return dict(row) if row else None
    except Exception as e:
        logger.error(f"Error getting keyboard macro: {e}")
        return None
    finally:
        conn.close()


def create_keyboard_macro(
    license_id: int,
    title: str,
    content: str,
    user_id: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """
    Create a new keyboard macro
    """
    from database import get_db_connection
    
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    try:
        now = datetime.utcnow().isoformat()
        
        query = """
            INSERT INTO keyboard_macros (license_key_id, user_id, title, content, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        
        cursor.execute(query, (license_id, user_id, title, content, now, now))
        conn.commit()
        
        macro_id = cursor.lastrowid
        
        # Fetch the created macro
        return get_keyboard_macro(license_id, macro_id, user_id)
    except Exception as e:
        logger.error(f"Error creating keyboard macro: {e}")
        conn.rollback()
        return None
    finally:
        conn.close()


def update_keyboard_macro(
    license_id: int,
    macro_id: int,
    title: Optional[str] = None,
    content: Optional[str] = None,
    user_id: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """
    Update a keyboard macro
    """
    from database import get_db_connection
    
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    try:
        now = datetime.utcnow().isoformat()
        
        updates = []
        values = []
        
        if title is not None:
            updates.append("title = ?")
            values.append(title)
        if content is not None:
            updates.append("content = ?")
            values.append(content)
        
        if not updates:
            return get_keyboard_macro(license_id, macro_id, user_id)
        
        updates.append("updated_at = ?")
        values.append(now)
        values.append(macro_id)
        values.append(license_id)
        
        query = f"""
            UPDATE keyboard_macros
            SET {', '.join(updates)}
            WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL
        """
        
        cursor.execute(query, values)
        conn.commit()
        
        if cursor.rowcount == 0:
            return None
        
        return get_keyboard_macro(license_id, macro_id, user_id)
    except Exception as e:
        logger.error(f"Error updating keyboard macro: {e}")
        conn.rollback()
        return None
    finally:
        conn.close()


def delete_keyboard_macro(
    license_id: int,
    macro_id: int,
    user_id: Optional[str] = None,
) -> bool:
    """
    Soft delete a keyboard macro
    """
    from database import get_db_connection
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        now = datetime.utcnow().isoformat()
        
        query = """
            UPDATE keyboard_macros
            SET deleted_at = ?, updated_at = ?
            WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL
        """
        
        cursor.execute(query, (now, now, macro_id, license_id))
        conn.commit()
        
        return cursor.rowcount > 0
    except Exception as e:
        logger.error(f"Error deleting keyboard macro: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()


def bulk_delete_keyboard_macros(
    license_id: int,
    macro_ids: List[int],
    user_id: Optional[str] = None,
) -> int:
    """
    Bulk soft delete keyboard macros
    Returns the number of deleted macros
    """
    from database import get_db_connection
    
    if not macro_ids:
        return 0
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        now = datetime.utcnow().isoformat()
        
        placeholders = ','.join('?' * len(macro_ids))
        query = f"""
            UPDATE keyboard_macros
            SET deleted_at = ?, updated_at = ?
            WHERE id IN ({placeholders}) 
              AND license_key_id = ? 
              AND deleted_at IS NULL
        """
        
        values = [now, now] + macro_ids + [license_id]
        cursor.execute(query, values)
        conn.commit()
        
        return cursor.rowcount
    except Exception as e:
        logger.error(f"Error bulk deleting keyboard macros: {e}")
        conn.rollback()
        return 0
    finally:
        conn.close()
