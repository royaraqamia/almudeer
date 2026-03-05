"""
Reset Almudeer delivery_status back to 'sent' for testing WhatsApp-like behavior.
"""
import asyncio
import sys
import os

os.environ['PYTHONIOENCODING'] = 'utf-8'
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ['DATABASE_URL'] = ''
os.environ['DB_TYPE'] = 'postgresql'

from db_helper import get_db, fetch_all, execute_sql
from database_unified import get_db_pool, close_db_pool


async def reset_delivery_status():
    print("=" * 80)
    print("Resetting Almudeer delivery_status to 'sent' for testing")
    print("=" * 80)

    pool = await get_db_pool()
    await pool.initialize()
    print("OK: Connected to PostgreSQL database")

    try:
        async with get_db() as db:
            # Reset all Almudeer messages to 'sent' status
            messages = await fetch_all(db, """
                SELECT id, delivery_status, status
                FROM outbox_messages
                WHERE channel = 'almudeer'
                AND delivery_status IN ('delivered', 'read')
                LIMIT 1000
            """)

            if not messages:
                print("OK: No messages to reset")
                return

            print("Found {} messages to reset".format(len(messages)))

            # Reset them to 'sent'
            updated_count = 0
            for msg in messages:
                try:
                    await execute_sql(
                        db,
                        "UPDATE outbox_messages SET delivery_status = 'sent' WHERE id = ?",
                        [msg['id']]
                    )
                    updated_count += 1
                except Exception as e:
                    print("ERROR updating message {}: {}".format(msg['id'], e))

            await execute_sql(db, "COMMIT")

            print("\nOK: Reset {} messages to 'sent' status".format(updated_count))
            print("\nNow when you test:")
            print("1. Send message from Account A to Account B")
            print("2. Account A sees: Single check (sent to server)")
            print("3. If Account B is online: Account A sees double gray checks immediately")
            print("4. If Account B is offline: Account A sees single check until Account B comes online")
            print("5. When Account B opens chat: Account A sees double blue checks")

    finally:
        await close_db_pool()
        print("\nOK: Database connection closed")


if __name__ == "__main__":
    asyncio.run(reset_delivery_status())
