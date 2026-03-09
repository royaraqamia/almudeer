"""
Al-Mudeer Database Migration - Security Fixes (February 2026)

This migration applies database changes required for the security fixes implemented
in February 2026. These changes improve FCM token deduplication and session security.

Migration includes:
1. FCM Tokens: Add unique constraints to prevent token collisions
2. Device Sessions: Add indexes for improved session revocation performance
3. License Keys: Ensure all security columns exist

IMPORTANT: 
- Backup your database before running this migration
- Run during low-traffic period for production
- SQLite migrations are auto-applied on startup
- PostgreSQL migrations should be run manually

Usage:
    python migrations/001_security_fixes_feb_2026.py
"""

import asyncio
import sys
import os

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from db_helper import get_db, execute_sql, commit_db, DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)


async def migrate_fcm_tokens():
    """
    SECURITY FIX #11 & #15: Add unique constraints to FCM tokens table
    Prevents token collisions and ensures proper deduplication
    """
    logger.info("Migrating fcm_tokens table...")
    
    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # Create unique index on token
                logger.info("Creating unique index on fcm_tokens(token)...")
                await execute_sql(db, """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_token_unique 
                    ON fcm_tokens(token)
                """)
                
                # Create unique index on device_id + license_key_id
                logger.info("Creating unique index on fcm_tokens(device_id, license_key_id)...")
                await execute_sql(db, """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_device_license_unique 
                    ON fcm_tokens(device_id, license_key_id) 
                    WHERE device_id IS NOT NULL
                """)
            else:
                # SQLite
                logger.info("Creating unique index on fcm_tokens(token) (SQLite)...")
                await execute_sql(db, """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_token_unique 
                    ON fcm_tokens(token)
                """)
                
                logger.info("Creating unique index on fcm_tokens(device_id, license_key_id) (SQLite)...")
                await execute_sql(db, """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_device_license_unique 
                    ON fcm_tokens(device_id, license_key_id)
                """)
            
            await commit_db(db)
            logger.info("✓ fcm_tokens migration completed successfully")
            
        except Exception as e:
            logger.error(f"✗ fcm_tokens migration failed: {e}")
            raise


async def migrate_device_sessions():
    """
    Add additional indexes for device_sessions to improve session revocation performance
    """
    logger.info("Migrating device_sessions table...")
    
    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # Index for session revocation checks
                logger.info("Creating index on device_sessions(is_revoked, family_id)...")
                await execute_sql(db, """
                    CREATE INDEX IF NOT EXISTS idx_device_sessions_revocation 
                    ON device_sessions(is_revoked, family_id)
                    WHERE is_revoked = FALSE
                """)
                
                # Index for license-based session lookup
                logger.info("Creating index on device_sessions(license_key_id, is_revoked)...")
                await execute_sql(db, """
                    CREATE INDEX IF NOT EXISTS idx_device_sessions_license_revoked 
                    ON device_sessions(license_key_id, is_revoked)
                """)
            else:
                # SQLite
                logger.info("Creating index on device_sessions(is_revoked, family_id) (SQLite)...")
                await execute_sql(db, """
                    CREATE INDEX IF NOT EXISTS idx_device_sessions_revocation 
                    ON device_sessions(is_revoked, family_id)
                """)
                
                logger.info("Creating index on device_sessions(license_key_id, is_revoked) (SQLite)...")
                await execute_sql(db, """
                    CREATE INDEX IF NOT EXISTS idx_device_sessions_license_revoked 
                    ON device_sessions(license_key_id, is_revoked)
                """)
            
            await commit_db(db)
            logger.info("✓ device_sessions migration completed successfully")
            
        except Exception as e:
            logger.error(f"✗ device_sessions migration failed: {e}")
            raise


