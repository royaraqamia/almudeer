"""add_chat_indexes

Revision ID: 20260226_019
Revises: 20260226_018
Create Date: 2026-02-26

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers
revision = '019_add_chat_indexes'
down_revision = '018_add_library_analytics'
branch_labels = None
depends_on = None


def upgrade():
    # FIX P1-1: Add composite indexes for faster alias resolution in chat queries
    # These indexes significantly speed up conversation loading and message threading
    
    # Index for inbox_messages sender lookup
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_sender_lookup 
        ON inbox_messages(license_key_id, sender_contact, sender_id)
    """)
    
    # Index for outbox_messages recipient lookup
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_outbox_messages_recipient_lookup 
        ON outbox_messages(license_key_id, recipient_email, recipient_id)
    """)
    
    # Index for conversation state lookups
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_conversations_license_sender 
        ON inbox_conversations(license_key_id, sender_contact)
    """)
    
    # Index for message threading (reply_to_id)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_reply_to 
        ON inbox_messages(license_key_id, reply_to_id)
        WHERE reply_to_id IS NOT NULL
    """)
    
    # Index for platform message ID lookups (deduplication)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_outbox_messages_platform_id 
        ON outbox_messages(license_key_id, channel, platform_message_id)
        WHERE platform_message_id IS NOT NULL
    """)
    
    # Index for deleted_at filtering (soft deletes)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_deleted_at 
        ON inbox_messages(license_key_id, deleted_at)
        WHERE deleted_at IS NOT NULL
    """)
    
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_outbox_messages_deleted_at 
        ON outbox_messages(license_key_id, deleted_at)
        WHERE deleted_at IS NOT NULL
    """)


def downgrade():
    # Remove indexes
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_sender_lookup")
    op.execute("DROP INDEX IF EXISTS idx_outbox_messages_recipient_lookup")
    op.execute("DROP INDEX IF EXISTS idx_inbox_conversations_license_sender")
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_reply_to")
    op.execute("DROP INDEX IF EXISTS idx_outbox_messages_platform_id")
    op.execute("DROP INDEX IF EXISTS idx_inbox_messages_deleted_at")
    op.execute("DROP INDEX IF EXISTS idx_outbox_messages_deleted_at")
