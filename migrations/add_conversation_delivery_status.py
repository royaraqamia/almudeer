"""
Add delivery_status column to inbox_conversations for Almudeer-to-Almudeer read receipts

Run: python -m migrations.add_conversation_delivery_status
"""

import asyncio
from db_helper import get_db, execute_sql, fetch_one, commit_db, DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)


async def add_delivery_status_column():
    """Add delivery_status column to inbox_conversations table."""
    try:
        async with get_db() as db:
            # Check if column already exists (different for SQLite vs PostgreSQL)
            if DB_TYPE == "postgresql":
                col_check = await fetch_one(
                    db,
                    """
                    SELECT column_name FROM information_schema.columns 
                    WHERE table_name = 'inbox_conversations' AND column_name = 'delivery_status'
                    """,
                    []
                )
            else:
                # SQLite: Use PRAGMA table_info
                cursor = await db.execute("PRAGMA table_info(inbox_conversations)")
                columns = await cursor.fetchall()
                col_check = any(col[1] == 'delivery_status' for col in columns)
            
            if col_check:
                logger.info("Column delivery_status already exists in inbox_conversations")
                return
            
            # Add the column
            await execute_sql(
                db,
                "ALTER TABLE inbox_conversations ADD COLUMN delivery_status TEXT DEFAULT 'pending'",
                []
            )
            await commit_db(db)
            
            logger.info("Added delivery_status column to inbox_conversations")
            
            # Backfill: Set delivery_status='sent' for existing conversations with status='sent'
            await execute_sql(
                db,
                """
                UPDATE inbox_conversations 
                SET delivery_status = 'sent' 
                WHERE status IN ('sent', 'approved', 'auto_replied')
                """,
                []
            )
            await commit_db(db)
            
            logger.info("Backfilled delivery_status for existing conversations")
            
    except Exception as e:
        logger.error(f"Failed to add delivery_status column: {e}")
        raise


if __name__ == "__main__":
    asyncio.run(add_delivery_status_column())
    print("[OK] Migration completed!")
