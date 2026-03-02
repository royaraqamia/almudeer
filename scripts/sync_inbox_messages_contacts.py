"""
Al-Mudeer - Inbox Messages Contact Sync Script
===============================================

This script synchronizes inbox_messages.sender_contact with current customer usernames.

Problem:
- When a license_key username changes, existing inbox_messages may still reference old usernames
- Mobile apps key conversations by sender_contact, so old messages appear under wrong conversations
- This breaks chat history continuity

Solution:
- Update inbox_messages.sender_contact to match current customer usernames
- This ensures all historical messages are grouped under the CURRENT username

Run with: python scripts/sync_inbox_messages_contacts.py
"""

import asyncio
import asyncpg
import sys
import os
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import database config
# IMPORTANT: Set DATABASE_URL environment variable before running
# Example (Windows): set DATABASE_URL=postgresql://user:pass@host:port/dbname
# Example (Linux/Mac): export DATABASE_URL=postgresql://user:pass@host:port/dbname
DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    print("ERROR: DATABASE_URL environment variable not set!")
    print("Please set it before running this script:")
    print("  Windows: set DATABASE_URL=postgresql://user:pass@host:port/dbname")
    print("  Linux/Mac: export DATABASE_URL=postgresql://user:pass@host:port/dbname")
    sys.exit(1)


async def find_mismatched_messages(conn):
    """
    Find inbox_messages where sender_contact doesn't match current customer username.
    """
    print("\nSearching for messages with mismatched sender_contact...")
    
    rows = await conn.fetch("""
        SELECT 
            m.id as message_id,
            m.license_key_id,
            m.sender_contact as current_contact,
            m.sender_id,
            c.contact as correct_contact,
            c.username as customer_username,
            lk.username as license_username
        FROM inbox_messages m
        INNER JOIN customers c ON m.license_key_id = c.license_key_id 
            AND (m.sender_contact = c.contact OR m.sender_contact = c.username)
        INNER JOIN license_keys lk ON c.license_key_id = lk.id
        WHERE lk.username IS NOT NULL
        AND m.sender_contact != lk.username
        AND m.sender_contact IS NOT NULL
        AND m.deleted_at IS NULL
        LIMIT 1000
    """)
    
    return rows


async def find_orphaned_messages(conn):
    """
    Find inbox_messages where sender_contact doesn't match any customer.
    """
    print("\nSearching for orphaned messages (no matching customer)...")
    
    rows = await conn.fetch("""
        SELECT 
            m.id as message_id,
            m.license_key_id,
            m.sender_contact,
            m.sender_id,
            m.created_at
        FROM inbox_messages m
        LEFT JOIN customers c ON m.license_key_id = c.license_key_id 
            AND (m.sender_contact = c.contact OR m.sender_contact = c.username)
        WHERE c.id IS NULL
        AND m.sender_contact IS NOT NULL
        AND m.sender_contact NOT LIKE '%@%'
        AND m.sender_contact NOT LIKE '+%'
        AND m.deleted_at IS NULL
        LIMIT 500
    """)
    
    return rows


async def update_message_sender_contact(conn, message_id: int, new_contact: str):
    """
    Update a single message's sender_contact.
    """
    try:
        await conn.execute("""
            UPDATE inbox_messages
            SET sender_contact = $1
            WHERE id = $2
        """, new_contact, message_id)
        return True
    except Exception as e:
        print(f"  Error updating message {message_id}: {e}")
        return False


async def update_messages_by_sender_id(conn, license_id: int, sender_id: str, new_contact: str):
    """
    Update all messages from a sender_id to use the correct contact.
    """
    try:
        result = await conn.execute("""
            UPDATE inbox_messages
            SET sender_contact = $1
            WHERE license_key_id = $2
            AND sender_id = $3
            AND sender_contact != $1
        """, new_contact, license_id, sender_id)
        
        count = int(result.split()[-1]) if result else 0
        return count
    except Exception as e:
        print(f"  Error updating messages for sender {sender_id}: {e}")
        return 0


async def main():
    """Main script execution."""
    if not DATABASE_URL:
        print("Error: DATABASE_URL not configured")
        print("Set DATABASE_URL environment variable or configure in config.py")
        sys.exit(1)
    
    print("=" * 70)
    print("Al-Mudeer - Inbox Messages Contact Sync")
    print("=" * 70)
    print(f"Database: {DATABASE_URL.split('@')[-1] if '@' in DATABASE_URL else 'configured'}")
    
    try:
        print("\nConnecting to database...")
        conn = await asyncpg.connect(DATABASE_URL)
        print("Connected successfully")
        
        # Part 1: Sync messages with mismatched contacts
        print("\n" + "=" * 70)
        print("Part 1: Syncing messages with mismatched sender_contact")
        print("=" * 70)
        
        mismatched = await find_mismatched_messages(conn)
        
        if not mismatched:
            print("[OK] No mismatched messages found")
        else:
            print(f"[WARN] Found {len(mismatched)} messages with mismatched sender_contact")
            print("\nPreview (first 20):")
            print(f"{'Message ID':<15} {'License':<20} {'Old Contact':<25} {'New Contact':<25}")
            print("-" * 85)
            
            updated_count = 0
            error_count = 0
            
            sender_groups = {}
            for row in mismatched:
                key = (row['license_key_id'], row['sender_id'])
                if key not in sender_groups:
                    sender_groups[key] = row['correct_contact'] or row['customer_username']
            
            for (license_id, sender_id), correct_contact in sender_groups.items():
                count = await update_messages_by_sender_id(conn, license_id, sender_id, correct_contact)
                updated_count += count
            
            print(f"\n[OK] Updated {updated_count} messages")
            if error_count > 0:
                print(f"[ERROR] Errors: {error_count}")
        
        # Part 2: Fix orphaned messages
        print("\n" + "=" * 70)
        print("Part 2: Fixing orphaned messages (no matching customer)")
        print("=" * 70)
        
        orphaned = await find_orphaned_messages(conn)
        
        if not orphaned:
            print("[OK] No orphaned messages found")
        else:
            print(f"[WARN] Found {len(orphaned)} orphaned messages")
            print("[INFO] These messages have sender_contact that doesn't match any customer")
            print("[INFO] Manual review recommended - skipping auto-update for safety")
            
            contact_counts = {}
            for row in orphaned:
                contact = row['sender_contact']
                contact_counts[contact] = contact_counts.get(contact, 0) + 1
            
            print("\nTop orphaned contacts:")
            for contact, count in sorted(contact_counts.items(), key=lambda x: -x[1])[:10]:
                print(f"  {contact}: {count} messages")
        
        print("\nCommitting changes to database...")
        await conn.close()
        print("[OK] Changes committed successfully")
        
        print("\n" + "=" * 70)
        print("Sync Complete!")
        print("=" * 70)
        print(f"Messages synced: {updated_count if mismatched else 0}")
        print(f"Orphaned messages (manual review): {len(orphaned) if orphaned else 0}")
        print(f"Errors: {error_count if mismatched and error_count > 0 else 0}")
        print("\nNext steps:")
        print("   1. Run sync_customer_usernames.py first if not already done")
        print("   2. Verify conversations in mobile app show correct history")
        print("   3. Review orphaned messages manually if any exist")
        
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
