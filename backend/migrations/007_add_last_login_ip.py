"""
Migration 007: Add last_login_ip columns for audit trail

P2-13 FIX: Track the IP address of the last login for both user_accounts
and license_keys tables. This enables security auditing and forensics.
"""

import os
from db_helper import get_db, execute_sql, commit_db
from database import DB_TYPE
from logging_config import get_logger

logger = get_logger(__name__)


async def run_migration():
    """Add last_login_ip columns to user_accounts and license_keys tables."""
    logger.info("Running migration 007: Add last_login_ip columns")

    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                # PostgreSQL: Add column if not exists
                await execute_sql(db, """
                    ALTER TABLE user_accounts
                    ADD COLUMN IF NOT EXISTS last_login_ip VARCHAR(45)
                """)
                await execute_sql(db, """
                    ALTER TABLE license_keys
                    ADD COLUMN IF NOT EXISTS last_login_ip VARCHAR(45)
                """)
            else:
                # SQLite: Use ALTER TABLE (no IF NOT EXISTS, catch error if exists)
                try:
                    await execute_sql(db, """
                        ALTER TABLE user_accounts
                        ADD COLUMN last_login_ip VARCHAR(45)
                    """)
                except Exception:
                    logger.debug("last_login_ip already exists on user_accounts")

                try:
                    await execute_sql(db, """
                        ALTER TABLE license_keys
                        ADD COLUMN last_login_ip VARCHAR(45)
                    """)
                except Exception:
                    logger.debug("last_login_ip already exists on license_keys")

            await commit_db(db)
            logger.info("Migration 007 completed: last_login_ip columns added")

        except Exception as e:
            logger.error(f"Migration 007 failed: {e}")
            raise
