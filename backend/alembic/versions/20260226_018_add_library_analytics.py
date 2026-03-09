"""Add analytics tracking to library_items

Revision ID: 018_add_library_analytics
Revises: 017_add_library_sharing
Create Date: 2026-02-26

P3-15: Track access patterns and usage analytics for library items

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '018_add_library_analytics'
down_revision: Union[str, None] = '017_add_library_sharing'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add analytics columns to library_items and create library_analytics table"""
    
    # Add analytics columns to library_items
    op.execute("""
        ALTER TABLE library_items ADD COLUMN last_accessed_at TIMESTAMP
    """)
    
    op.execute("""
        ALTER TABLE library_items ADD COLUMN access_count INTEGER DEFAULT 0
    """)
    
    op.execute("""
        ALTER TABLE library_items ADD COLUMN download_count INTEGER DEFAULT 0
    """)
    
    # Create detailed analytics tracking table
    op.create_table(
        'library_analytics',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('item_id', sa.Integer(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Text(), nullable=True),
        sa.Column('action', sa.String(50), nullable=False),
        # actions: 'view', 'download', 'edit', 'share', 'delete'
        sa.Column('timestamp', sa.DateTime(), nullable=True),
        sa.Column('client_ip', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.Text(), nullable=True),
        sa.Column('metadata', sa.Text(), nullable=True),  # JSON metadata
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['item_id'], ['library_items.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE')
    )
    
    # Indexes for analytics queries
    op.execute("""
        CREATE INDEX idx_analytics_item_id
        ON library_analytics(item_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_analytics_timestamp
        ON library_analytics(timestamp DESC)
    """)
    
    op.execute("""
        CREATE INDEX idx_analytics_action
        ON library_analytics(action)
    """)
    
    op.execute("""
        CREATE INDEX idx_analytics_license_timestamp
        ON library_analytics(license_key_id, timestamp DESC)
    """)
    
    # Indexes for library_items analytics columns
    op.execute("""
        CREATE INDEX idx_library_last_accessed
        ON library_items(last_accessed_at DESC)
    """)
    
    op.execute("""
        CREATE INDEX idx_library_access_count
        ON library_items(access_count DESC)
    """)


def downgrade() -> None:
    """Remove analytics columns and table"""
    op.execute("DROP INDEX IF EXISTS idx_library_access_count")
    op.execute("DROP INDEX IF EXISTS idx_library_last_accessed")
    op.execute("DROP INDEX IF EXISTS idx_analytics_license_timestamp")
    op.execute("DROP INDEX IF EXISTS idx_analytics_action")
    op.execute("DROP INDEX IF EXISTS idx_analytics_timestamp")
    op.execute("DROP INDEX IF EXISTS idx_analytics_item_id")
    op.drop_table('library_analytics')
    op.execute("ALTER TABLE library_items DROP COLUMN download_count")
    op.execute("ALTER TABLE library_items DROP COLUMN access_count")
    op.execute("ALTER TABLE library_items DROP COLUMN last_accessed_at")
