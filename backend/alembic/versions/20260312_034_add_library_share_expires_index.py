"""Add index on library_shares(expires_at) for expiration cleanup worker

Revision ID: 034_add_library_share_expires_index
Revises: 033_merge_library_and_task_indexes
Create Date: 2026-03-12

Production Readiness Fix: Add index for efficient share expiration queries.
The cleanup worker needs to find expired shares efficiently:
  WHERE expires_at IS NOT NULL AND expires_at < ? AND deleted_at IS NULL

This index prevents full table scans during expiration cleanup.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '034_add_library_share_expires_index'
down_revision: Union[str, None] = '033_merge_library_and_task_indexes'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add index on expires_at for expiration cleanup"""

    # Index for efficient expiration queries
    # Used by cleanup worker to find expired shares
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_expires_at
        ON library_shares(expires_at)
        WHERE expires_at IS NOT NULL AND deleted_at IS NULL
    """)

    # Composite index for queries that filter by license and expiration
    # Useful for license-specific expiration reports
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_license_expires_at
        ON library_shares(license_key_id, expires_at)
        WHERE expires_at IS NOT NULL AND deleted_at IS NULL
    """)


def downgrade() -> None:
    """Remove the expiration indexes"""
    op.execute("DROP INDEX IF EXISTS idx_shares_license_expires_at")
    op.execute("DROP INDEX IF EXISTS idx_shares_expires_at")
