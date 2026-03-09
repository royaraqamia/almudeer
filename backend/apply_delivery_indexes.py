import sqlite3
import os
import asyncio
import asyncpg
from dotenv import load_dotenv

async def apply_pg_indexes():
    load_dotenv()
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("PostgreSQL DATABASE_URL not set, skipping...")
        return

    print("Connecting to PostgreSQL...")
    try:
        try:
            conn = await asyncpg.connect(db_url, ssl='require', timeout=10)
        except:
            conn = await asyncpg.connect(db_url, timeout=10)
            
        try:
            print("Applying indexes to PostgreSQL...")
            # Inbox Messages
            await conn.execute("CREATE INDEX IF NOT EXISTS idx_inbox_license_status ON inbox_messages(license_key_id, status)")
            await conn.execute("CREATE INDEX IF NOT EXISTS idx_inbox_license_contact ON inbox_messages(license_key_id, sender_contact)")
            
            # Outbox Messages
            await conn.execute("CREATE INDEX IF NOT EXISTS idx_outbox_license_status ON outbox_messages(license_key_id, status)")
            await conn.execute("CREATE INDEX IF NOT EXISTS idx_outbox_recipient_id ON outbox_messages(recipient_id)")
            await conn.execute("CREATE INDEX IF NOT EXISTS idx_outbox_recipient_email ON outbox_messages(recipient_email)")
            await conn.execute("CREATE INDEX IF NOT EXISTS idx_outbox_inbox_link ON outbox_messages(inbox_message_id)")
            print("SUCCESS: PostgreSQL indexes applied!")
        finally:
            await conn.close()
    except Exception as e:
        print(f"FAILED to apply PostgreSQL indexes: {e}")

def apply_sqlite_indexes():
    if not os.path.exists("almudeer.db"):
        print("SQLite almudeer.db not found, skipping...")
        return

    print("Applying indexes to SQLite (almudeer.db)...")
    try:
        conn = sqlite3.connect("almudeer.db")
        cursor = conn.cursor()
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_inbox_license_status ON inbox_messages(license_key_id, status)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_inbox_license_contact ON inbox_messages(license_key_id, sender_contact)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_outbox_license_status ON outbox_messages(license_key_id, status)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_outbox_recipient_id ON outbox_messages(recipient_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_outbox_recipient_email ON outbox_messages(recipient_email)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_outbox_inbox_link ON outbox_messages(inbox_message_id)")
        conn.commit()
        conn.close()
        print("SUCCESS: SQLite indexes applied!")
    except Exception as e:
        print(f"FAILED to apply SQLite indexes: {e}")

async def main():
    await apply_pg_indexes()
    apply_sqlite_indexes()

if __name__ == "__main__":
    asyncio.run(main())
