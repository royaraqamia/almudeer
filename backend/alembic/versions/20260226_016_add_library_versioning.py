"""Add library_item_versions for version history tracking

Revision ID: 016_add_library_versioning
Revises: 015_add_library_attachments
Create Date: 2026-02-26

P3-13: Track version history of library items (notes especially)

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '016_add_library_versioning'
down_revision: Union[str, None] = '015_add_library_attachments'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create library_item_versions table and indexes"""
    
    op.create_table(
        'library_item_versions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('item_id', sa.Integer(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False, default=1),
        sa.Column('title', sa.Text(), nullable=True),
        sa.Column('content', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('created_by', sa.Text(), nullable=True),
        sa.Column('change_summary', sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['item_id'], ['library_items.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE')
    )
    
    # Indexes for common queries
    op.execute("""
        CREATE INDEX idx_versions_item_id
        ON library_item_versions(item_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_versions_item_version
        ON library_item_versions(item_id, version DESC)
    """)
    
    op.execute("""
        CREATE INDEX idx_versions_license
        ON library_item_versions(license_key_id)
    """)
    
    # Add version column to library_items for tracking current version
    op.execute("""
        ALTER TABLE library_items ADD COLUMN version INTEGER DEFAULT 1
    """)
    
    op.execute("""
        CREATE INDEX idx_library_version
        ON library_items(version)
    """)


def downgrade() -> None:
    """Drop library_item_versions table and remove version column"""
    op.execute("DROP INDEX IF EXISTS idx_library_version")
    op.execute("ALTER TABLE library_items DROP COLUMN version")
    op.execute("DROP INDEX IF EXISTS idx_versions_license")
    op.execute("DROP INDEX IF EXISTS idx_versions_item_version")
    op.execute("DROP INDEX IF EXISTS idx_versions_item_id")
    op.drop_table('library_item_versions')
