"""
Al-Mudeer - Add Keyboard Macros Table Migration
Adds cloud sync support for keyboard macros/shortcuts
"""

import sqlite3
from database import get_db_connection


def migrate():
    """Add keyboard_macros table for cloud-synced macros"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # Create keyboard_macros table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS keyboard_macros (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Create indexes for performance
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_macros_license 
            ON keyboard_macros(license_key_id)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_macros_deleted 
            ON keyboard_macros(deleted_at)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_macros_license_deleted 
            ON keyboard_macros(license_key_id, deleted_at)
        """)
        
        conn.commit()
        print("✓ Keyboard macros table created successfully")
        
    except Exception as e:
        print(f"✗ Error creating keyboard macros table: {e}")
        conn.rollback()
    finally:
        conn.close()


if __name__ == "__main__":
    migrate()
