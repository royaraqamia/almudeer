"""Add task_shares for sharing tasks with other users

Revision ID: 029_add_task_sharing
Revises: 028a_add_tasks_table
Create Date: 2026-03-07

P4-2: Share tasks with other users with read/edit/admin permissions
Replaces old assigned_to field with proper share-based model

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '029_add_task_sharing'
down_revision: Union[str, None] = '028a_add_tasks_table'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create task_shares table and indexes"""

    op.create_table(
        'task_shares',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('task_id', sa.Text(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('shared_with_user_id', sa.Text(), nullable=False),
        sa.Column('permission', sa.String(20), nullable=False, default='read'),
        # permission: 'read', 'edit', 'admin'
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('created_by', sa.Text(), nullable=True),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.Column('deleted_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['task_id'], ['tasks.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('task_id', 'shared_with_user_id', name='uq_share_task_user')
    )

    # Indexes for common queries
    op.execute("""
        CREATE INDEX idx_task_shares_task_id
        ON task_shares(task_id)
    """)

    op.execute("""
        CREATE INDEX idx_task_shares_user_id
        ON task_shares(shared_with_user_id)
    """)

    op.execute("""
        CREATE INDEX idx_task_shares_license
        ON task_shares(license_key_id)
    """)

    op.execute("""
        CREATE INDEX idx_task_shares_active
        ON task_shares(license_key_id, task_id, deleted_at)
        WHERE deleted_at IS NULL
    """)

    # Note: is_shared column is added in 028a_add_tasks_table


def downgrade() -> None:
    """Drop task_shares table"""
    op.execute("DROP INDEX IF EXISTS idx_task_shares_active")
    op.execute("DROP INDEX IF EXISTS idx_task_shares_license")
    op.execute("DROP INDEX IF EXISTS idx_task_shares_user_id")
    op.execute("DROP INDEX IF EXISTS idx_task_shares_task_id")
    op.drop_table('task_shares')
