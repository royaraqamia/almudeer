"""Add updated_at column to task_shares

Revision ID: 030_add_task_shares_updated_at
Revises: 029_add_task_sharing
Create Date: 2026-03-08

DATA-003 FIX: Add updated_at column to task_shares for consistency with library_shares

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '030_add_task_shares_updated_at'
down_revision: Union[str, None] = '029_add_task_sharing'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add updated_at column to task_shares if not exists and add index"""
    from alembic import op
    import sqlalchemy as sa
    import os
    
    # Detect database type
    DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()
    
    # Check if column exists (it should from 029_add_task_sharing)
    # This migration is kept for backwards compatibility
    connection = op.get_bind()
    column_exists = False
    
    if DB_TYPE == "postgresql":
        # PostgreSQL-compatible column check
        for row in connection.execute(sa.text("""
            SELECT column_name FROM information_schema.columns 
            WHERE table_name = 'task_shares' AND column_name = 'updated_at'
        """)):
            column_exists = True
            break
    else:
        # SQLite-compatible column check
        for row in connection.execute(sa.text("PRAGMA table_info(task_shares)")):
            if row[1] == 'updated_at':
                column_exists = True
                break
    
    if not column_exists:
        # Add updated_at column
        op.add_column('task_shares', sa.Column('updated_at', sa.DateTime(), nullable=True))
        
        # Set updated_at = created_at for existing shares
        op.execute("""
            UPDATE task_shares SET updated_at = created_at WHERE updated_at IS NULL
        """)

    # Add index for common queries (sorting by updated_at)
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_task_shares_updated_at
            ON task_shares(updated_at)
            WHERE deleted_at IS NULL
        """)
    else:
        # SQLite doesn't support partial indexes with WHERE in older versions
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_task_shares_updated_at
            ON task_shares(updated_at)
        """)


def downgrade() -> None:
    """Remove updated_at column from task_shares"""
    op.execute("DROP INDEX IF EXISTS idx_task_shares_updated_at")
    op.drop_column('task_shares', 'updated_at')
