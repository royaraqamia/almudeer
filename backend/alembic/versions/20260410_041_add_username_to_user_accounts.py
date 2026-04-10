"""Add username to user_accounts

Revision ID: 041_add_username_to_user_accounts
Revises: 040_add_email_auth
Create Date: 2026-04-10

This migration adds the username column to the user_accounts table.
Username is required for user identification and must be unique.
"""
from typing import Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '041_add_username_to_user_accounts'
down_revision: Union[str, None] = '040_add_email_auth'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Add username column to user_accounts"""

    # Helper to check if column exists
    def column_exists(table, column):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT column_name FROM information_schema.columns "
                f"WHERE table_name='{table}' AND column_name='{column}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False

    # Add username column if it doesn't exist
    if not column_exists('user_accounts', 'username'):
        if DB_TYPE == "postgresql":
            op.execute("ALTER TABLE user_accounts ADD COLUMN username VARCHAR(50)")
        else:
            op.execute("ALTER TABLE user_accounts ADD COLUMN username TEXT")

    # Create unique index on username for performance and uniqueness
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_user_accounts_username
        ON user_accounts(username)
        WHERE username IS NOT NULL;
    """)


def downgrade() -> None:
    """Remove the username column (caution: destructive)"""
    
    # Drop index
    op.execute("DROP INDEX IF EXISTS idx_user_accounts_username")
    
    if DB_TYPE == "postgresql":
        op.execute("ALTER TABLE user_accounts DROP COLUMN IF EXISTS username")
    # SQLite doesn't support DROP COLUMN easily
