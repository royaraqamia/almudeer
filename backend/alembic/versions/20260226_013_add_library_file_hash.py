"""Add file_hash column to library_items for deduplication

Revision ID: 013_add_library_file_hash
Revises: 012_add_library_download_logs
Create Date: 2026-02-26

This migration adds a file_hash column to library_items for
file deduplication and integrity verification.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '013_add_library_file_hash'
down_revision: Union[str, None] = '012_add_library_download_logs'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Add file_hash column to library_items table"""
    
    # Add file_hash column
    op.execute("""
        ALTER TABLE library_items ADD COLUMN file_hash TEXT
    """)
    
    # Create index for deduplication queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_file_hash
        ON library_items(file_hash)
    """)
    
    # Create composite index for license + hash deduplication
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_license_hash
        ON library_items(license_key_id, file_hash)
    """)


def downgrade() -> None:
    """Drop file_hash column and indexes"""
    
    # Drop indexes
    op.execute("DROP INDEX IF EXISTS idx_library_license_hash")
    op.execute("DROP INDEX IF EXISTS idx_library_file_hash")
    
    # Note: SQLite doesn't support DROP COLUMN directly
    # For PostgreSQL, uncomment below:
    # op.execute("ALTER TABLE library_items DROP COLUMN IF EXISTS file_hash")
