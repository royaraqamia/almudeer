"""
P3-14 FIX: Add composite indexes for conversation-related queries
Improves performance for users with many messages
"""

from alembic import op
import sqlalchemy as sa


# Revision identifiers
revision = '20260226_021_add_composite_conversation_indexes'
down_revision = '20260226_020_add_performance_indexes'  # Update this to match your previous migration
branch_labels = None
depends_on = None


def upgrade():
    # P3-14 FIX: Composite index for conversation message loading
    # Optimizes: SELECT * FROM inbox_messages WHERE license_key_id = ? AND sender_contact = ? ORDER BY created_at DESC
    op.create_index(
        'idx_inbox_messages_license_contact_created',
        'inbox_messages',
        ['license_key_id', 'sender_contact', 'created_at'],
        unique=False
    )
    
    # P3-14 FIX: Composite index for outbox message loading
    # Optimizes: SELECT * FROM outbox_messages WHERE license_key_id = ? AND recipient_email = ? ORDER BY created_at DESC
    op.create_index(
        'idx_outbox_messages_license_recipient_created',
        'outbox_messages',
        ['license_key_id', 'recipient_email', 'created_at'],
        unique=False
    )
    
    # P3-14 FIX: Composite index for conversation state updates
    # Optimizes: UPDATE inbox_conversations SET unread_count = ? WHERE license_key_id = ? AND sender_contact = ?
    op.create_index(
        'idx_inbox_conversations_license_contact',
        'inbox_conversations',
        ['license_key_id', 'sender_contact'],
        unique=False
    )
    
    # P3-14 FIX: Index for retry count filtering (P1-6 FIX support)
    op.create_index(
        'idx_outbox_messages_status_retry',
        'outbox_messages',
        ['status', 'retry_count', 'created_at'],
        unique=False
    )
    
    # P3-14 FIX: Index for message search within conversation
    op.create_index(
        'idx_inbox_messages_contact_body',
        'inbox_messages',
        ['license_key_id', 'sender_contact'],
        unique=False,
        # PostgreSQL supports INCLUDE for covering indexes
        postgresql_include=['body', 'created_at'] if op.get_context().dialect.name == 'postgresql' else None
    )


def downgrade():
    op.drop_index('idx_inbox_messages_contact_body', table_name='inbox_messages')
    op.drop_index('idx_outbox_messages_status_retry', table_name='outbox_messages')
    op.drop_index('idx_inbox_conversations_license_contact', table_name='inbox_conversations')
    op.drop_index('idx_outbox_messages_license_recipient_created', table_name='outbox_messages')
    op.drop_index('idx_inbox_messages_license_contact_created', table_name='inbox_messages')
