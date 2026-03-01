"""
Al-Mudeer - Remove Device Fingerprint Column Migration
Removes the device_fingerprint column from device_sessions table.

This migration simplifies authentication by removing device fingerprint tracking.
Device binding is now handled solely through device_secret_hash.

Run: python migrations/003_remove_device_fingerprint.py
"""

import asyncio
from db_helper import get_db, execute_sql, commit_db
from database import DB_TYPE


async def migrate():
    """Remove device_fingerprint column from device_sessions table"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # PostgreSQL: Drop the column
            await execute_sql(db, """
                ALTER TABLE device_sessions 
                DROP COLUMN IF EXISTS device_fingerprint
            """)
        else:
            # SQLite: Drop the column (requires table recreation in older versions)
            # SQLite 3.35.0+ supports DROP COLUMN directly
            try:
                await execute_sql(db, """
                    ALTER TABLE device_sessions 
                    DROP COLUMN device_fingerprint
                """)
            except Exception as e:
                # Fallback for older SQLite versions: recreate table without the column
                print(f"Direct DROP COLUMN failed: {e}")
                print("Recreating table without device_fingerprint column...")
                
                # Create temporary table without device_fingerprint
                await execute_sql(db, """
                    CREATE TABLE device_sessions_new (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        license_key_id INTEGER NOT NULL,
                        family_id VARCHAR(255) NOT NULL,
                        refresh_token_jti VARCHAR(255) NOT NULL,
                        ip_address VARCHAR(255),
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        expires_at TIMESTAMP NOT NULL,
                        is_revoked BOOLEAN DEFAULT FALSE,
                        device_secret_hash VARCHAR(255),
                        device_name VARCHAR(255),
                        location VARCHAR(255),
                        user_agent TEXT,
                        FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE
                    )
                """)
                
                # Copy data from old table to new table (excluding device_fingerprint)
                await execute_sql(db, """
                    INSERT INTO device_sessions_new 
                    SELECT 
                        id, license_key_id, family_id, refresh_token_jti,
                        ip_address, created_at, last_used_at, expires_at,
                        is_revoked, device_secret_hash, device_name, location,
                        user_agent
                    FROM device_sessions
                """)
                
                # Drop old table
                await execute_sql(db, "DROP TABLE device_sessions")
                
                # Rename new table
                await execute_sql(db, "ALTER TABLE device_sessions_new RENAME TO device_sessions")
                
                # Recreate indexes
                await execute_sql(db, """
                    CREATE INDEX IF NOT EXISTS idx_device_sessions_jti
                    ON device_sessions(refresh_token_jti)
                """)
                await execute_sql(db, """
                    CREATE INDEX IF NOT EXISTS idx_device_sessions_family
                    ON device_sessions(family_id)
                """)

        await commit_db(db)

    print("Device fingerprint column removed successfully")


if __name__ == "__main__":
    asyncio.run(migrate())
