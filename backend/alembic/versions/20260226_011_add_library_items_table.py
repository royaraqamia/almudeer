"""Add library_items table and indexes

Revision ID: 011_add_library_items
Revises: 010_add_search_vector
Create Date: 2026-02-26

This migration creates the library_items table for storing notes, images,
files, audio, and video content with proper indexing for performance.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '011_add_library_items'
down_revision: Union[str, None] = '010_add_search_vector'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Create library_items table and indexes"""
    
    # Helper for DB-specific syntax
    if DB_TYPE == "postgresql":
        id_pk = "SERIAL PRIMARY KEY"
        timestamp_now = "TIMESTAMP DEFAULT NOW()"
    else:
        id_pk = "INTEGER PRIMARY KEY AUTOINCREMENT"
        timestamp_now = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
    
    # Create library_items table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS library_items (
            id {id_pk},
            license_key_id INTEGER NOT NULL,
            user_id TEXT,
            customer_id INTEGER,
            type TEXT NOT NULL,
            title TEXT,
            content TEXT,
            file_path TEXT,
            file_size INTEGER,
            mime_type TEXT,
            created_at {timestamp_now},
            updated_at {timestamp_now},
            deleted_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
            FOREIGN KEY (customer_id) REFERENCES customers(id)
        )
    """)
    
    # Create performance indexes
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_license_customer
        ON library_items(license_key_id, customer_id)
    """)
    
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_user
        ON library_items(license_key_id, user_id)
    """)
    
    # Index for soft-delete filtering
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_deleted_at
        ON library_items(deleted_at)
    """)
    
    # Composite index for common query patterns
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_active_user_type
        ON library_items(license_key_id, user_id, deleted_at, type)
    """)
    
    # Index on type column for filtering
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_type
        ON library_items(type)
    """)
    
    # PostgreSQL partial index for active items
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_library_active_items
            ON library_items(license_key_id, deleted_at)
            WHERE deleted_at IS NULL
        """)


def downgrade() -> None:
    """Drop library_items table and indexes"""
    
    # Drop indexes first
    op.execute("DROP INDEX IF EXISTS idx_library_active_items")
    op.execute("DROP INDEX IF EXISTS idx_library_type")
    op.execute("DROP INDEX IF EXISTS idx_library_active_user_type")
    op.execute("DROP INDEX IF EXISTS idx_library_deleted_at")
    op.execute("DROP INDEX IF EXISTS idx_library_user")
    op.execute("DROP INDEX IF EXISTS idx_library_license_customer")
    
    # Drop table
    op.execute("DROP TABLE IF EXISTS library_items")
