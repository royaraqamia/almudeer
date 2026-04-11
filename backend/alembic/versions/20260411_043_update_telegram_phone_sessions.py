"""Update telegram_phone_sessions table structure

Revision ID: 043_update_telegram_phone_sessions
Revises: 042_remove_license_keys
Create Date: 2026-04-11

This migration updates the telegram_phone_sessions table to:
1. Make user_id the primary identifier (UNIQUE NOT NULL)
2. Remove the FOREIGN KEY constraint to license_keys (already removed in 042)
3. Update table structure to match new code expectations
"""
from typing import Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '043_update_telegram_phone_sessions'
down_revision: Union[str, None] = '042_remove_license_keys'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "postgresql").lower()


def upgrade() -> None:
    """Update telegram_phone_sessions table structure"""

    # Helper to check if column exists
    def column_exists(table, column):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT column_name FROM information_schema.columns "
                f"WHERE table_name='{table}' AND column_name='{column}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False

    # Helper to check if table exists
    def table_exists(table):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT table_name FROM information_schema.tables "
                f"WHERE table_schema='public' AND table_name='{table}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(
                f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table}'"
            ))
            return res.first() is not None

    # Helper to check if constraint exists
    def constraint_exists(table, constraint_name):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT conname FROM pg_constraint WHERE conname='{constraint_name}'"
            ))
            return res.first() is not None
        else:
            # SQLite doesn't have constraints in the same way
            return False

    print("=== Starting telegram_phone_sessions structure update ===")

    if not table_exists('telegram_phone_sessions'):
        print("telegram_phone_sessions table does not exist. Skipping.")
        return

    if DB_TYPE == "postgresql":
        # PostgreSQL: Can modify columns directly
        
        # Step 1: Drop foreign key constraint if it still exists
        if constraint_exists('telegram_phone_sessions', 'telegram_phone_sessions_license_key_id_fkey'):
            print("Dropping foreign key constraint: telegram_phone_sessions_license_key_id_fkey")
            op.execute("""
                ALTER TABLE telegram_phone_sessions
                DROP CONSTRAINT IF EXISTS telegram_phone_sessions_license_key_id_fkey
            """)
        
        # Step 2: Drop license_key_id column if it still exists
        if column_exists('telegram_phone_sessions', 'license_key_id'):
            print("Dropping license_key_id column")
            op.execute("""
                ALTER TABLE telegram_phone_sessions
                DROP COLUMN IF EXISTS license_key_id
            """)
        
        # Step 3: Make user_id NOT NULL if it isn't already
        # First, update any NULL values to empty string to avoid constraint violation
        op.execute("""
            UPDATE telegram_phone_sessions
            SET user_id = COALESCE(user_id, '')
            WHERE user_id IS NULL
        """)
        
        # Now set NOT NULL constraint
        print("Setting user_id to NOT NULL")
        op.execute("""
            ALTER TABLE telegram_phone_sessions
            ALTER COLUMN user_id SET NOT NULL
        """)
        
        # Step 4: Add UNIQUE constraint on user_id if it doesn't exist
        # Check if unique constraint/index exists
        unique_check = op.get_bind().execute(sa.text(
            """
            SELECT indexname FROM pg_indexes 
            WHERE tablename = 'telegram_phone_sessions' 
            AND indexdef LIKE '%user_id%' 
            AND indexdef LIKE '%UNIQUE%'
            """
        ))
        
        if not unique_check.first():
            print("Adding UNIQUE constraint on user_id")
            op.execute("""
                ALTER TABLE telegram_phone_sessions
                ADD CONSTRAINT telegram_phone_sessions_user_id_key UNIQUE (user_id)
            """)
        else:
            print("UNIQUE constraint on user_id already exists")
        
        # Step 5: Ensure user_id has correct type (TEXT)
        print("Ensuring user_id column type is TEXT")
        op.execute("""
            ALTER TABLE telegram_phone_sessions
            ALTER COLUMN user_id TYPE TEXT
        """)
        
    else:
        # SQLite: More complex, need to recreate table
        print("SQLite detected. Recreating telegram_phone_sessions table...")
        
        # Step 1: Create new table with correct structure
        op.execute("""
            CREATE TABLE IF NOT EXISTS telegram_phone_sessions_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT UNIQUE NOT NULL,
                phone_number TEXT NOT NULL,
                session_data_encrypted TEXT NOT NULL,
                user_first_name TEXT,
                user_last_name TEXT,
                user_username TEXT,
                is_active INTEGER DEFAULT 1,
                last_synced_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Step 2: Migrate data from old table
        op.execute("""
            INSERT OR IGNORE INTO telegram_phone_sessions_new
                (user_id, phone_number, session_data_encrypted, user_first_name, 
                 user_last_name, user_username, is_active, last_synced_at, created_at, updated_at)
            SELECT 
                COALESCE(user_id, ''),
                phone_number,
                session_data_encrypted,
                user_first_name,
                user_last_name,
                user_username,
                is_active,
                last_synced_at,
                created_at,
                updated_at
            FROM telegram_phone_sessions
            WHERE user_id IS NOT NULL
        """)
        
        # Step 3: Drop old table
        op.execute("DROP TABLE IF EXISTS telegram_phone_sessions")
        
        # Step 4: Rename new table
        op.execute("ALTER TABLE telegram_phone_sessions_new RENAME TO telegram_phone_sessions")
        
        print("SQLite table recreated successfully")

    print("=== telegram_phone_sessions structure update complete ===")


def downgrade() -> None:
    """Revert the structure changes"""
    
    # Helper to check if table exists
    def table_exists(table):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT table_name FROM information_schema.tables "
                f"WHERE table_schema='public' AND table_name='{table}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(
                f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table}'"
            ))
            return res.first() is not None
    
    # Helper to check if column exists
    def column_exists(table, column):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT column_name FROM information_schema.columns "
                f"WHERE table_name='{table}' AND column_name='{column}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False
    
    print("=== WARNING: Downgrade may not be fully reversible ===")
    
    if not table_exists('telegram_phone_sessions'):
        print("telegram_phone_sessions table does not exist. Skipping.")
        return
    
    if DB_TYPE == "postgresql":
        # PostgreSQL
        print("Reverting PostgreSQL changes...")
        
        # Drop UNIQUE constraint
        op.execute("""
            ALTER TABLE telegram_phone_sessions
            DROP CONSTRAINT IF EXISTS telegram_phone_sessions_user_id_key
        """)
        
        # Make user_id nullable again
        op.execute("""
            ALTER TABLE telegram_phone_sessions
            ALTER COLUMN user_id DROP NOT NULL
        """)
        
        # Recreate license_key_id column if needed
        if not column_exists('telegram_phone_sessions', 'license_key_id'):
            op.execute("""
                ALTER TABLE telegram_phone_sessions
                ADD COLUMN license_key_id INTEGER
            """)
            
            # Recreate FK constraint if license_keys table exists
            if table_exists('license_keys'):
                op.execute("""
                    ALTER TABLE telegram_phone_sessions
                    ADD CONSTRAINT telegram_phone_sessions_license_key_id_fkey
                    FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
                """)
    else:
        # SQLite
        print("Reverting SQLite changes...")
        # SQLite downgrade is complex - would need to recreate table again
        print("SQLite downgrade not fully implemented. Manual intervention may be required.")
    
    print("=== Downgrade complete (may be partial) ===")
