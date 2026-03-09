"""add is_forwarded to messages

Revision ID: e6b9c9d9e9f9
Revises: d3c68aa953d0
Create Date: 2026-02-10 09:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = 'e6b9c9d9e9f9'
down_revision: Union[str, None] = 'd3c68aa953d0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

def upgrade() -> None:
    """Add is_forwarded column to inbox_messages and outbox_messages"""
    connection = op.get_bind()
    
    # helper to check if column exists
    def column_exists(table, column):
        if DB_TYPE == "postgresql":
            # PostgreSQL uses lowercase for table names in information_schema
            res = connection.execute(sa.text(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table.lower()}' AND column_name='{column.lower()}'"))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False

    # Add is_forwarded to inbox_messages
    if not column_exists('inbox_messages', 'is_forwarded'):
        if DB_TYPE == "postgresql":
            op.execute("ALTER TABLE inbox_messages ADD COLUMN is_forwarded BOOLEAN DEFAULT FALSE")
        else:
            op.execute("ALTER TABLE inbox_messages ADD COLUMN is_forwarded BOOLEAN DEFAULT 0")

    # Add is_forwarded to outbox_messages
    if not column_exists('outbox_messages', 'is_forwarded'):
        if DB_TYPE == "postgresql":
            op.execute("ALTER TABLE outbox_messages ADD COLUMN is_forwarded BOOLEAN DEFAULT FALSE")
        else:
            op.execute("ALTER TABLE outbox_messages ADD COLUMN is_forwarded BOOLEAN DEFAULT 0")


def downgrade() -> None:
    """Remove is_forwarded column"""
    if DB_TYPE == "postgresql":
        op.execute("ALTER TABLE inbox_messages DROP COLUMN IF EXISTS is_forwarded")
        op.execute("ALTER TABLE outbox_messages DROP COLUMN IF EXISTS is_forwarded")
    else:
        # SQLite doesn't support DROP COLUMN easily.
        pass
