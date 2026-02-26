"""Add full-text search to library_items for better search performance

Revision ID: 014_add_library_fts
Revises: 013_add_library_file_hash
Create Date: 2026-02-26

This migration adds FTS5 virtual table for library_items to enable
fast full-text search capabilities.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '014_add_library_fts'
down_revision: Union[str, None] = '013_add_library_file_hash'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add full-text search virtual table and triggers for library_items"""
    
    # Create FTS5 virtual table
    op.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS library_items_fts USING fts5(
            title, 
            content,
            content='library_items',
            content_rowid='id'
        )
    """)
    
    # Create triggers to keep FTS index in sync with library_items
    # Trigger for INSERT
    op.execute("""
        CREATE TRIGGER IF NOT EXISTS library_items_ai AFTER INSERT ON library_items BEGIN
            INSERT INTO library_items_fts(rowid, title, content)
            VALUES (new.id, new.title, new.content);
        END
    """)
    
    # Trigger for DELETE
    op.execute("""
        CREATE TRIGGER IF NOT EXISTS library_items_ad AFTER DELETE ON library_items BEGIN
            INSERT INTO library_items_fts(library_items_fts, rowid, title, content) 
            VALUES('delete', old.id, old.title, old.content);
        END
    """)
    
    # Trigger for UPDATE
    op.execute("""
        CREATE TRIGGER IF NOT EXISTS library_items_au AFTER UPDATE ON library_items BEGIN
            INSERT INTO library_items_fts(library_items_fts, rowid, title, content) 
            VALUES('delete', old.id, old.title, old.content);
            INSERT INTO library_items_fts(rowid, title, content) 
            VALUES (new.id, new.title, new.content);
        END
    """)
    
    # Populate FTS table with existing data
    op.execute("""
        INSERT INTO library_items_fts(rowid, title, content)
        SELECT id, title, content FROM library_items
        WHERE deleted_at IS NULL
    """)


def downgrade() -> None:
    """Remove full-text search virtual table and triggers"""
    
    # Drop triggers
    op.execute("DROP TRIGGER IF EXISTS library_items_ai")
    op.execute("DROP TRIGGER IF EXISTS library_items_ad")
    op.execute("DROP TRIGGER IF EXISTS library_items_au")
    
    # Drop FTS table
    op.execute("DROP TABLE IF EXISTS library_items_fts")
