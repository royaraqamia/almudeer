"""add last_message_attachments to inbox_conversations

Revision ID: 009_add_conversation_attachments
Revises: 008_add_attachments
Create Date: 2026-02-15 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '009_add_conversation_attachments'
down_revision: Union[str, None] = '008_add_attachments'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

def upgrade() -> None:
    """Add last_message_attachments column to inbox_conversations"""
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

    # Add last_message_attachments to inbox_conversations
    if not column_exists('inbox_conversations', 'last_message_attachments'):
        op.execute("ALTER TABLE inbox_conversations ADD COLUMN last_message_attachments TEXT")


def downgrade() -> None:
    """Remove last_message_attachments column"""
    if DB_TYPE == "postgresql":
        op.execute("ALTER TABLE inbox_conversations DROP COLUMN IF EXISTS last_message_attachments")
    else:
        # SQLite doesn't support DROP COLUMN easily.
        pass