async def migrate_license_keys():
    """
    Ensure all security-related columns exist in license_keys table
    """
    logger.info("Migrating license_keys table...")
    
    async with get_db() as db:
        try:
            migrations = [
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS token_version INTEGER DEFAULT 1",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP",
            ]
            
            for migration in migrations:
                try:
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, migration)
                    else:
                        # SQLite doesn't support ADD COLUMN IF NOT EXISTS
                        await execute_sql(db, migration.replace("ADD COLUMN IF NOT EXISTS", "ADD COLUMN"))
                except Exception as e:
                    logger.debug(f"Migration item skipped (may already exist): {migration} - {e}")
            
            await commit_db(db)
            logger.info("✓ license_keys migration completed successfully")
            
        except Exception as e:
            logger.error(f"✗ license_keys migration failed: {e}")
            raise


async def cleanup_duplicate_fcm_tokens():
    """
    Clean up any duplicate FCM tokens before adding unique constraints
    Keeps the most recently updated token for each device_id/license_key_id combination
    """
    logger.info("Cleaning up duplicate FCM tokens...")
    
    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # Delete duplicates, keeping the most recent
                logger.info("Removing duplicate FCM tokens (PostgreSQL)...")
                await execute_sql(db, """
                    DELETE FROM fcm_tokens a USING fcm_tokens b
                    WHERE a.device_id = b.device_id 
                    AND a.license_key_id = b.license_key_id
                    AND a.device_id IS NOT NULL
                    AND a.ctid < b.ctid
                """)
                
                # Also clean up duplicate tokens (same token value)
                await execute_sql(db, """
                    DELETE FROM fcm_tokens a USING fcm_tokens b
                    WHERE a.token = b.token
                    AND a.ctid < b.ctid
                """)
            else:
                # SQLite: More complex deduplication
                logger.info("Removing duplicate FCM tokens (SQLite)...")
                
                # Delete duplicate device_id combinations
                await execute_sql(db, """
                    DELETE FROM fcm_tokens 
                    WHERE id NOT IN (
                        SELECT MAX(id) 
                        FROM fcm_tokens 
                        WHERE device_id IS NOT NULL
                        GROUP BY device_id, license_key_id
                    )
                """)
                
                # Delete duplicate tokens
                await execute_sql(db, """
                    DELETE FROM fcm_tokens 
                    WHERE id NOT IN (
                        SELECT MAX(id) 
                        FROM fcm_tokens 
                        GROUP BY token
                    )
                """)
            
            await commit_db(db)
            logger.info("✓ Duplicate FCM tokens cleaned up successfully")
            
        except Exception as e:
            logger.error(f"✗ Duplicate cleanup failed: {e}")
            # Don't raise - duplicates will be handled by unique constraint


async def run_migration():
    """Run all migrations"""
    logger.info("=" * 60)
    logger.info("Al-Mudeer Security Fixes Migration (February 2026)")
    logger.info("=" * 60)
    logger.info(f"Database type: {DB_TYPE}")
    logger.info("")
    
    try:
        # Step 1: Cleanup duplicates first
        await cleanup_duplicate_fcm_tokens()
        
        # Step 2: Migrate FCM tokens
        await migrate_fcm_tokens()
        
        # Step 3: Migrate device sessions
        await migrate_device_sessions()
        
        # Step 4: Migrate license keys
        await migrate_license_keys()
        
        logger.info("")
        logger.info("=" * 60)
        logger.info("✓ All migrations completed successfully!")
        logger.info("=" * 60)
        logger.info("")
        logger.info("Next steps:")
        logger.info("1. Set DEVICE_SECRET_PEPPER and LICENSE_KEY_PEPPER in .env")
        logger.info("2. Restart the backend application")
        logger.info("3. Monitor logs for any issues")
        
    except Exception as e:
        logger.error("")
        logger.error("=" * 60)
        logger.error(f"✗ Migration failed: {e}")
        logger.error("=" * 60)
        logger.error("")
        logger.error("Please check the error above and try again.")
        logger.error("If the issue persists, restore from backup and contact support.")
        sys.exit(1)


if __name__ == "__main__":
    print("Starting database migration...")
    asyncio.run(run_migration())
