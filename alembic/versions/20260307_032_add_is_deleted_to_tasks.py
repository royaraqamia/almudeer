"""Add is_deleted column to tasks table for soft delete support

Revision ID: 032_add_is_deleted_to_tasks
Revises: 031_fix_notifications_id_sequence
Create Date: 2026-03-07

P4-2: Add soft delete support to tasks table

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '032_add_is_deleted_to_tasks'
down_revision: Union[str, None] = '031_fix_notifications_id_sequence'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add is_deleted column and other missing columns to tasks table"""
    from db_helper import DB_TYPE
    
    if DB_TYPE == "postgresql":
        # PostgreSQL - use IF NOT EXISTS
        op.execute("""
            ALTER TABLE tasks ADD COLUMN IF NOT EXISTS is_deleted INTEGER DEFAULT 0
        """)
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_tasks_is_deleted
            ON tasks(is_deleted)
        """)
        
        # Add other missing columns
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS alarm_enabled BOOLEAN DEFAULT FALSE")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS alarm_time TIMESTAMP")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence TEXT")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS category TEXT")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS created_by TEXT")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS assigned_to TEXT")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS attachments TEXT")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'shared'")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS is_shared INTEGER DEFAULT 0")
        op.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS order_index REAL DEFAULT 0.0")
        
        # Create indexes
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_tasks_is_shared
            ON tasks(is_shared)
        """)
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_tasks_license_completed
            ON tasks(license_key_id, is_completed)
        """)
    else:
        # SQLite - check if column exists first
        try:
            op.execute("""
                ALTER TABLE tasks ADD COLUMN is_deleted INTEGER DEFAULT 0
            """)
            op.execute("""
                CREATE INDEX idx_tasks_is_deleted
                ON tasks(is_deleted)
            """)
        except Exception:
            pass  # Column already exists

        # Add other missing columns
        for col_name, col_type in [
            ("alarm_enabled", "BOOLEAN DEFAULT FALSE"),
            ("alarm_time", "TIMESTAMP"),
            ("recurrence", "TEXT"),
            ("category", "TEXT"),
            ("created_by", "TEXT"),
            ("assigned_to", "TEXT"),
            ("attachments", "TEXT"),
            ("visibility", "TEXT DEFAULT 'shared'"),
            ("is_shared", "INTEGER DEFAULT 0"),
            ("order_index", "REAL DEFAULT 0.0"),
        ]:
            try:
                op.execute(f"ALTER TABLE tasks ADD COLUMN {col_name} {col_type}")
            except Exception:
                pass  # Column already exists

        # Create indexes
        try:
            op.execute("""
                CREATE INDEX IF NOT EXISTS idx_tasks_is_shared
                ON tasks(is_shared)
            """)
            op.execute("""
                CREATE INDEX IF NOT EXISTS idx_tasks_license_completed
                ON tasks(license_key_id, is_completed)
            """)
        except Exception:
            pass


def downgrade() -> None:
    """Remove is_deleted column from tasks table"""
    op.execute("DROP INDEX IF EXISTS idx_tasks_is_deleted")
    op.execute("DROP INDEX IF EXISTS idx_tasks_is_shared")
    op.execute("DROP INDEX IF EXISTS idx_tasks_license_completed")
    op.execute("ALTER TABLE tasks DROP COLUMN is_deleted")
