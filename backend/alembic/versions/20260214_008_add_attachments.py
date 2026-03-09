"""add attachments column to messages

Revision ID: 008_add_attachments
Revises: e6b9c9d9e9f9
Create Date: 2026-02-14 23:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '008_add_attachments'
down_revision: Union[str, None] = 'e6b9c9d9e9f9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

def upgrade() -> None:
    """Add attachments column to inbox_messages and outbox_messages"""
    connection = op.get_bind()
    
    # helper to check if column exists
    def column_exists(table, column):
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table.lower()}' AND column_name='{column.lower()}'"))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False

    # Add attachments to inbox_messages
    if not column_exists('inbox_messages', 'attachments'):
        op.execute("ALTER TABLE inbox_messages ADD COLUMN attachments TEXT")

    # Add attachments to outbox_messages
    if not column_exists('outbox_messages', 'attachments'):
        op.execute("ALTER TABLE outbox_messages ADD COLUMN attachments TEXT")


def downgrade() -> None:
    """Remove attachments column"""
    if DB_TYPE == "postgresql":
        op.execute("ALTER TABLE inbox_messages DROP COLUMN IF EXISTS attachments")
        op.execute("ALTER TABLE outbox_messages DROP COLUMN IF EXISTS attachments")
    else:
        # SQLite doesn't support DROP COLUMN easily.
        pass
