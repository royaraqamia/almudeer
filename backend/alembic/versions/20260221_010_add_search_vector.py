"""add search vector for full text search

Revision ID: 010_add_search_vector
Revises: 009_add_conversation_attachments
Create Date: 2026-02-21

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '010_add_search_vector'
down_revision: Union[str, None] = '009_add_conversation_attachments'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

def upgrade() -> None:
    """Add search_vector column and GIN index for full-text search"""
    if DB_TYPE == "postgresql":
        # 1. Add search_vector to inbox_messages
        # We use execute with raw SQL for tsvector type as it's PG specific
        op.execute("ALTER TABLE inbox_messages ADD COLUMN IF NOT EXISTS search_vector tsvector")
        op.execute("CREATE INDEX IF NOT EXISTS idx_inbox_search_vector ON inbox_messages USING GIN(search_vector)")
        
        # 2. Add search_vector to outbox_messages
        op.execute("ALTER TABLE outbox_messages ADD COLUMN IF NOT EXISTS search_vector tsvector")
        op.execute("CREATE INDEX IF NOT EXISTS idx_outbox_search_vector ON outbox_messages USING GIN(search_vector)")
        
        # 3. Create function and trigger to auto-update search_vector
        op.execute("""
            CREATE OR REPLACE FUNCTION update_inbox_search_vector() RETURNS trigger AS $$
            BEGIN
                new.search_vector :=
                    setweight(to_tsvector('english', coalesce(new.body, '')), 'A') ||
                    setweight(to_tsvector('english', coalesce(new.sender_name, '')), 'B') ||
                    setweight(to_tsvector('english', coalesce(new.subject, '')), 'B');
                RETURN new;
            END
            $$ LANGUAGE plpgsql;
        """)
        
        op.execute("""
            DROP TRIGGER IF EXISTS trg_inbox_search_vector ON inbox_messages;
            CREATE TRIGGER trg_inbox_search_vector BEFORE INSERT OR UPDATE
            ON inbox_messages FOR EACH ROW EXECUTE FUNCTION update_inbox_search_vector();
        """)
        
        op.execute("""
            CREATE OR REPLACE FUNCTION update_outbox_search_vector() RETURNS trigger AS $$
            BEGIN
                new.search_vector :=
                    setweight(to_tsvector('english', coalesce(new.body, '')), 'A') ||
                    setweight(to_tsvector('english', coalesce(new.subject, '')), 'B');
                RETURN new;
            END
            $$ LANGUAGE plpgsql;
        """)
        
        op.execute("""
            DROP TRIGGER IF EXISTS trg_outbox_search_vector ON outbox_messages;
            CREATE TRIGGER trg_outbox_search_vector BEFORE INSERT OR UPDATE
            ON outbox_messages FOR EACH ROW EXECUTE FUNCTION update_outbox_search_vector();
        """)
        
        # 4. Initial backfill
        op.execute("UPDATE inbox_messages SET search_vector = setweight(to_tsvector('english', coalesce(body, '')), 'A') || setweight(to_tsvector('english', coalesce(sender_name, '')), 'B') || setweight(to_tsvector('english', coalesce(subject, '')), 'B')")
        op.execute("UPDATE outbox_messages SET search_vector = setweight(to_tsvector('english', coalesce(body, '')), 'A') || setweight(to_tsvector('english', coalesce(subject, '')), 'B')")
    else:
        # SQLite FTS handled via messages_fts virtual table if needed
        pass

def downgrade() -> None:
    """Remove search vector and triggers"""
    if DB_TYPE == "postgresql":
        op.execute("DROP TRIGGER IF EXISTS trg_inbox_search_vector ON inbox_messages")
        op.execute("DROP TRIGGER IF EXISTS trg_outbox_search_vector ON outbox_messages")
        op.execute("DROP FUNCTION IF EXISTS update_inbox_search_vector()")
        op.execute("DROP FUNCTION IF EXISTS update_outbox_search_vector()")
        op.execute("DROP INDEX IF EXISTS idx_inbox_search_vector")
        op.execute("DROP INDEX IF EXISTS idx_outbox_search_vector")
        op.execute("ALTER TABLE inbox_messages DROP COLUMN IF EXISTS search_vector")
        op.execute("ALTER TABLE outbox_messages DROP COLUMN IF EXISTS search_vector")
