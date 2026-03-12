"""
Backfill delivery_status for existing Almudeer channel messages.
Run this once to fix existing messages that were sent but don't have delivery_status set.
"""
import asyncio
import sys
import os

# Set console encoding to UTF-8 for Windows
os.environ['PYTHONIOENCODING'] = 'utf-8'
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

os.environ['DATABASE_URL'] = ''
os.environ['DB_TYPE'] = 'postgresql'

from db_helper import get_db, fetch_all, execute_sql
from database_unified import get_db_pool, close_db_pool


async def backfill_delivery_status():
    print("=" * 80)
    print("Backfilling delivery_status for Almudeer channel messages")
    print("=" * 80)

    pool = await get_db_pool()
    await pool.initialize()
    print("OK: Connected to PostgreSQL database")

    try:
        async with get_db() as db:
            # Find all Almudeer channel messages with status='sent' but NULL delivery_status
            messages = await fetch_all(db, """
                SELECT id, license_key_id, status, delivery_status, recipient_contact, created_at
                FROM outbox_messages
                WHERE channel = 'almudeer'
                AND status = 'sent'
                AND (delivery_status IS NULL OR delivery_status = 'pending')
                ORDER BY created_at ASC
                LIMIT 1000
            """)

            if not messages:
                print("OK: No messages need backfilling")
                return

            print("Found {} messages to backfill".format(len(messages)))

            # Update them to 'delivered'
            updated_count = 0
            for msg in messages:
                try:
                    await execute_sql(
                        db,
                        "UPDATE outbox_messages SET delivery_status = 'delivered' WHERE id = ?",
                        [msg['id']]
                    )
                    updated_count += 1
                except Exception as e:
                    print("ERROR updating message {}: {}".format(msg['id'], e))

            await execute_sql(db, "COMMIT")

            print("\nOK: Backfilled {} messages".format(updated_count))
            print("\nMessages now have delivery_status='delivered'")
            print("Mobile apps will show double gray checks (✓✓) for these messages")

    finally:
        await close_db_pool()
        print("\nOK: Database connection closed")


if __name__ == "__main__":
    asyncio.run(backfill_delivery_status())
