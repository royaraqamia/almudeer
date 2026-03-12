"""
FIX #8: Add composite index on library_shares for expired share cleanup

This migration adds a composite index to improve the performance of the
cleanup_expired_shares() job which queries by expires_at and deleted_at.

Index: idx_library_shares_expires_deleted (expires_at, deleted_at)
"""

import asyncio
import logging
from db_helper import get_db, execute_sql, DB_TYPE

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def add_library_shares_index():
    """Add composite index for expired share cleanup optimization"""
    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # PostgreSQL syntax
                await execute_sql(
                    db,
                    """
                    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_library_shares_expires_deleted
                    ON library_shares(expires_at, deleted_at)
                    WHERE expires_at IS NOT NULL
                    """
                )
                logger.info("Created PostgreSQL index idx_library_shares_expires_deleted")
            else:
                # SQLite syntax
                await execute_sql(
                    db,
                    """
                    CREATE INDEX IF NOT EXISTS idx_library_shares_expires_deleted
                    ON library_shares(expires_at, deleted_at)
                    """
                )
                logger.info("Created SQLite index idx_library_shares_expires_deleted")

            logger.info("Index creation completed successfully")
        except Exception as e:
            logger.error(f"Failed to create index: {e}", exc_info=True)
            raise


if __name__ == "__main__":
    logger.info(f"Running library shares index migration (DB type: {DB_TYPE})")
    asyncio.run(add_library_shares_index())
    logger.info("Migration completed")
