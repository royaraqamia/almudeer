"""Add library_shares for sharing items with other users

Revision ID: 017_add_library_sharing
Revises: 016_add_library_versioning
Create Date: 2026-02-26

P3-14: Share library items with other users with read/edit permissions

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '017_add_library_sharing'
down_revision: Union[str, None] = '016_add_library_versioning'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create library_shares table and indexes"""
    
    op.create_table(
        'library_shares',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('item_id', sa.Integer(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('shared_with_user_id', sa.Text(), nullable=False),
        sa.Column('permission', sa.String(20), nullable=False, default='read'),
        # permission: 'read', 'edit', 'admin'
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('created_by', sa.Text(), nullable=True),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('deleted_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['item_id'], ['library_items.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('item_id', 'shared_with_user_id', name='uq_share_item_user')
    )
    
    # Indexes for common queries
    op.execute("""
        CREATE INDEX idx_shares_item_id
        ON library_shares(item_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_shares_user_id
        ON library_shares(shared_with_user_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_shares_license
        ON library_shares(license_key_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_shares_active
        ON library_shares(license_key_id, item_id, deleted_at)
        WHERE deleted_at IS NULL
    """)
    
    # Add shared_with_me view optimization - add index to library_items for shared items
    op.execute("""
        ALTER TABLE library_items ADD COLUMN is_shared INTEGER DEFAULT 0
    """)
    
    op.execute("""
        CREATE INDEX idx_library_is_shared
        ON library_items(is_shared)
    """)


def downgrade() -> None:
    """Drop library_shares table and remove is_shared column"""
    op.execute("DROP INDEX IF EXISTS idx_library_is_shared")
    op.execute("ALTER TABLE library_items DROP COLUMN is_shared")
    op.execute("DROP INDEX IF EXISTS idx_shares_active")
    op.execute("DROP INDEX IF EXISTS idx_shares_license")
    op.execute("DROP INDEX IF EXISTS idx_shares_user_id")
    op.execute("DROP INDEX IF EXISTS idx_shares_item_id")
    op.drop_table('library_shares')
