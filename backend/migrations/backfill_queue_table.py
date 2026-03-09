"""
Al-Mudeer - Backfill Queue Table Migration
Creates the backfill_queue table for gradual historical chat reveal
"""

from logging_config import get_logger

logger = get_logger(__name__)


async def create_backfill_queue_table():
    """
    Create the backfill_queue table for tracking historical messages
    that need to be gradually revealed in the inbox.
    
    This table queues messages from the past 30 days when a user
    first links a channel, then reveals them one-by-one every 10 minutes.
    """
    from db_helper import get_db, execute_sql, commit_db, DB_TYPE
    
    logger.info("Creating backfill_queue table...")
    
    async with get_db() as db:
        # Create backfill_queue table
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                CREATE TABLE IF NOT EXISTS backfill_queue (
                    id SERIAL PRIMARY KEY,
                    license_key_id INTEGER NOT NULL,
                    channel TEXT NOT NULL,
                    channel_message_id TEXT,
                    sender_contact TEXT,
                    sender_name TEXT,
                    sender_id TEXT,
                    subject TEXT,
                    body TEXT NOT NULL,
                    received_at TIMESTAMP,
                    scheduled_reveal_at TIMESTAMP NOT NULL,
                    status TEXT DEFAULT 'pending',
                    attachments TEXT,
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT NOW(),
                    revealed_at TIMESTAMP,
                    FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE
                )
            """)
        else:
            await execute_sql(db, """
                CREATE TABLE IF NOT EXISTS backfill_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    license_key_id INTEGER NOT NULL,
                    channel TEXT NOT NULL,
                    channel_message_id TEXT,
                    sender_contact TEXT,
                    sender_name TEXT,
                    sender_id TEXT,
                    subject TEXT,
                    body TEXT NOT NULL,
                    received_at TIMESTAMP,
                    scheduled_reveal_at TIMESTAMP NOT NULL,
                    status TEXT DEFAULT 'pending',
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    revealed_at TIMESTAMP,
                    FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE
                )
            """)
        
        # Create indexes for efficient queries
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_backfill_queue_license
            ON backfill_queue(license_key_id)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_backfill_queue_status
            ON backfill_queue(status, scheduled_reveal_at)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_backfill_queue_channel_msg
            ON backfill_queue(channel_message_id)
        """)
        
        await commit_db(db)
        logger.info("✅ Backfill queue table created!")
