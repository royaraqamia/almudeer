"""
Al-Mudeer - Database Migration for Share Features

P3-14: Library Sharing
- Add updated_at column to library_shares
- Add database indexes for performance
"""

from alembic import op
import sqlalchemy as sa
from datetime import datetime, timezone

revision: str = '20260226_019_add_share_features'
down_revision: str = '018_add_library_analytics'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add share-related database enhancements"""
    
    # Add updated_at column to library_shares
    op.execute("""
        ALTER TABLE library_shares ADD COLUMN updated_at TIMESTAMP
    """)
    
    # Add composite index for share permission queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_active_user
        ON library_shares(license_key_id, shared_with_user_id, deleted_at)
        WHERE deleted_at IS NULL
    """)
    
    # Add index for expiration queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_expires_at
        ON library_shares(expires_at)
        WHERE deleted_at IS NULL
    """)
    
    # Add index for share creator queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_created_by
        ON library_shares(created_by)
    """)
    
    print("Share features database migration completed")


def downgrade() -> None:
    """Remove share-related database enhancements"""
    op.execute("DROP INDEX IF EXISTS idx_shares_created_by")
    op.execute("DROP INDEX IF EXISTS idx_shares_expires_at")
    op.execute("DROP INDEX IF EXISTS idx_shares_active_user")
    op.execute("ALTER TABLE library_shares DROP COLUMN updated_at")
