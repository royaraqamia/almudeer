"""Add index for athkar_stats in user_preferences

Revision ID: 034_add_athkar_stats_index
Revises: 033_merge_library_and_task_indexes
Create Date: 2026-03-10

Adds an index on the athkar_stats column for faster lookups
when syncing athkar progress across devices.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '034_add_athkar_stats_index'
down_revision: Union[str, None] = '033_merge_library_and_task_indexes'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add index for athkar_stats column"""
    # Index for faster athkar_stats lookups
    # Note: We can't use partial index on TEXT column, but the index
    # will still speed up queries where athkar_stats IS NOT NULL
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_user_preferences_athkar_stats
        ON user_preferences(athkar_stats)
        WHERE athkar_stats IS NOT NULL
    """)


def downgrade() -> None:
    """Remove the index"""
    op.execute("DROP INDEX IF EXISTS idx_user_preferences_athkar_stats")
