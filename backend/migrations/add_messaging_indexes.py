import logging
from db_helper import get_db, execute_sql, commit_db, DB_TYPE

logger = logging.getLogger(__name__)

async def migrate():
    """
    Add performance-improving indexes for messaging tables.
    """
    async with get_db() as db:
        logger.info(f"Applying messaging indexes for {DB_TYPE}...")
        
        # 1. Inbox Messages Indexes
        # Efficient loading for specific conversation
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_inbox_messages_lookup 
            ON inbox_messages(license_key_id, sender_contact, status)
        """)
        
        # Efficient cursor-based pagination
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_inbox_messages_cursor 
                ON inbox_messages(license_key_id, COALESCE(received_at, created_at) DESC, id DESC)
            """)
        else:
            # SQLite doesn't support COALESCE in indexes easily
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_inbox_messages_received 
                ON inbox_messages(license_key_id, received_at DESC, id DESC)
            """)
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_inbox_messages_created 
                ON inbox_messages(license_key_id, created_at DESC, id DESC)
            """)

        # 2. Outbox Messages Indexes
        # Efficient loading for specific conversation
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_outbox_messages_lookup 
            ON outbox_messages(license_key_id, recipient_email, status)
        """)
        
        # Efficient cursor-based pagination
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_outbox_messages_cursor 
                ON outbox_messages(license_key_id, COALESCE(sent_at, created_at) DESC, id DESC)
            """)
        else:
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_outbox_messages_sent 
                ON outbox_messages(license_key_id, sent_at DESC, id DESC)
            """)
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_outbox_messages_created 
                ON outbox_messages(license_key_id, created_at DESC, id DESC)
            """)

        await commit_db(db)
        logger.info("Successfully added messaging indexes.")

if __name__ == "__main__":
    import asyncio
    asyncio.run(migrate())
