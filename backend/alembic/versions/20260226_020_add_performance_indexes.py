"""Add performance indexes for conversation features

Revision ID: 020_add_performance_indexes
Revises: 019_add_chat_indexes
Create Date: 2026-02-26

"""
from alembic import op
import sqlalchemy as sa
import os

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


# revision identifiers, used by Alembic.
revision = '020_add_performance_indexes'
down_revision = '019_add_chat_indexes'
branch_labels = None
depends_on = None


def upgrade():
    # P1-2: Index for message threading (reply_to_id) - if not already exists
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_reply_to_lookup
        ON inbox_messages(license_key_id, reply_to_id)
        WHERE reply_to_id IS NOT NULL
    """)

    # P1-2: Index for outbox message threading
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_outbox_messages_reply_to_lookup
        ON outbox_messages(license_key_id, reply_to_id)
        WHERE reply_to_id IS NOT NULL
    """)

    # P1-1: Composite index for conversation list with online status
    # Note: INCLUDE is PostgreSQL-specific, use regular composite index for SQLite
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_inbox_conversations_online_lookup
            ON inbox_conversations(license_key_id, last_message_at DESC)
            INCLUDE (sender_contact, sender_name, channel, unread_count)
        """)
    else:
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_inbox_conversations_online_lookup
            ON inbox_conversations(license_key_id, last_message_at DESC, sender_contact, sender_name, channel, unread_count)
        """)

    # P1-8: Index for attachment queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_attachments
        ON inbox_messages(license_key_id, id)
        WHERE attachments IS NOT NULL
    """)

    # P1-3: Index for sender alias lookups
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_sender_id_lookup
        ON inbox_messages(license_key_id, sender_id, sender_contact)
    """)

    # P1-3: Index for outbox recipient lookups
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_outbox_messages_recipient_id_lookup
        ON outbox_messages(license_key_id, recipient_id, recipient_email)
    """)

    # P2-1: Index for read receipts synchronization
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_read_status
        ON inbox_messages(license_key_id, sender_contact, status)
        WHERE deleted_at IS NULL
    """)

    # P2-6: Index for draft synchronization
    # Note: INCLUDE is PostgreSQL-specific
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_conversations_draft
            ON inbox_conversations(license_key_id, sender_contact)
            INCLUDE (last_message_body, last_message_at)
        """)
    else:
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_conversations_draft
            ON inbox_conversations(license_key_id, sender_contact, last_message_body, last_message_at)
        """)


def downgrade():
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_reply_to_lookup")
    op.execute("DROP INDEX IF EXISTS idx_outbox_messages_reply_to_lookup")
    op.execute("DROP INDEX IF EXISTS idx_inbox_conversations_online_lookup")
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_attachments")
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_sender_id_lookup")
    op.execute("DROP INDEX IF EXISTS idx_outbox_messages_recipient_id_lookup")
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_read_status")
    op.execute("DROP INDEX IF EXISTS idx_conversations_draft")
