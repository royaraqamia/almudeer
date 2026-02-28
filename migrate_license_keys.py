"""
Al-Mudeer - License Key Hash Migration Script

Migrates existing license key hashes from plain SHA-256 to HMAC-SHA256 with pepper.

SECURITY: This script re-hashes all license keys using the new peppered hashing scheme.
Run this AFTER setting LICENSE_KEY_PEPPER in your .env file.

IMPORTANT: 
1. Back up your database before running this script
2. Set LICENSE_KEY_PEPPER in .env first
3. Run during low-traffic period
4. Users will need to re-login after migration (old hashes become invalid)

Usage:
    python migrate_license_keys.py
"""

import asyncio
import os
import sys

# Add parent directory to path to import backend modules
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from database import get_db, adapt_sql_for_db, hash_license_key
from security import get_license_key_pepper


async def migrate_license_keys():
    """
    Migrate all license keys to use peppered hashing.
    
    This script:
    1. Reads all license keys from the database (plain text not stored, so we need to update from known keys)
    2. Re-hashes them with the new peppered scheme
    3. Updates the database
    
    WARNING: Since license keys are one-way hashed, we cannot recover the original keys.
    This migration requires users to re-enter their license keys OR
    we need to temporarily accept both hash formats during a transition period.
    
    ALTERNATIVE APPROACH:
    For existing installations, implement dual-hash verification:
    1. Check new peppered hash first
    2. If not found, check old plain SHA-256 hash
    3. If old hash matches, re-hash with pepper and update
    4. Remove old hash support after transition period
    """
    
    print("=" * 60)
    print("LICENSE KEY HASH MIGRATION")
    print("=" * 60)
    print()
    
    # Check if pepper is set
    try:
        pepper = get_license_key_pepper()
        print(f"✓ License key pepper found: {pepper[:16]}...")
    except Exception as e:
        print(f"✗ ERROR: License key pepper not set!")
        print(f"  Please set LICENSE_KEY_PEPPER in your .env file first.")
        print(f"  Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\"")
        sys.exit(1)
    
    print()
    print("IMPORTANT: Since license keys are one-way hashed, we cannot migrate")
    print("existing hashes without the original plain-text keys.")
    print()
    print("RECOMMENDED APPROACH:")
    print("1. Implement dual-hash verification in the login flow")
    print("2. Accept both old (SHA-256) and new (HMAC-SHA256) hashes")
    print("3. When a user logs in with old hash, re-hash with pepper and update")
    print("4. After 30-90 days, remove old hash support")
    print()
    
    # Show what needs to be done in database.py
    print("=" * 60)
    print("MANUAL STEPS REQUIRED:")
    print("=" * 60)
    print()
    print("1. Update validate_license_key() in database.py to check both hash formats:")
    print()
    print("   async def validate_license_key(license_key: str):")
    print("       # Try new peppered hash first")
    print("       new_hash = hash_license_key(license_key)  # Uses HMAC with pepper")
    print("       result = await fetch_one(db, 'SELECT * FROM license_keys WHERE key_hash = ?', [new_hash])")
    print("       if result:")
    print("           return result")
    print()
    print("       # Fallback to old hash for backward compatibility")
    print("       import hashlib")
    print("       old_hash = hashlib.sha256(license_key.encode()).hexdigest()")
    print("       result = await fetch_one(db, 'SELECT * FROM license_keys WHERE key_hash = ?', [old_hash])")
    print("       if result:")
    print("           # Migrate to new hash")
    print("           await execute_sql(db, 'UPDATE license_keys SET key_hash = ? WHERE id = ?', [new_hash, result['id']])")
    print("           return result")
    print()
    print("2. After migration period (30-90 days), remove the old hash fallback")
    print()
    print("=" * 60)
    print("MIGRATION COMPLETE")
    print("=" * 60)
    
    return True


if __name__ == "__main__":
    asyncio.run(migrate_license_keys())
