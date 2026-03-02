"""
Al-Mudeer - Add Avatar URL to Inbox Conversations
==================================================

This script adds the avatar_url column to inbox_conversations table
so that profile images can be displayed in the conversation list.

Run with:
  Windows: set DATABASE_URL=your_url && python scripts\add_avatar_to_conversations.py
  Linux/Mac: export DATABASE_URL=your_url && python scripts\add_avatar_to_conversations.py
"""

import asyncio
import asyncpg
import sys
import os
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

if not DATABASE_URL:
    print("ERROR: DATABASE_URL environment variable not set!")
    sys.exit(1)


async def main():
    """Add avatar_url column to inbox_conversations."""
    print("=" * 70)
    print("Al-Mudeer - Add Avatar URL to Conversations")
    print("=" * 70)
    
    try:
        print("\nConnecting to database...")
        conn = await asyncpg.connect(DATABASE_URL)
        print("Connected successfully")
        
        # Check if column already exists
        print("\nChecking if avatar_url column exists...")
        
        exists = await conn.fetchval("""
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'inbox_conversations' 
                AND column_name = 'avatar_url'
            )
        """)
        
        if exists:
            print("[OK] avatar_url column already exists")
        else:
            print("[INFO] Adding avatar_url column...")
            
            await conn.execute("""
                ALTER TABLE inbox_conversations 
                ADD COLUMN IF NOT EXISTS avatar_url TEXT
            """)
            
            print("[OK] avatar_url column added successfully")
        
        # Now populate avatar_url from license_keys.profile_image_url
        print("\nPopulating avatar_url from license keys...")
        
        result = await conn.execute("""
            UPDATE inbox_conversations ic
            SET avatar_url = lk.profile_image_url
            FROM license_keys lk
            WHERE ic.sender_contact = lk.username
            AND lk.profile_image_url IS NOT NULL
            AND ic.avatar_url IS DISTINCT FROM lk.profile_image_url
        """)
        
        # Parse count from result
        updated_count = int(result.split()[-1]) if result else 0
        
        print(f"[OK] Updated {updated_count} conversations with avatar URLs")
        
        await conn.close()
        
        print("\n" + "=" * 70)
        print("Migration Complete!")
        print("=" * 70)
        print(f"Conversations updated: {updated_count}")
        print("\nNext steps:")
        print("1. Run sync_all_customer_data.py to sync names and images")
        print("2. Open mobile app to verify profile images appear")
        
    except asyncpg.PostgresError as e:
        print(f"\nDatabase error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
