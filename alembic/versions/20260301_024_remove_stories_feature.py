"""Remove stories feature - drop all stories tables

Revision ID: 024_remove_stories_feature
Revises: 023_add_athkar_stats_column
Create Date: 2026-03-01

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '024_remove_stories_feature'
down_revision: Union[str, None] = '023_add_athkar_stats_column'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade():
    """Drop all stories-related tables and indexes."""
    
    # Drop indexes first (if they exist)
    op.execute("DROP INDEX IF EXISTS idx_stories_license")
    op.execute("DROP INDEX IF EXISTS idx_stories_created")
    op.execute("DROP INDEX IF EXISTS idx_story_views_contact")
    op.execute("DROP INDEX IF EXISTS idx_story_highlights_license")
    op.execute("DROP INDEX IF EXISTS idx_story_highlight_items_highlight")
    op.execute("DROP INDEX IF EXISTS idx_story_highlight_items_story")
    op.execute("DROP INDEX IF EXISTS idx_story_drafts_license")
    
    # Drop tables in order (respecting foreign keys)
    # 1. Drop dependent tables first
    op.execute("DROP TABLE IF EXISTS story_highlight_items")
    op.execute("DROP TABLE IF EXISTS story_views")
    op.execute("DROP TABLE IF EXISTS story_drafts")
    
    # 2. Drop main tables
    op.execute("DROP TABLE IF EXISTS story_highlights")
    op.execute("DROP TABLE IF EXISTS stories")
    
    print("Stories tables and indexes removed successfully")


def downgrade():
    """Restore stories tables (not recommended - data will be lost)."""
    
    # Note: Downgrade will create empty tables. Data cannot be restored.
    
    ID_PK = "SERIAL PRIMARY KEY" if op.get_context().dialect.name == "postgresql" else "INTEGER PRIMARY KEY AUTOINCREMENT"
    TIMESTAMP_NOW = "TIMESTAMP DEFAULT NOW()" if op.get_context().dialect.name == "postgresql" else "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
    
    # Recreate stories table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS stories (
            id {ID_PK},
            license_key_id INTEGER NOT NULL,
            user_id TEXT,
            user_name TEXT,
            type TEXT NOT NULL,
            title TEXT,
            content TEXT,
            media_path TEXT,
            thumbnail_path TEXT,
            duration_ms INTEGER DEFAULT 0,
            created_at {TIMESTAMP_NOW},
            expires_at {TIMESTAMP_NOW},
            updated_at {TIMESTAMP_NOW},
            deleted_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)
    
    # Recreate story_views table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS story_views (
            id {ID_PK},
            story_id INTEGER NOT NULL,
            viewer_contact TEXT NOT NULL,
            viewer_name TEXT,
            viewed_at {TIMESTAMP_NOW},
            UNIQUE(story_id, viewer_contact),
            FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE
        )
    """)
    
    # Recreate story_highlights table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS story_highlights (
            id {ID_PK},
            license_key_id INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            cover_media_path TEXT,
            created_at {TIMESTAMP_NOW},
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)
    
    # Recreate story_highlight_items table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS story_highlight_items (
            id {ID_PK},
            highlight_id INTEGER NOT NULL,
            story_id INTEGER NOT NULL,
            position INTEGER DEFAULT 0,
            added_at {TIMESTAMP_NOW},
            UNIQUE(highlight_id, story_id),
            FOREIGN KEY (highlight_id) REFERENCES story_highlights(id) ON DELETE CASCADE,
            FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE
        )
    """)
    
    # Recreate story_drafts table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS story_drafts (
            id {ID_PK},
            license_key_id INTEGER NOT NULL,
            user_id TEXT,
            type TEXT NOT NULL,
            title TEXT,
            content TEXT,
            media_path TEXT,
            thumbnail_path TEXT,
            duration_ms INTEGER DEFAULT 0,
            created_at {TIMESTAMP_NOW},
            updated_at {TIMESTAMP_NOW},
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)
    
    # Recreate indexes
    op.execute("CREATE INDEX IF NOT EXISTS idx_stories_license ON stories(license_key_id)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_stories_created ON stories(created_at)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_story_views_contact ON story_views(viewer_contact)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_story_highlights_license ON story_highlights(license_key_id)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_story_highlight_items_highlight ON story_highlight_items(highlight_id)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_story_highlight_items_story ON story_highlight_items(story_id)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_story_drafts_license ON story_drafts(license_key_id)")
    
    print("Stories tables restored (empty - data lost)")
