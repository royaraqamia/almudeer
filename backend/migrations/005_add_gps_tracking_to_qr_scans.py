"""
Migration 005: Add GPS tracking columns to qr_scan_logs

This migration adds latitude, longitude, and app_version columns to the qr_scan_logs table.
These columns are used for enhanced analytics and location-based tracking of QR code scans.

Date: 2026-03-12
"""

from logging_config import get_logger
from db_helper import execute_sql, commit_db
from database import DB_TYPE, get_db

logger = get_logger(__name__)


async def upgrade():
    """Add GPS tracking columns to qr_scan_logs"""
    logger.info("Starting migration 005: Add GPS tracking columns to qr_scan_logs")

    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                # PostgreSQL: Use IF NOT EXISTS to avoid errors if columns already exist
                await execute_sql(
                    db,
                    "ALTER TABLE qr_scan_logs ADD COLUMN IF NOT EXISTS latitude REAL"
                )
                await execute_sql(
                    db,
                    "ALTER TABLE qr_scan_logs ADD COLUMN IF NOT EXISTS longitude REAL"
                )
                await execute_sql(
                    db,
                    "ALTER TABLE qr_scan_logs ADD COLUMN IF NOT EXISTS app_version TEXT"
                )
                
                # Create index for location-based analytics
                await execute_sql(
                    db,
                    "CREATE INDEX IF NOT EXISTS idx_qr_scan_logs_location ON qr_scan_logs(latitude, longitude)"
                )
            else:
                # SQLite: Check if columns exist first
                result = await execute_sql(
                    db,
                    "PRAGMA table_info(qr_scan_logs)"
                )
                columns = [row[1] for row in result] if result else []
                
                # Add columns if they don't exist
                if "latitude" not in columns:
                    await execute_sql(db, "ALTER TABLE qr_scan_logs ADD COLUMN latitude REAL")
                    logger.info("Added latitude column to qr_scan_logs")
                
                if "longitude" not in columns:
                    await execute_sql(db, "ALTER TABLE qr_scan_logs ADD COLUMN longitude REAL")
                    logger.info("Added longitude column to qr_scan_logs")
                
                if "app_version" not in columns:
                    await execute_sql(db, "ALTER TABLE qr_scan_logs ADD COLUMN app_version TEXT")
                    logger.info("Added app_version column to qr_scan_logs")
                
                # Create index for location-based analytics
                await execute_sql(
                    db,
                    "CREATE INDEX IF NOT EXISTS idx_qr_scan_logs_location ON qr_scan_logs(latitude, longitude)"
                )
            
            await commit_db(db)

        logger.info("Migration 005 completed: GPS tracking columns added to qr_scan_logs")

    except Exception as e:
        logger.error(f"Migration 005 failed: {e}")
        raise


async def downgrade():
    """Remove GPS tracking columns from qr_scan_logs (for rollback)"""
    logger.info("Rolling back migration 005: Removing GPS tracking columns")

    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                # PostgreSQL: Drop columns if they exist
                await execute_sql(
                    db,
                    "ALTER TABLE qr_scan_logs DROP COLUMN IF EXISTS latitude"
                )
                await execute_sql(
                    db,
                    "ALTER TABLE qr_scan_logs DROP COLUMN IF EXISTS longitude"
                )
                await execute_sql(
                    db,
                    "ALTER TABLE qr_scan_logs DROP COLUMN IF EXISTS app_version"
                )
                
                # Drop index
                await execute_sql(
                    db,
                    "DROP INDEX IF EXISTS idx_qr_scan_logs_location"
                )
            else:
                # SQLite: Cannot drop columns in older versions
                # We'll just drop the index and leave the columns
                # To fully remove columns, would need to recreate the table
                await execute_sql(
                    db,
                    "DROP INDEX IF EXISTS idx_qr_scan_logs_location"
                )
                logger.warning("SQLite: Columns cannot be dropped without recreating the table")
            
            await commit_db(db)

        logger.info("Migration 005 rolled back successfully")

    except Exception as e:
        logger.error(f"Migration 005 rollback failed: {e}")
        raise


if __name__ == "__main__":
    import asyncio

    async def main():
        await upgrade()
        print("Migration 005 completed successfully")

    asyncio.run(main())
