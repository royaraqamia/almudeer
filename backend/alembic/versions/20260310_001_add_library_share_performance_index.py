"""Add performance index for library_shares shared_with_user_id queries

Revision ID: 033_merge_library_and_task_indexes
Revises: 032_add_is_deleted_to_tasks, 030_add_task_shares_updated_at
Create Date: 2026-03-10

Minor Issue #11: Add composite index for efficient shared items lookup
The existing idx_shares_user_id only indexes shared_with_user_id,
but queries typically filter by license_key_id AND shared_with_user_id AND deleted_at.
This composite index optimizes those queries.

This is a merge migration that combines the task and library index branches.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '033_merge_library_and_task_indexes'
down_revision: Union[str, None] = ('032_add_is_deleted_to_tasks', '030_add_task_shares_updated_at')
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add composite index for library_shares"""
    
    # Composite index for common query pattern:
    # WHERE shared_with_user_id = ? AND license_key_id = ? AND deleted_at IS NULL
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_shared_with_license_active
        ON library_shares(shared_with_user_id, license_key_id, deleted_at)
        WHERE deleted_at IS NULL
    """)
    
    # Also ensure the simple index exists for other query patterns
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_shared_with_user_id
        ON library_shares(shared_with_user_id)
    """)


def downgrade() -> None:
    """Remove the composite index"""
    op.execute("DROP INDEX IF EXISTS idx_shares_shared_with_license_active")
    op.execute("DROP INDEX IF EXISTS idx_shares_shared_with_user_id")
