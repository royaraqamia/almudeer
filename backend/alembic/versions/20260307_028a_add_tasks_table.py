"""Add tasks table for task management

Revision ID: 028a_add_tasks_table
Revises: 028_add_quran_progress_calculator_history
Create Date: 2026-03-07

P4: Task management table
This migration was missing from the original chain.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa
import os

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

revision: str = '028a_add_tasks_table'
down_revision: Union[str, None] = '028_add_quran_progress_calculator_history'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create tasks table and indexes"""
    
    # Helper for DB-specific syntax
    if DB_TYPE == "postgresql":
        timestamp_default = "NOW()"
    else:
        timestamp_default = "CURRENT_TIMESTAMP"

    # Create tasks table
    op.create_table(
        'tasks',
        sa.Column('id', sa.Text(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('title', sa.Text(), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_completed', sa.Boolean(), default=False),
        sa.Column('due_date', sa.DateTime(), nullable=True),
        sa.Column('priority', sa.String(20), default='medium'),
        sa.Column('color', sa.BigInteger(), nullable=True),
        sa.Column('sub_tasks', sa.Text(), nullable=True),  # JSON string
        sa.Column('alarm_enabled', sa.Boolean(), default=False),
        sa.Column('alarm_time', sa.DateTime(), nullable=True),
        sa.Column('recurrence', sa.String(50), nullable=True),
        sa.Column('category', sa.String(100), nullable=True),
        sa.Column('order_index', sa.Float(), default=0.0),
        sa.Column('created_by', sa.Text(), nullable=True),
        sa.Column('assigned_to', sa.Text(), nullable=True),
        sa.Column('attachments', sa.Text(), nullable=True),  # JSON string
        sa.Column('visibility', sa.String(20), default='shared'),
        sa.Column('is_shared', sa.Integer(), default=0),
        sa.Column('is_deleted', sa.Integer(), default=0),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text(timestamp_default)),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.Column('synced_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'])
    )

    # Indexes for common queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_license_completed
        ON tasks(license_key_id, is_completed)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to
        ON tasks(license_key_id, assigned_to, is_completed)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_visibility
        ON tasks(license_key_id, visibility, created_by)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_due_date
        ON tasks(license_key_id, due_date)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_category
        ON tasks(license_key_id, category)
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_priority
        ON tasks(license_key_id, priority)
    """)


def downgrade() -> None:
    """Drop tasks table"""
    op.drop_table('tasks')
