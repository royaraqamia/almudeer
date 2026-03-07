"""Add reply_count to inbox_messages and outbox_messages tables

Revision ID: 030_add_reply_count
Revises: 029_add_task_sharing
Create Date: 2026-03-07

"""
from alembic import op
import sqlalchemy as sa

revision = '030_add_reply_count'
down_revision = '029_add_task_sharing'
branch_labels = None
depends_on = None


def upgrade():
    """Add reply_count column to inbox_messages and outbox_messages tables"""

    from db_helper import DB_TYPE

    if DB_TYPE == "postgresql":
        # PostgreSQL - use IF NOT EXISTS
        op.execute("ALTER TABLE inbox_messages ADD COLUMN IF NOT EXISTS reply_count INTEGER DEFAULT 0")
        op.execute("ALTER TABLE outbox_messages ADD COLUMN IF NOT EXISTS reply_count INTEGER DEFAULT 0")
        
        # Add index for faster lookup of messages with replies
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_inbox_messages_reply_count
            ON inbox_messages(license_key_id, reply_count)
            WHERE reply_count > 0
        """)
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_outbox_messages_reply_count
            ON outbox_messages(license_key_id, reply_count)
            WHERE reply_count > 0
        """)
    else:
        # SQLite - check if column exists first
        try:
            op.execute("ALTER TABLE inbox_messages ADD COLUMN reply_count INTEGER DEFAULT 0")
        except Exception:
            pass  # Column already exists

        try:
            op.execute("ALTER TABLE outbox_messages ADD COLUMN reply_count INTEGER DEFAULT 0")
        except Exception:
            pass  # Column already exists


def downgrade():
    """Remove reply_count columns from inbox_messages and outbox_messages tables"""

    from db_helper import DB_TYPE

    if DB_TYPE == "postgresql":
        op.execute("DROP INDEX IF EXISTS idx_inbox_messages_reply_count")
        op.execute("DROP INDEX IF EXISTS idx_outbox_messages_reply_count")
        op.execute("ALTER TABLE inbox_messages DROP COLUMN IF EXISTS reply_count")
        op.execute("ALTER TABLE outbox_messages DROP COLUMN IF EXISTS reply_count")
    else:
        # SQLite doesn't support DROP COLUMN in older versions
        try:
            op.execute("ALTER TABLE inbox_messages DROP COLUMN reply_count")
        except Exception:
            pass

        try:
            op.execute("ALTER TABLE outbox_messages DROP COLUMN reply_count")
        except Exception:
            pass
