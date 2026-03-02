"""
Al-Mudeer - Complete Customer Data Sync Script
===============================================

This script syncs ALL existing customer data with current license_keys data.
It updates: name, username, and profile_image_url for Almudeer channel contacts ONLY.

Run with: 
  Windows: set DATABASE_URL=your_url && python scripts/sync_all_customer_data.py
  Linux/Mac: export DATABASE_URL=your_url && python scripts/sync_all_customer_data.py
"""

import asyncio
import asyncpg
import sys
import os
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

# Get database URL from environment
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

if not DATABASE_URL:
    print("ERROR: DATABASE_URL environment variable not set!")
    print("Please set it before running this script.")
    sys.exit(1)


async def get_all_license_keys(conn):
    """Get all current license keys with their data."""
    print("\nFetching all license keys...")
    
    rows = await conn.fetch("""
        SELECT 
            id,
            username,
            full_name,
            profile_image_url
        FROM license_keys
        WHERE username IS NOT NULL
        ORDER BY username
    """)
    
    return rows


async def find_customers_needing_update(conn):
    """
    Find ALL customers that need data sync with their license_keys.
    
    This finds customers where:
    - contact matches a license_keys.username (Almudeer channel users ONLY)
    - BUT name, username, or profile_image_url is out of sync
    """
    print("\nSearching for customers needing data update...")
    
    rows = await conn.fetch("""
        SELECT 
            c.id as customer_id,
            c.license_key_id,
            c.contact,
            c.name as current_name,
            c.username as current_username,
            c.profile_pic_url as current_image,
            lk.full_name as correct_name,
            lk.username as correct_username,
            lk.profile_image_url as correct_image
        FROM customers c
        INNER JOIN license_keys lk ON c.license_key_id = lk.id
        WHERE lk.username IS NOT NULL
        -- Match by contact OR username (Almudeer users only)
        AND (c.contact = lk.username OR c.username = lk.username)
        -- Exclude non-Almudeer contacts
        AND c.contact NOT LIKE '+%'
        AND c.contact NOT LIKE '%@%'
        AND c.contact NOT LIKE 'tg:%'
        AND c.contact NOT LIKE 'unknown_%'
        -- Find mismatches
        AND (
            (c.name IS DISTINCT FROM lk.full_name)
            OR (c.username IS DISTINCT FROM lk.username)
            OR (c.profile_pic_url IS DISTINCT FROM lk.profile_image_url)
        )
        ORDER BY lk.username, c.id
    """)
    
    return rows


async def update_customer_data(conn, customer_id: int, name: str, username: str, image_url: str):
    """Update a single customer's data."""
    try:
        await conn.execute("""
            UPDATE customers
            SET 
                name = $1::TEXT,
                username = $2::TEXT,
                profile_pic_url = $3::TEXT
            WHERE id = $4
        """, name, username, image_url, customer_id)
        
        return True
    except Exception as e:
        print(f"  Error updating customer {customer_id}: {e}")
        return False


async def find_conversations_needing_update(conn):
    """
    Find inbox_conversations that need sender_name/avatar update.
    """
    print("\nSearching for conversations needing update...")
    
    rows = await conn.fetch("""
        SELECT 
            ic.license_key_id,
            ic.sender_contact,
            ic.sender_name as current_name,
            ic.avatar_url as current_image,
            lk.full_name as correct_name,
            lk.profile_image_url as correct_image
        FROM inbox_conversations ic
        INNER JOIN license_keys lk ON ic.sender_contact = lk.username
        WHERE lk.username IS NOT NULL
        AND ic.sender_contact NOT LIKE '+%'
        AND ic.sender_contact NOT LIKE '%@%'
        AND ic.sender_contact NOT LIKE 'tg:%'
        AND ic.sender_contact NOT LIKE 'unknown_%'
        AND (
            (ic.sender_name IS DISTINCT FROM lk.full_name)
            OR (ic.avatar_url IS DISTINCT FROM lk.profile_image_url)
        )
        LIMIT 1000
    """)
    
    return rows


