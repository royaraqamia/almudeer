"""Add username to customers

Revision ID: 005_add_username_to_customers
Revises: 004_fix_outbox_columns
Create Date: 2026-02-06

This migration adds the username column to the customers table.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '005_add_username_to_customers'
down_revision: Union[str, None] = '004_fix_outbox_columns'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Add username column to customers"""
    
    # helper to check if column exists
    def column_exists(table, column):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table}' AND column_name='{column}'"))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False

    if not column_exists('customers', 'username'):
        op.execute("ALTER TABLE customers ADD COLUMN username TEXT")


def downgrade() -> None:
    """Remove the added column (caution: destructive)"""
    if DB_TYPE == "postgresql":
        op.execute("ALTER TABLE customers DROP COLUMN IF EXISTS username")
    # SQLite doesn't support DROP COLUMN easily
