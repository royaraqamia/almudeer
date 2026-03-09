import asyncio
import os
import sys

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

from migrations.manager import migration_manager
from migrations.inbox_conversations_table import migrate as migrate_inbox_conversations


async def run_migration_004_postgresql():
    """Run migration 004 for PostgreSQL (remove device_secret_hash column)"""
    import asyncpg
    
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        print("[SKIP] DATABASE_URL not set, skipping PostgreSQL migration 004")
        return
    
    print("Running migration 004 (PostgreSQL)...")
    try:
        conn = await asyncpg.connect(database_url, ssl='require')
        
        # Check if column exists
        column_check = await conn.fetchval('''
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'device_sessions' 
                AND column_name = 'device_secret_hash'
            )
        ''')
        
        if column_check:
            await conn.execute('ALTER TABLE device_sessions DROP COLUMN IF EXISTS device_secret_hash')
            print("[OK] Migration 004: Dropped device_secret_hash column (PostgreSQL)")
        else:
            print("[OK] Migration 004: Column already removed (PostgreSQL)")
        
        await conn.close()
    except Exception as e:
        print(f"[WARN] Migration 004 failed (PostgreSQL): {e}")


async def main():
    print("Running migrations...")

    # Run standard SQL migrations
    await migration_manager.migrate()

    # Run migration 004 for PostgreSQL
    db_type = os.getenv('DB_TYPE', 'sqlite').lower()
    if db_type == 'postgresql':
        await run_migration_004_postgresql()

    # Run Python-based migrations
    print("Running inbox_conversations migration...")
    try:
        await migrate_inbox_conversations()
        print("[OK] Inbox conversations migration complete.")
    except Exception as e:
        print(f"[WARN] Inbox conversations migration failed: {e}")

    print("All migrations complete.")

if __name__ == "__main__":
    asyncio.run(main())