async def update_conversation_data(conn, license_id: int, sender_contact: str, name: str, image_url: str):
    """Update conversation cache data."""
    try:
        await conn.execute("""
            UPDATE inbox_conversations
            SET 
                sender_name = $1::TEXT,
                avatar_url = $2::TEXT
            WHERE license_key_id = $3 
            AND sender_contact = $4
        """, name, image_url, license_id, sender_contact)
        
        return True
    except Exception as e:
        print(f"  Error updating conversation for {sender_contact}: {e}")
        return False


async def main():
    """Main execution."""
    print("=" * 70)
    print("Al-Mudeer - Complete Customer Data Sync")
    print("=" * 70)
    print(f"Database: {DATABASE_URL.split('@')[-1]}")
    
    try:
        print("\nConnecting to database...")
        conn = await asyncpg.connect(DATABASE_URL)
        print("Connected successfully")
        
        # Part 1: Get all license keys
        print("\n" + "=" * 70)
        print("Part 1: Fetching current license keys data")
        print("=" * 70)
        
        licenses = await get_all_license_keys(conn)
        print(f"Found {len(licenses)} license keys with usernames")
        
        # Part 2: Update customers
        print("\n" + "=" * 70)
        print("Part 2: Syncing customer data")
        print("=" * 70)
        
        customers_to_update = await find_customers_needing_update(conn)
        
        if not customers_to_update:
            print("[OK] All customers are up to date")
        else:
            print(f"[INFO] Found {len(customers_to_update)} customers needing update")
            print("\nPreview (first 20):")
            print(f"{'ID':<10} {'Username':<25} {'Old Name':<30} {'New Name':<30}")
            print("-" * 95)
            
            updated_count = 0
            error_count = 0
            
            for row in customers_to_update[:20]:
                customer_id = row['customer_id']
                username = row['correct_username']
                current_name = row['current_name'] or '(null)'
                correct_name = row['correct_name'] or '(null)'
                
                print(f"Customer {customer_id}: {username} - Name updated")
                
                success = await update_customer_data(
                    conn, 
                    customer_id, 
                    row['correct_name'],
                    row['correct_username'],
                    row['correct_image']
                )
                
                if success:
                    updated_count += 1
                else:
                    error_count += 1
            
            # Update remaining
            for row in customers_to_update[20:]:
                success = await update_customer_data(
                    conn,
                    customer_id,
                    row['correct_name'],
                    row['correct_username'],
                    row['correct_image']
                )
                
                if success:
                    updated_count += 1
                else:
                    error_count += 1
            
            print(f"\n[OK] Updated {updated_count} customers")
            if error_count > 0:
                print(f"[ERROR] Errors: {error_count}")
        
        # Part 3: Update conversations
        print("\n" + "=" * 70)
        print("Part 3: Syncing conversation cache data")
        print("=" * 70)
        
        conversations_to_update = await find_conversations_needing_update(conn)
        
        if not conversations_to_update:
            print("[OK] All conversations are up to date")
        else:
            print(f"[INFO] Found {len(conversations_to_update)} conversations needing update")
            
            conv_updated_count = 0
            conv_error_count = 0
            
            for row in conversations_to_update:
                success = await update_conversation_data(
                    conn,
                    row['license_key_id'],
                    row['sender_contact'],
                    row['correct_name'],
                    row['correct_image']
                )
                
                if success:
                    conv_updated_count += 1
                else:
                    conv_error_count += 1
            
            print(f"[OK] Updated {conv_updated_count} conversations")
            if conv_error_count > 0:
                print(f"[ERROR] Errors: {conv_error_count}")
        
        # Commit
        print("\nCommitting changes...")
        await conn.close()
        print("[OK] Changes committed")
        
        # Summary
        print("\n" + "=" * 70)
        print("Sync Complete!")
        print("=" * 70)
        print(f"Customers updated: {updated_count if customers_to_update else 0}")
        print(f"Conversations updated: {conv_updated_count if conversations_to_update else 0}")
        print(f"Total errors: {error_count + conv_error_count}")
        
        print("\nNext steps:")
        print("1. Open mobile app and check if old conversations show updated names/images")
        print("2. If still showing old data, try pulling down to refresh")
        print("3. Run this script periodically to keep data in sync")
        
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
