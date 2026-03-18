"""
Migration: Add unique index to browser_history table to prevent duplicate entries

This adds a unique index on (license_key_id, user_id, url, deleted_at) to prevent
race conditions when multiple concurrent requests try to insert the same URL.
"""

import asyncio
import sys
import os

# Add the backend directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from db_pool import db_pool, DB_TYPE
from models.browser import init_browser_tables


async def migrate():
    """Add unique index to browser_history table"""
    from db_helper import get_db, execute_sql
    
    print(f"Starting migration: Add unique index to browser_history (DB Type: {DB_TYPE})")
    
    async with get_db() as db:
        # Add unique index for browser_history
        # Note: We use deleted_at in the unique constraint to allow soft-delete recovery
        # Only one non-deleted entry per (license_key_id, user_id, url) is allowed
        if DB_TYPE == "postgresql":
            # PostgreSQL: Use partial unique index for soft-delete support
            await execute_sql(db, """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_browser_history_unique
                ON browser_history(license_key_id, user_id, url)
                WHERE deleted_at IS NULL
            """)
            print("Created unique partial index on browser_history for PostgreSQL")
        else:
            # SQLite: Create a unique index (SQLite supports partial indexes since 3.8.0)
            await execute_sql(db, """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_browser_history_unique
                ON browser_history(license_key_id, user_id, url)
                WHERE deleted_at IS NULL
            """)
            print("Created unique partial index on browser_history for SQLite")
    
    print("Migration completed successfully!")


async def main():
    """Main entry point"""
    await db_pool.initialize()
    try:
        await migrate()
    except Exception as e:
        print(f"Migration failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        await db_pool.close()


if __name__ == "__main__":
    asyncio.run(main())
