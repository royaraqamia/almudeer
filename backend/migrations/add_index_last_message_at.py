import logging
from db_helper import get_db, execute_sql, commit_db, DB_TYPE

logger = logging.getLogger(__name__)

async def migrate():
    """
    Add index on last_message_at in inbox_conversations table.
    """
    async with get_db() as db:
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at 
            ON inbox_conversations(license_key_id, last_message_at DESC)
        """)
        await commit_db(db)
        logger.info("Added index idx_conversations_last_message_at to inbox_conversations table")

if __name__ == "__main__":
    import asyncio
    asyncio.run(migrate())
