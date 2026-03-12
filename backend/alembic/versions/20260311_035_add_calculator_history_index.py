"""Add index on calculator_history for faster sync

Revision ID: 035_add_calculator_history_index
Revises: 034_add_athkar_stats_index
Create Date: 2026-03-11

"""
from alembic import op
import sqlalchemy as sa

revision = '035_add_calculator_history_index'
down_revision = '034_add_athkar_stats_index'
branch_labels = None
depends_on = None


def upgrade():
    """Add index on calculator_history column for faster sync operations"""

    # Get the database type
    from db_helper import DB_TYPE

    if DB_TYPE == "postgresql":
        # PostgreSQL - calculator_history is TEXT column (not JSONB)
        # For TEXT columns, we use a regular B-tree index which is more efficient
        # GIN indexes are for JSONB, arrays, or full-text search
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_user_preferences_calculator_history 
            ON user_preferences 
            USING BTREE (calculator_history)
        """)
    else:
        # SQLite - check if index exists first
        try:
            op.execute("CREATE INDEX IF NOT EXISTS idx_user_preferences_calculator_history ON user_preferences (calculator_history)")
        except Exception:
            pass  # Index already exists


def downgrade():
    """Remove index on calculator_history column"""
    
    from db_helper import DB_TYPE
    
    if DB_TYPE == "postgresql":
        op.execute("DROP INDEX IF EXISTS idx_user_preferences_calculator_history")
    else:
        try:
            op.execute("DROP INDEX IF EXISTS idx_user_preferences_calculator_history")
        except Exception:
            pass
