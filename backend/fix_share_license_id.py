"""
Fix existing shares that have incorrect license_key_id

BUG: Shares were saved with the sharer's license_key_id instead of the recipient's.
This script migrates existing shares to use the recipient's license_id.

Run this script once to fix all existing shares in the database.
"""

import asyncio
import sys
import os

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Set required environment variables
os.environ["DB_TYPE"] = os.environ.get("DB_TYPE", "postgresql")
os.environ["ENCRYPTION_KEY"] = os.environ.get("ENCRYPTION_KEY", "test-encryption-key-32-chars-min")
os.environ["JWT_SECRET_KEY"] = os.environ.get("JWT_SECRET_KEY", "test-jwt-secret-key-at-least-32-chars")

from db_helper import get_db, fetch_all, execute_sql, commit_db
from db_pool import db_pool


async def fix_task_shares():
    """Fix task_shares table - update license_key_id to recipient's license_id"""
    print("=" * 60)
    print("FIXING TASK_SHARES TABLE")
    print("=" * 60)
    
    async with get_db() as db:
        # Get all shares where license_key_id doesn't match shared_with_user_id
        # shared_with_user_id IS the recipient's license_id (as string)
        rows = await fetch_all(
            db,
            """
            SELECT id, task_id, license_key_id, shared_with_user_id
            FROM task_shares
            WHERE deleted_at IS NULL
            AND shared_with_user_id IS NOT NULL
            AND shared_with_user_id != ''
            """
        )
        
        if not rows:
            print("No task shares found to fix")
            return 0
        
        fixed_count = 0
        skip_count = 0
        error_count = 0
        
        for row in rows:
            share_id = row['id']
            current_license_id = row['license_key_id']
            recipient_user_id = row['shared_with_user_id']
            
            try:
                # recipient_user_id is already the license_id as string
                recipient_license_id = int(recipient_user_id)
                
                # Only update if different
                if current_license_id != recipient_license_id:
                    await execute_sql(
                        db,
                        """
                        UPDATE task_shares
                        SET license_key_id = ?
                        WHERE id = ?
                        """,
                        [recipient_license_id, share_id]
                    )
                    print(f"  Fixed task_share id={share_id}: "
                          f"license_key_id {current_license_id} -> {recipient_license_id}")
                    fixed_count += 1
                else:
                    skip_count += 1
            except (ValueError, TypeError) as e:
                print(f"  ERROR: Invalid recipient_user_id '{recipient_user_id}' for share id={share_id}: {e}")
                error_count += 1
            except Exception as e:
                print(f"  ERROR: Failed to update share id={share_id}: {e}")
                error_count += 1
        
        await commit_db(db)
        
        print(f"\nTask Shares Summary:")
        print(f"  - Fixed: {fixed_count}")
        print(f"  - Skipped (already correct): {skip_count}")
        print(f"  - Errors: {error_count}")
        
        return fixed_count


async def fix_library_shares():
    """Fix library_shares table - update license_key_id to recipient's license_id"""
    print("\n" + "=" * 60)
    print("FIXING LIBRARY_SHARES TABLE")
    print("=" * 60)
    
    async with get_db() as db:
        # Get all shares where license_key_id doesn't match shared_with_user_id
        rows = await fetch_all(
            db,
            """
            SELECT id, item_id, license_key_id, shared_with_user_id
            FROM library_shares
            WHERE deleted_at IS NULL
            AND shared_with_user_id IS NOT NULL
            AND shared_with_user_id != ''
            """
        )
        
        if not rows:
            print("No library shares found to fix")
            return 0
        
        fixed_count = 0
        skip_count = 0
        error_count = 0
        
        for row in rows:
            share_id = row['id']
            current_license_id = row['license_key_id']
            recipient_user_id = row['shared_with_user_id']
            
            try:
                # recipient_user_id is already the license_id as string
                recipient_license_id = int(recipient_user_id)
                
                # Only update if different
                if current_license_id != recipient_license_id:
                    await execute_sql(
                        db,
                        """
                        UPDATE library_shares
                        SET license_key_id = ?
                        WHERE id = ?
                        """,
                        [recipient_license_id, share_id]
                    )
                    print(f"  Fixed library_share id={share_id}: "
                          f"license_key_id {current_license_id} -> {recipient_license_id}")
                    fixed_count += 1
                else:
                    skip_count += 1
            except (ValueError, TypeError) as e:
                print(f"  ERROR: Invalid recipient_user_id '{recipient_user_id}' for share id={share_id}: {e}")
                error_count += 1
            except Exception as e:
                print(f"  ERROR: Failed to update share id={share_id}: {e}")
                error_count += 1
        
        await commit_db(db)
        
        print(f"\nLibrary Shares Summary:")
        print(f"  - Fixed: {fixed_count}")
        print(f"  - Skipped (already correct): {skip_count}")
        print(f"  - Errors: {error_count}")
        
        return fixed_count


async def main():
    """Run the migration"""
    print("\n")
    print("╔" + "=" * 58 + "╗")
    print("║" + " " * 15 + "SHARE LICENSE_KEY_ID FIX" + " " * 18 + "║")
    print("╚" + "=" * 58 + "╝")
    print()
    print("This script fixes existing shares that have incorrect license_key_id.")
    print("Shares were previously saved with the sharer's license_id instead of")
    print("the recipient's license_id, causing recipients to not see shared items.")
    print()
    print(f"Database type: {os.environ.get('DB_TYPE', 'unknown')}")
    print()
    
    # Initialize database pool
    print("Initializing database connection...")
    await db_pool.initialize()
    print("✓ Database connected successfully")
    print()
    
    # Support --yes flag for non-interactive execution
    if len(sys.argv) > 1 and sys.argv[1] in ('--yes', '-y', '--auto'):
        confirm = 'yes'
        print("Running in automatic mode (--yes flag detected)")
    else:
        confirm = input("Do you want to continue? (yes/no): ").strip().lower()
    
    if confirm not in ('yes', 'y'):
        print("Aborted.")
        return 1
    
    print()
    
    try:
        task_fixed = await fix_task_shares()
        library_fixed = await fix_library_shares()
        
        print("\n" + "=" * 60)
        print("MIGRATION COMPLETE")
        print("=" * 60)
        print(f"Total task shares fixed: {task_fixed}")
        print(f"Total library shares fixed: {library_fixed}")
        print()
        print("✓ You can now restart the backend server.")
        print("✓ Recipients should now see previously shared tasks/items.")
        
        return 0
        
    except Exception as e:
        print(f"\n✗ MIGRATION FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
