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
import os

revision: str = '014_add_library_fts'
down_revision: Union[str, None] = '013_add_library_file_hash'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Add full-text search virtual table and triggers for library_items"""

    if DB_TYPE == "postgresql":
        # PostgreSQL: Add tsvector column and GIN index
        op.execute("""
            ALTER TABLE library_items 
            ADD COLUMN IF NOT EXISTS search_vector tsvector
        """)
        
        # Populate search_vector column
        op.execute("""
            UPDATE library_items 
            SET search_vector = to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(content, ''))
            WHERE search_vector IS NULL
        """)
        
        # Create GIN index for fast search
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_library_items_search_vector 
            ON library_items USING GIN(search_vector)
        """)
        
        # Create function and triggers to keep search_vector in sync
        op.execute("""
            CREATE OR REPLACE FUNCTION library_items_search_vector_update() RETURNS trigger AS $$
            BEGIN
                NEW.search_vector := to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, ''));
                RETURN NEW;
            END
            $$ LANGUAGE plpgsql
        """)
        
        op.execute("""
            CREATE TRIGGER library_items_search_vector_insert 
            BEFORE INSERT ON library_items
            FOR EACH ROW EXECUTE FUNCTION library_items_search_vector_update()
        """)
        
        op.execute("""
            CREATE TRIGGER library_items_search_vector_update 
            BEFORE UPDATE ON library_items
            FOR EACH ROW EXECUTE FUNCTION library_items_search_vector_update()
        """)
    else:
        # SQLite: Create FTS5 virtual table
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

    if DB_TYPE == "postgresql":
        # Drop triggers
        op.execute("DROP TRIGGER IF EXISTS library_items_search_vector_insert ON library_items")
        op.execute("DROP TRIGGER IF EXISTS library_items_search_vector_update ON library_items")
        op.execute("DROP FUNCTION IF EXISTS library_items_search_vector_update()")
        
        # Drop index
        op.execute("DROP INDEX IF EXISTS idx_library_items_search_vector")
        
        # Drop column
        op.execute("ALTER TABLE library_items DROP COLUMN IF EXISTS search_vector")
    else:
        # SQLite: Drop triggers and FTS table
        op.execute("DROP TRIGGER IF EXISTS library_items_ai")
        op.execute("DROP TRIGGER IF EXISTS library_items_ad")
        op.execute("DROP TRIGGER IF EXISTS library_items_au")
        op.execute("DROP TABLE IF EXISTS library_items_fts")
