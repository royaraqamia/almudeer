"""
Script to revoke all device sessions for a license key.
Use this to fix fingerprint mismatch issues during development.

Usage: python revoke_sessions.py <license_key>
"""

import sys
import asyncio
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

from database import get_db, execute_sql, fetch_one, hash_license_key, DB_TYPE


async def revoke_all_sessions(license_key: str):
    """Revoke all device sessions for a given license key."""
    print(f"Revoking all sessions for license key: {license_key}")
    print(f"Database type: {DB_TYPE}")
    
    # Initialize database pool
    from db_pool import db_pool
    await db_pool.initialize()
    
    async with get_db() as db:
        # Hash the license key to look it up
        key_hash = hash_license_key(license_key)
        
        # Get license ID - use asyncpg syntax for PostgreSQL
        if DB_TYPE == 'postgresql':
            result = await db.fetchrow("SELECT id FROM license_keys WHERE key_hash = $1", key_hash)
            if result:
                result = dict(result)
        else:
            result = await fetch_one(db, "SELECT id FROM license_keys WHERE key_hash = ?", [key_hash])
            
        if not result:
            print(f"Error: License key '{license_key}' not found in database.")
            print("Make sure you're using the correct license key and database.")
            return False
        
        license_id = result.get("id")
        print(f"Found license ID: {license_id}")
        
        # Count existing sessions
        if DB_TYPE == 'postgresql':
            count_result = await db.fetchrow("SELECT COUNT(*) as count FROM device_sessions WHERE license_key_id = $1", license_id)
            if count_result:
                count_result = dict(count_result)
        else:
            count_result = await fetch_one(db, "SELECT COUNT(*) as count FROM device_sessions WHERE license_key_id = ?", [license_id])
            
        session_count = count_result.get("count", 0) if count_result else 0
        print(f"Found {session_count} existing session(s)")
        
        if session_count == 0:
            print("No sessions to revoke.")
            return True
        
        # Revoke all sessions
        if DB_TYPE == 'postgresql':
            await db.execute("UPDATE device_sessions SET is_revoked = TRUE WHERE license_key_id = $1", license_id)
        else:
            await execute_sql(db, "UPDATE device_sessions SET is_revoked = TRUE WHERE license_key_id = ?", [license_id])
        
        from db_helper import commit_db
        await commit_db(db)
        
        print(f"[OK] Successfully revoked all {session_count} session(s)")
        print("[OK] User should now login again to create a new session with correct fingerprint")
        return True


if __name__ == "__main__":
    import asyncio
    
    if len(sys.argv) < 2:
        print("Usage: python revoke_sessions.py <license_key>")
        print("Example: python revoke_sessions.py ABCD-1234-EFGH-5678")
        sys.exit(1)
    
    license_key = sys.argv[1]
    success = asyncio.run(revoke_all_sessions(license_key))
    sys.exit(0 if success else 1)
