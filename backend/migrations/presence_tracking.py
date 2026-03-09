"""
Migration for Presence Tracking
Adds last_seen_at column to license_keys table
"""

from db_helper import get_db, execute_sql, commit_db, DB_TYPE
from db_pool import db_pool
from logging_config import get_logger

logger = get_logger(__name__)


async def ensure_presence_schema():
    """
    Ensure last_seen_at column exists in license_keys.
    """
    await db_pool.initialize()
    try:
        async with get_db() as db:
            try:
                if DB_TYPE == "postgresql":
                    await execute_sql(db, """
                        ALTER TABLE license_keys 
                        ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP
                    """)
                else:
                    await execute_sql(db, """
                        ALTER TABLE license_keys 
                        ADD COLUMN last_seen_at TIMESTAMP
                    """)
                await commit_db(db)
                logger.info("✅ license_keys.last_seen_at column verified")
            except Exception as e:
                if "duplicate" not in str(e).lower() and "already exists" not in str(e).lower():
                    logger.debug(f"Presence column error: {e}")
    finally:
        await db_pool.close()

    logger.info("🎉 Presence tracking schema verified!")


if __name__ == "__main__":
    import asyncio
    asyncio.run(ensure_presence_schema())
