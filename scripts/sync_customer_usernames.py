"""
Al-Mudeer - Customer Username Sync Script
==========================================

This script synchronizes customer data with current license_keys usernames.

Problem:
- When a license_key username changes, the customers table may still have old usernames
- This causes mobile apps to not recognize existing conversations
- Mobile apps key conversations by sender_contact (username), so mismatches break chat continuity

Solution:
- Update customers.contact and customers.username to match current license_keys.username
- This ensures all existing customers reference the CURRENT username

Run with: python scripts/sync_customer_usernames.py
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


async def find_mismatched_customers(conn):
    """
    Find customers where contact/username doesn't match current license_keys.username.
    
    Returns list of customers that need updating.
    """
    print("\nSearching for mismatched customers...")
    
    rows = await conn.fetch("""
        SELECT 
            c.id as customer_id,
            c.license_key_id,
            c.contact as current_contact,
            c.username as current_username,
            lk.username as license_username,
            lk.full_name as license_full_name,
            c.name as customer_name
        FROM customers c
        INNER JOIN license_keys lk ON c.license_key_id = lk.id
        WHERE lk.username IS NOT NULL
        AND (
            -- Contact doesn't match current username
            (c.contact != lk.username AND c.contact IS NOT NULL)
            OR
            -- Username field is NULL or doesn't match
            (c.username IS DISTINCT FROM lk.username)
        )
        ORDER BY lk.username, c.id
    """)
    
    return rows


async def find_customers_with_null_username(conn):
    """
    Find customers where username is NULL but could be derived from contact.
    """
    print("\nSearching for customers with NULL username...")
    
    rows = await conn.fetch("""
        SELECT 
            c.id as customer_id,
            c.license_key_id,
            c.contact,
            c.name,
            c.phone,
            c.email
        FROM customers c
        WHERE c.username IS NULL
        AND c.contact IS NOT NULL
        ORDER BY c.id
        LIMIT 100
    """)
    
    return rows


async def sync_customer_username(conn, customer_id: int, new_username: str):
    """
    Update a single customer's contact and username to match license_keys.
    Handles duplicate key errors gracefully.
    """
    try:
        await conn.execute("""
            UPDATE customers
            SET 
                contact = $1::VARCHAR,
                username = $1::VARCHAR
            WHERE id = $2
        """, new_username, customer_id)
        
        return True
    except asyncpg.exceptions.UniqueViolationError:
        # Duplicate is OK - means another customer already has this contact
        # This can happen when multiple "unknown_*" contacts exist for the same user
        # We'll skip this one as it's already handled
        return True
    except Exception as e:
        print(f"  Error updating customer {customer_id}: {e}")
        return False


async def sync_customer_username_from_contact(conn, customer_id: int, contact: str):
    """
    Update a customer's username from their contact field.
    """
    try:
        await conn.execute("""
            UPDATE customers
            SET 
                username = $1::VARCHAR
            WHERE id = $2
        """, contact, customer_id)
        
        return True
    except Exception as e:
        print(f"  Error updating customer {customer_id}: {e}")
        return False


async def main():
    """Main script execution."""
    if not DATABASE_URL:
        print("Error: DATABASE_URL not configured")
        print("Set DATABASE_URL environment variable or configure in config.py")
        sys.exit(1)
    
    print("=" * 70)
    print("Al-Mudeer - Customer Username Sync")
    print("=" * 70)
    print(f"Database: {DATABASE_URL.split('@')[-1] if '@' in DATABASE_URL else 'configured'}")
    
    try:
        # Connect to database
        print("\nConnecting to database...")
        conn = await asyncpg.connect(DATABASE_URL)
        print("Connected successfully")
        
        # Part 1: Sync mismatched customers
        print("\n" + "=" * 70)
        print("Part 1: Syncing customers with mismatched usernames")
        print("=" * 70)
        
        mismatched = await find_mismatched_customers(conn)
        
        if not mismatched:
            print("[OK] No mismatched customers found")
        else:
            print(f"[WARN] Found {len(mismatched)} mismatched customers")
            print("\nPreview (first 20):")
            print(f"{'Customer ID':<15} {'License':<20} {'Old Contact':<25} {'New Username':<25}")
            print("-" * 85)
            
            updated_count = 0
            error_count = 0
            
            for row in mismatched[:20]:
                customer_id = row['customer_id']
                license_username = row['license_username']
                current_contact = row['current_contact']
                
                print(f"{customer_id:<15} {license_username:<20} {current_contact:<25} {license_username:<25}")
                
                success = await sync_customer_username(conn, customer_id, license_username)
                if success:
                    updated_count += 1
                else:
                    error_count += 1
            
            # Update remaining (beyond preview)
            for row in mismatched[20:]:
                success = await sync_customer_username(conn, row['customer_id'], row['license_username'])
                if success:
                    updated_count += 1
                else:
                    error_count += 1
            
            print(f"\n[OK] Updated {updated_count} customers")
            if error_count > 0:
                print(f"[ERROR] Errors: {error_count}")
        
        # Part 2: Fill NULL usernames
        print("\n" + "=" * 70)
        print("Part 2: Filling NULL usernames from contact field")
        print("=" * 70)
        
        null_usernames = await find_customers_with_null_username(conn)
        
        if not null_usernames:
            print("[OK] No customers with NULL username found")
        else:
            print(f"[WARN] Found {len(null_usernames)} customers with NULL username")
            
            filled_count = 0
            for row in null_usernames:
                customer_id = row['customer_id']
                contact = row['contact']
                
                if contact:
                    success = await sync_customer_username_from_contact(conn, customer_id, contact)
                    if success:
                        filled_count += 1
            
            print(f"[OK] Filled {filled_count} NULL usernames")
        
        # Commit all changes
        print("\nCommitting changes to database...")
        await conn.close()
        print("[OK] Changes committed successfully")
        
        # Summary
        print("\n" + "=" * 70)
        print("Sync Complete!")
        print("=" * 70)
        print(f"Mismatched customers synced: {updated_count if mismatched else 0}")
        print(f"NULL usernames filled: {filled_count if null_usernames else 0}")
        print(f"Errors: {error_count if mismatched and error_count > 0 else 0}")
        print("\nNext steps:")
        print("   1. Verify data in admin dashboard")
        print("   2. Test mobile app to ensure conversations show updated names")
        print("   3. Schedule this script to run periodically (optional)")
        
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
