"""Add transfer history table for tracking file transfers

Revision ID: 022_add_transfer_history
Revises: 021_add_share_performance_indexes
Create Date: 2026-02-27

P3-1/Nearby: Track file transfer history for analytics and monitoring

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '025_add_transfer_history'
down_revision: Union[str, None] = '024_add_share_performance_indexes'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create transfer_history table and indexes"""

    op.create_table(
        'transfer_history',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('session_id', sa.Text(), nullable=False),
        sa.Column('device_id_a', sa.Text(), nullable=False),  # Sender
        sa.Column('device_id_b', sa.Text(), nullable=False),  # Receiver
        sa.Column('file_name', sa.Text(), nullable=False),
        sa.Column('file_size', sa.BigInteger(), nullable=False),
        sa.Column('file_type', sa.Text(), nullable=False),  # image, video, document, etc.
        sa.Column('mime_type', sa.Text(), nullable=False),
        sa.Column('file_hash', sa.Text(), nullable=True),  # SHA256 for integrity
        sa.Column('status', sa.Text(), nullable=False),  # 'completed', 'failed', 'cancelled'
        sa.Column('direction', sa.Text(), nullable=False),  # 'sending', 'receiving'
        sa.Column('started_at', sa.DateTime(), nullable=True),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.Column('duration_seconds', sa.Integer(), nullable=True),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('retry_count', sa.Integer(), default=0),
        sa.Column('bytes_transferred', sa.BigInteger(), default=0),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE')
    )

    # Indexes for common queries
    op.execute("""
        CREATE INDEX idx_transfer_history_license
        ON transfer_history(license_key_id, created_at DESC)
    """)

    op.execute("""
        CREATE INDEX idx_transfer_history_status
        ON transfer_history(license_key_id, status)
        WHERE deleted_at IS NULL
    """)

    op.execute("""
        CREATE INDEX idx_transfer_history_session
        ON transfer_history(session_id)
    """)

    op.execute("""
        CREATE INDEX idx_transfer_history_device
        ON transfer_history(device_id_a, device_id_b, created_at DESC)
    """)

    op.execute("""
        CREATE INDEX idx_transfer_history_completed_at
        ON transfer_history(completed_at DESC)
        WHERE completed_at IS NOT NULL
    """)

    # Add soft delete column for analytics retention
    op.execute("""
        ALTER TABLE transfer_history ADD COLUMN deleted_at TIMESTAMP NULL
    """)


def downgrade() -> None:
    """Drop transfer_history table and indexes"""
    op.execute("DROP INDEX IF EXISTS idx_transfer_history_completed_at")
    op.execute("DROP INDEX IF EXISTS idx_transfer_history_device")
    op.execute("DROP INDEX IF EXISTS idx_transfer_history_session")
    op.execute("DROP INDEX IF EXISTS idx_transfer_history_status")
    op.execute("DROP INDEX IF EXISTS idx_transfer_history_license")
    # Note: SQLite doesn't support DROP COLUMN, so we can't remove deleted_at in downgrade
    op.drop_table('transfer_history')
