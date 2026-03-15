"""
Al-Mudeer Database Migration - Fix FCM Token Unique Indexes

This migration ensures unique indexes exist on fcm_tokens table to prevent
duplicate token registration when users log in from multiple devices.

Issue: The save_fcm_token function uses ON CONFLICT (device_id, license_key_id)
and ON CONFLICT (token) for atomic UPSERTs, but the unique indexes may not exist
in production if the previous migration (001_security_fixes_feb_2026.py) wasn't run.

This migration:
1. Cleans up any existing duplicate FCM tokens
2. Creates unique index on token column
3. Creates unique index on (device_id, license_key_id) combination

IMPORTANT:
- Backup your database before running this migration
- Run during low-traffic period for production

Usage:
    python migrations/006_fix_fcm_unique_indexes.py
"""

import asyncio
import sys
import os

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from db_helper import get_db, execute_sql, commit_db, DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)


async def cleanup_duplicate_fcm_tokens():
    """
    Clean up any duplicate FCM tokens before adding unique constraints.
    Keeps the most recently updated token for each combination.
    """
    logger.info("Cleaning up duplicate FCM tokens...")

    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # Delete duplicate device_id combinations, keeping the most recent
                logger.info("Removing duplicate FCM tokens by device_id (PostgreSQL)...")
                await execute_sql(db, """
                    DELETE FROM fcm_tokens a USING fcm_tokens b
                    WHERE a.device_id = b.device_id
                    AND a.license_key_id = b.license_key_id
                    AND a.device_id IS NOT NULL
                    AND a.ctid < b.ctid
                """)

                # Also clean up duplicate tokens (same token value)
                logger.info("Removing duplicate FCM tokens by token value (PostgreSQL)...")
                await execute_sql(db, """
                    DELETE FROM fcm_tokens a USING fcm_tokens b
                    WHERE a.token = b.token
                    AND a.ctid < b.ctid
                """)
            else:
                # SQLite: More complex deduplication
                logger.info("Removing duplicate FCM tokens by device_id (SQLite)...")

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
                logger.info("Removing duplicate FCM tokens by token value (SQLite)...")
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


async def create_unique_indexes():
    """
    Create unique indexes on fcm_tokens table to prevent duplicates.
    These indexes are required for the UPSERT operations in save_fcm_token.
    """
    logger.info("Creating unique indexes on fcm_tokens table...")

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
                # Partial index: only for rows where device_id IS NOT NULL
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
            logger.info("✓ Unique indexes created successfully")

        except Exception as e:
            logger.error(f"✗ Index creation failed: {e}")
            raise


async def run_migration():
    """Run the FCM token unique index migration"""
    logger.info("=" * 60)
    logger.info("Al-Mudeer Migration - Fix FCM Unique Indexes")
    logger.info("=" * 60)
    logger.info(f"Database type: {DB_TYPE}")
    logger.info("")

    try:
        # Step 1: Cleanup duplicates first (required before adding unique constraints)
        await cleanup_duplicate_fcm_tokens()

        # Step 2: Create unique indexes
        await create_unique_indexes()

        logger.info("")
        logger.info("=" * 60)
        logger.info("✓ Migration completed successfully!")
        logger.info("=" * 60)
        logger.info("")
        logger.info("The fcm_tokens table now has unique indexes to prevent:")
        logger.info("  - Duplicate FCM tokens (same token registered multiple times)")
        logger.info("  - Duplicate device registrations (same device on same license)")
        logger.info("")
        logger.info("Next steps:")
        logger.info("  1. Restart the backend application")
        logger.info("  2. Monitor logs for any issues")

    except Exception as e:
        logger.error("")
        logger.error("=" * 60)
        logger.error(f"✗ Migration failed: {e}")
        logger.error("=" * 60)
        logger.error("")
        logger.error("Please check the error above and try again.")
        logger.error("If the issue persists, restore from backup and contact support.")
        sys.exit(1)


async def main():
    """Main entry point - initialize DB pool and run migration"""
    from db_pool import db_pool
    
    # Initialize database connection pool
    await db_pool.initialize()
    
    # Run the migration
    await run_migration()
    
    # Cleanup: close all pool connections
    await db_pool.close()


if __name__ == "__main__":
    print("Starting FCM unique indexes migration...")
    asyncio.run(main())
