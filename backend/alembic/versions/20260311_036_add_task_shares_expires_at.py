"""Add expires_at column to task_shares for share expiration support

Revision ID: 036_add_task_shares_expires_at
Revises: 033_merge_library_and_task_indexes
Create Date: 2026-03-11

P4-2 FIX: Add expires_at column to task_shares for time-limited sharing
The column was referenced in queries but never added to the schema.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '036_add_task_shares_expires_at'
down_revision: Union[str, None] = '033_merge_library_and_task_indexes'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add expires_at column to task_shares and create index"""
    from db_helper import DB_TYPE

    # Check if column already exists
    connection = op.get_bind()
    column_exists = False

    if DB_TYPE == "postgresql":
        for row in connection.execute(sa.text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'task_shares' AND column_name = 'expires_at'
        """)):
            column_exists = True
            break
    else:
        for row in connection.execute(sa.text("PRAGMA table_info(task_shares)")):
            if row[1] == 'expires_at':
                column_exists = True
                break

    if not column_exists:
        # Add expires_at column for time-limited sharing
        op.add_column('task_shares', sa.Column('expires_at', sa.DateTime(), nullable=True))

    # Create index for expiration queries
    # Used in: WHERE (expires_at IS NULL OR expires_at > ?)
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_task_shares_expires_at
            ON task_shares(expires_at)
            WHERE deleted_at IS NULL
        """)
        # Also create composite index for common query pattern
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_task_shares_active_with_expiration
            ON task_shares(license_key_id, task_id, deleted_at, expires_at)
            WHERE deleted_at IS NULL
        """)
    else:
        # SQLite doesn't support partial indexes in older versions
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_task_shares_expires_at
            ON task_shares(expires_at)
        """)
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_task_shares_active_with_expiration
            ON task_shares(license_key_id, task_id, deleted_at, expires_at)
        """)


def downgrade() -> None:
    """Remove expires_at column from task_shares"""
    op.execute("DROP INDEX IF EXISTS idx_task_shares_expires_at")
    op.execute("DROP INDEX IF EXISTS idx_task_shares_active_with_expiration")
    op.drop_column('task_shares', 'expires_at')
