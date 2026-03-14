"""Add created_by column to library_items and backfill

Revision ID: 039_add_library_items_created_by
Revises: 038_make_sender_contact_nullable
Create Date: 2026-03-14

Fix: Add created_by column to library_items table and backfill existing data.
This ensures proper ownership tracking for library items when deleting.
"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '039_add_library_items_created_by'
down_revision: Union[str, None] = '038_make_sender_contact_nullable'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add created_by column to library_items and backfill existing data"""
    
    # Use PostgreSQL's DO block to conditionally add column if it doesn't exist
    op.execute("""
        DO $$ 
        BEGIN 
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'library_items' AND column_name = 'created_by'
            ) THEN
                ALTER TABLE library_items ADD COLUMN created_by TEXT;
            END IF;
        END $$;
    """)

    # Create index for performance on ownership checks
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_created_by
        ON library_items(created_by)
    """)

    # Backfill: Set created_by = user_id for existing items where created_by is NULL
    # This ensures existing items have proper ownership set
    op.execute("""
        UPDATE library_items
        SET created_by = user_id
        WHERE created_by IS NULL AND user_id IS NOT NULL
    """)


def downgrade() -> None:
    """Remove created_by column from library_items"""
    op.execute("DROP INDEX IF EXISTS idx_library_created_by")
    op.execute("ALTER TABLE library_items DROP COLUMN created_by")
