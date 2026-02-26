"""Add library_attachments table for multiple attachments per item

Revision ID: 015_add_library_attachments
Revises: 014_add_library_fts
Create Date: 2026-02-26

This migration adds support for multiple attachments per library item.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '015_add_library_attachments'
down_revision: Union[str, None] = '014_add_library_fts'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create library_attachments table and indexes"""
    
    op.create_table(
        'library_attachments',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('library_item_id', sa.Integer(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('file_path', sa.Text(), nullable=False),
        sa.Column('file_size', sa.Integer(), nullable=True),
        sa.Column('mime_type', sa.String(255), nullable=True),
        sa.Column('filename', sa.String(255), nullable=True),
        sa.Column('file_hash', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('created_by', sa.Text(), nullable=True),
        sa.Column('deleted_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['library_item_id'], ['library_items.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE')
    )
    
    # Indexes for common queries
    op.execute("""
        CREATE INDEX idx_attachments_item_id
        ON library_attachments(library_item_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_attachments_license
        ON library_attachments(license_key_id)
    """)
    
    op.execute("""
        CREATE INDEX idx_attachments_deleted
        ON library_attachments(deleted_at)
    """)
    
    # Composite index for active attachments
    op.execute("""
        CREATE INDEX idx_attachments_active
        ON library_attachments(license_key_id, library_item_id, deleted_at)
    """)


def downgrade() -> None:
    """Drop library_attachments table"""
    op.execute("DROP INDEX IF EXISTS idx_attachments_active")
    op.execute("DROP INDEX IF EXISTS idx_attachments_deleted")
    op.execute("DROP INDEX IF EXISTS idx_attachments_license")
    op.execute("DROP INDEX IF EXISTS idx_attachments_item_id")
    op.drop_table('library_attachments')
