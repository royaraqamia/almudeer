"""Add quran_progress and calculator_history columns to user_preferences table

Revision ID: 028_add_quran_calc_history
Revises: 027_remove_stories_feature
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa

revision = '028_add_quran_calc_history'
down_revision = '027_remove_stories_feature'
branch_labels = None
depends_on = None


def upgrade():
    """Add quran_progress and calculator_history columns to user_preferences table"""
    
    # Get the database type
    from db_helper import DB_TYPE
    
    if DB_TYPE == "postgresql":
        # PostgreSQL - use IF NOT EXISTS
        op.execute("ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS quran_progress TEXT")
        op.execute("ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS calculator_history TEXT")
    else:
        # SQLite - check if column exists first
        try:
            op.execute("ALTER TABLE user_preferences ADD COLUMN quran_progress TEXT")
        except Exception:
            pass  # Column already exists
        
        try:
            op.execute("ALTER TABLE user_preferences ADD COLUMN calculator_history TEXT")
        except Exception:
            pass  # Column already exists


def downgrade():
    """Remove quran_progress and calculator_history columns from user_preferences table"""
    
    from db_helper import DB_TYPE
    
    if DB_TYPE == "postgresql":
        op.execute("ALTER TABLE user_preferences DROP COLUMN IF EXISTS quran_progress")
        op.execute("ALTER TABLE user_preferences DROP COLUMN IF EXISTS calculator_history")
    else:
        # SQLite doesn't support DROP COLUMN in older versions
        # These columns will remain if SQLite version doesn't support it
        try:
            op.execute("ALTER TABLE user_preferences DROP COLUMN quran_progress")
        except Exception:
            pass
        
        try:
            op.execute("ALTER TABLE user_preferences DROP COLUMN calculator_history")
        except Exception:
            pass
