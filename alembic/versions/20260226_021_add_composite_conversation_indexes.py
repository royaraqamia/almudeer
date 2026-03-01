"""
P3-14 FIX: Add composite indexes for conversation-related queries
Improves performance for users with many messages
"""

from alembic import op
import sqlalchemy as sa
import os

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


# Revision identifiers
revision = '021_add_composite_conversation_indexes'
down_revision = '020_add_performance_indexes'  # Update this to match your previous migration
branch_labels = None
depends_on = None


def upgrade():
    # P3-14 FIX: Composite index for conversation message loading
    # Optimizes: SELECT * FROM inbox_messages WHERE license_key_id = ? AND sender_contact = ? ORDER BY created_at DESC
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_messages_license_contact_created
        ON inbox_messages(license_key_id, sender_contact, created_at)
    """)

    # P3-14 FIX: Composite index for outbox message loading
    # Optimizes: SELECT * FROM outbox_messages WHERE license_key_id = ? AND recipient_email = ? ORDER BY created_at DESC
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_outbox_messages_license_recipient_created
        ON outbox_messages(license_key_id, recipient_email, created_at)
    """)

    # P3-14 FIX: Composite index for conversation state updates
    # Optimizes: UPDATE inbox_conversations SET unread_count = ? WHERE license_key_id = ? AND sender_contact = ?
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_inbox_conversations_license_contact
        ON inbox_conversations(license_key_id, sender_contact)
    """)

    # P3-14 FIX: Index for retry count filtering (P1-6 FIX support)
    # Note: retry_count column is added in a later migration, so we create this index conditionally
    # For SQLite, skip if column doesn't exist; for PostgreSQL, it will be created later
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_outbox_messages_status_retry
            ON outbox_messages(status, retry_count, created_at)
        """)

    # P3-14 FIX: Index for message search within conversation
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_inbox_messages_contact_body
            ON inbox_messages(license_key_id, sender_contact)
            INCLUDE (body, created_at)
        """)
    else:
        op.execute("""
            CREATE INDEX IF NOT EXISTS idx_inbox_messages_contact_body
            ON inbox_messages(license_key_id, sender_contact, body, created_at)
        """)


def downgrade():
    op.drop_index('idx_inbox_messages_contact_body', table_name='inbox_messages')
    op.drop_index('idx_outbox_messages_status_retry', table_name='outbox_messages')
    op.drop_index('idx_inbox_conversations_license_contact', table_name='inbox_conversations')
    op.drop_index('idx_outbox_messages_license_recipient_created', table_name='outbox_messages')
    op.drop_index('idx_inbox_messages_license_contact_created', table_name='inbox_messages')
