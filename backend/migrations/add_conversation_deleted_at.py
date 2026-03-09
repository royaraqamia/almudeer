"""
Migration: Add deleted_at column to inbox_conversations table.

This allows soft-deleting conversations so that:
1. Deleted conversations can be synced to mobile apps via delta sync
2. Conversations can be permanently cleaned up after a retention period
"""
import logging
from db_helper import get_db, execute_sql, commit_db, DB_TYPE, fetch_all

logger = logging.getLogger(__name__)

async def migrate():
    """Add deleted_at column to inbox_conversations table."""
    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # Check if column already exists
                result = await db.fetchval("""
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name = 'inbox_conversations' 
                    AND column_name = 'deleted_at'
                """)
                
                if not result:
                    await execute_sql(db, """
                        ALTER TABLE inbox_conversations 
                        ADD COLUMN deleted_at TIMESTAMP
                    """)
                    await execute_sql(db, """
                        CREATE INDEX IF NOT EXISTS idx_conversations_deleted 
                        ON inbox_conversations(license_key_id, deleted_at)
                    """)
                    logger.info("Added deleted_at column to inbox_conversations (PostgreSQL)")
                else:
                    logger.info("deleted_at column already exists in inbox_conversations (PostgreSQL)")
                    
            else:
                # SQLite - check if column exists using pragma
                columns = await fetch_all(db, "PRAGMA table_info(inbox_conversations)")
                has_deleted_at = any(col['name'] == 'deleted_at' for col in columns)
                
                if not has_deleted_at:
                    await execute_sql(db, """
                        ALTER TABLE inbox_conversations 
                        ADD COLUMN deleted_at DATETIME
                    """)
                    await execute_sql(db, """
                        CREATE INDEX IF NOT EXISTS idx_conversations_deleted 
                        ON inbox_conversations(license_key_id, deleted_at)
                    """)
                    logger.info("Added deleted_at column to inbox_conversations (SQLite)")
                else:
                    logger.info("deleted_at column already exists in inbox_conversations (SQLite)")
            
            await commit_db(db)
            logger.info("Migration completed successfully")
            
        except Exception as e:
            logger.error(f"Migration failed: {e}")
            raise

if __name__ == "__main__":
    import asyncio
    asyncio.run(migrate())
