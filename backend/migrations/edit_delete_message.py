"""
Al-Mudeer - Message Edit/Delete Migration
Adds columns for tracking message edits and soft deletes
"""

from logging_config import get_logger
from db_helper import get_db, execute_sql, commit_db, DB_TYPE

logger = get_logger(__name__)


async def ensure_message_edit_delete_schema():
    """
    Ensure the database has the required columns for message editing and deletion.
    
    Adds to outbox_messages:
    - edited_at: Timestamp when message was edited
    - original_body: Original message content before edit
    - deleted_at: Timestamp when message was soft-deleted
    - edit_count: Number of times message was edited
    
    This migration is idempotent and safe to run multiple times.
    """
    async with get_db() as db:
        # Add edited_at column
        try:
            if DB_TYPE == "postgresql":
                await execute_sql(db, """
                    ALTER TABLE outbox_messages 
                    ADD COLUMN IF NOT EXISTS edited_at TIMESTAMP
                """)
            else:
                await execute_sql(db, """
                    ALTER TABLE outbox_messages 
                    ADD COLUMN edited_at TEXT
                """)
            logger.info("Added edited_at column to outbox_messages")
        except Exception as e:
            if "duplicate column" not in str(e).lower() and "already exists" not in str(e).lower():
                logger.debug(f"edited_at column might already exist: {e}")
        
        # Add original_body column
        try:
            await execute_sql(db, """
                ALTER TABLE outbox_messages 
                ADD COLUMN original_body TEXT
            """)
            logger.info("Added original_body column to outbox_messages")
        except Exception as e:
            if "duplicate column" not in str(e).lower() and "already exists" not in str(e).lower():
                logger.debug(f"original_body column might already exist: {e}")
        
        # Add deleted_at column
        try:
            if DB_TYPE == "postgresql":
                await execute_sql(db, """
                    ALTER TABLE outbox_messages 
                    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP
                """)
            else:
                await execute_sql(db, """
                    ALTER TABLE outbox_messages 
                    ADD COLUMN deleted_at TEXT
                """)
            logger.info("Added deleted_at column to outbox_messages")
        except Exception as e:
            if "duplicate column" not in str(e).lower() and "already exists" not in str(e).lower():
                logger.debug(f"deleted_at column might already exist: {e}")
        
        # Add edit_count column
        try:
            if DB_TYPE == "postgresql":
                await execute_sql(db, """
                    ALTER TABLE outbox_messages 
                    ADD COLUMN IF NOT EXISTS edit_count INTEGER DEFAULT 0
                """)
            else:
                await execute_sql(db, """
                    ALTER TABLE outbox_messages 
                    ADD COLUMN edit_count INTEGER DEFAULT 0
                """)
            logger.info("Added edit_count column to outbox_messages")
        except Exception as e:
            if "duplicate column" not in str(e).lower() and "already exists" not in str(e).lower():
                logger.debug(f"edit_count column might already exist: {e}")
        
        await commit_db(db)
        logger.info("Message edit/delete schema migration complete")
