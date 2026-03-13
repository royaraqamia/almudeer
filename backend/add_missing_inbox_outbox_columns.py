"""
Al-Mudeer - Add Missing Inbox/Outbox Columns

This script adds any missing columns to inbox_messages and outbox_messages tables.
Run this after verify_inbox_outbox_schema.py identifies missing columns.
"""

import asyncio
import os
from db_pool import db_pool, DB_TYPE
from db_helper import get_db, fetch_all, execute_sql, commit_db

async def add_column_if_missing(db, table_name, column_name, column_def):
    """Add a column to a table if it doesn't exist."""
    # Check if column exists
    if DB_TYPE == "postgresql":
        result = await fetch_all(
            db,
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_name = $1 AND column_name = $2
            """,
            [table_name, column_name]
        )
    else:
        result = await fetch_all(
            db,
            "PRAGMA table_info({table_name})".format(table_name=table_name)
        )
        result = [row for row in result if row.get("name") == column_name]
    
    if result:
        print(f"  ⏭️  {table_name}.{column_name} already exists")
        return False
    
    # Add column
    try:
        if DB_TYPE == "postgresql":
            await execute_sql(
                db,
                f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {column_def}",
                []
            )
        else:
            await execute_sql(
                db,
                f"ALTER TABLE {table_name} ADD COLUMN {column_def}",
                []
            )
        await commit_db(db)
        print(f"  ✅ Added {table_name}.{column_name}")
        return True
    except Exception as e:
        print(f"  ❌ Failed to add {table_name}.{column_name}: {e}")
        return False


async def main():
    """Add missing columns."""
    print("=" * 80)
    print("Al-Mudeer - Adding Missing Inbox/Outbox Columns")
    print("=" * 80)
    
    # Initialize database
    os.environ["DB_TYPE"] = "postgresql"
    await db_pool.initialize()
    
    try:
        added_count = 0
        
        async with get_db() as db:
            # inbox_messages missing columns
            print("\n📥 inbox_messages:")
            inbox_columns = [
                "direction TEXT DEFAULT 'incoming'",
                "delivery_status TEXT",
                "sent_at TIMESTAMP",
                "retry_count INTEGER DEFAULT 0",
                "max_retries INTEGER DEFAULT 3",
                "last_retry_at TIMESTAMP",
                "failed_at TIMESTAMP",
                "archived_at TIMESTAMP",
                "edit_count INTEGER DEFAULT 0",
                "sender_username TEXT",
                "voice_note_url TEXT",
                "voice_note_duration INTEGER",
                "is_voice_note BOOLEAN DEFAULT FALSE",
                "forwarded_from_license_id INTEGER",
            ]
            
            for col_def in inbox_columns:
                col_name = col_def.split()[0]
                if await add_column_if_missing(db, "inbox_messages", col_name, col_def):
                    added_count += 1
            
            # outbox_messages missing columns
            print("\n📤 outbox_messages:")
            outbox_columns = [
                "failure_reason TEXT",
                "channel_message_id TEXT",
                "max_retries INTEGER DEFAULT 3",
                "voice_note_url TEXT",
                "voice_note_duration INTEGER",
                "is_voice_note BOOLEAN DEFAULT FALSE",
            ]
            
            for col_def in outbox_columns:
                col_name = col_def.split()[0]
                if await add_column_if_missing(db, "outbox_messages", col_name, col_def):
                    added_count += 1
        
        print("\n" + "=" * 80)
        print(f"Summary: {added_count} column(s) added")
        print("=" * 80)
        
        if added_count == 0:
            print("\n✅ No missing columns to add!")
        else:
            print(f"\n✅ Added {added_count} missing column(s)")
    finally:
        await db_pool.close()


if __name__ == "__main__":
    asyncio.run(main())
