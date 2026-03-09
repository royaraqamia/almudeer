"""Add athkar_stats column to user_preferences table

Revision ID: 026_add_athkar_stats_column
Revises: 025_add_transfer_history
Create Date: 2026-02-28

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '026_add_athkar_stats_column'
down_revision: Union[str, None] = '025_add_transfer_history'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Add athkar_stats column to user_preferences table"""
    
    # Check if column already exists (for safety)
    if DB_TYPE == "postgresql":
        # PostgreSQL: check if column exists before adding
        op.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'user_preferences'
                    AND column_name = 'athkar_stats'
                ) THEN
                    ALTER TABLE user_preferences ADD COLUMN athkar_stats TEXT;
                END IF;
            END
            $$;
        """)
    else:
        # SQLite: ALTER TABLE ADD COLUMN is safe even if column exists (will error if exists)
        # We use a conditional approach to handle both fresh installs and existing DBs
        try:
            op.execute("ALTER TABLE user_preferences ADD COLUMN athkar_stats TEXT")
        except Exception:
            # Column might already exist, ignore error
            pass


def downgrade() -> None:
    """Remove athkar_stats column from user_preferences table"""
    if DB_TYPE == "postgresql":
        op.execute("""
            ALTER TABLE user_preferences DROP COLUMN IF EXISTS athkar_stats;
        """)
    else:
        # SQLite doesn't support DROP COLUMN in older versions
        # For simplicity, we skip the downgrade on SQLite
        pass
