"""
Migration 004: Remove device_secret_hash column

This migration removes the device_secret_hash column from device_sessions table.
Device binding via device secrets has been removed to allow license keys to be
used from any device without restriction.

Date: 2026-03-08
"""

from logging_config import get_logger
from db_helper import execute_sql, commit_db
from database import DB_TYPE, get_db

logger = get_logger(__name__)


async def upgrade():
    """Remove device_secret_hash column from device_sessions"""
    logger.info("Starting migration 004: Remove device_secret_hash column")

    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                # PostgreSQL: Use IF EXISTS to avoid errors if column doesn't exist
                await execute_sql(
                    db,
                    "ALTER TABLE device_sessions DROP COLUMN IF EXISTS device_secret_hash"
                )
            else:
                # SQLite: Check if column exists first
                # Get table info
                result = await execute_sql(
                    db,
                    "PRAGMA table_info(device_sessions)"
                )
                columns = [row[1] for row in result] if result else []

                if "device_secret_hash" in columns:
                    # SQLite doesn't support DROP COLUMN directly in older versions
                    # We need to recreate the table without the column

                    # Step 1: Get all data
                    all_sessions = await execute_sql(
                        db,
                        "SELECT id, license_key_id, family_id, refresh_token_jti, ip_address, "
                        "expires_at, device_name, location, user_agent, created_at, "
                        "last_used_at, is_revoked FROM device_sessions"
                    )

                    # Step 2: Drop old table
                    await execute_sql(db, "DROP TABLE device_sessions")

                    # Step 3: Create new table without device_secret_hash
                    await execute_sql(db, """
                        CREATE TABLE device_sessions (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            license_key_id INTEGER NOT NULL,
                            family_id TEXT NOT NULL,
                            refresh_token_jti TEXT NOT NULL,
                            ip_address TEXT,
                            expires_at TIMESTAMP NOT NULL,
                            device_name TEXT,
                            location TEXT,
                            user_agent TEXT,
                            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            is_revoked INTEGER DEFAULT 0,
                            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
                        )
                    """)

                    # Step 4: Recreate indexes
                    await execute_sql(db, """
                        CREATE INDEX IF NOT EXISTS idx_device_sessions_family_id
                        ON device_sessions(family_id)
                    """)
                    await execute_sql(db, """
                        CREATE INDEX IF NOT EXISTS idx_device_sessions_license_key_id
                        ON device_sessions(license_key_id)
                    """)
                    await execute_sql(db, """
                        CREATE INDEX IF NOT EXISTS idx_device_sessions_refresh_token_jti
                        ON device_sessions(refresh_token_jti)
                    """)

                    # Step 5: Restore data (without device_secret_hash)
                    if all_sessions:
                        for session in all_sessions:
                            await execute_sql(
                                db,
                                """INSERT INTO device_sessions
                                   (id, license_key_id, family_id, refresh_token_jti, ip_address,
                                    expires_at, device_name, location, user_agent, created_at,
                                    last_used_at, is_revoked)
                                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                                list(session)
                            )

            await commit_db(db)

        logger.info("Migration 004 completed: device_secret_hash column removed")

    except Exception as e:
        logger.error(f"Migration 004 failed: {e}")
        raise


async def downgrade():
    """Add back device_secret_hash column (for rollback)"""
    logger.info("Rolling back migration 004: Adding device_secret_hash column")

    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                await execute_sql(
                    db,
                    "ALTER TABLE device_sessions ADD COLUMN device_secret_hash VARCHAR(255)"
                )
            else:
                # SQLite: Add column
                await execute_sql(
                    db,
                    "ALTER TABLE device_sessions ADD COLUMN device_secret_hash VARCHAR(255)"
                )

            await commit_db(db)

        logger.info("Migration 004 rolled back successfully")

    except Exception as e:
        logger.error(f"Migration 004 rollback failed: {e}")
        raise


if __name__ == "__main__":
    import asyncio

    async def main():
        await upgrade()
        print("Migration 004 completed successfully")

    asyncio.run(main())
