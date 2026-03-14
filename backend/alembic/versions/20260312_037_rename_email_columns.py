"""Rename legacy recipient_email columns to recipient_contact

Revision ID: 037_rename_email_columns
Revises: 036_add_task_shares_expires_at
Create Date: 2026-03-12

"""
from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision = '037_rename_email_columns'
down_revision = '036_add_task_shares_expires_at'
branch_labels = None
depends_on = None

def upgrade():
    # Rename recipient_email to recipient_contact in outbox_messages (if column exists)
    # Check if column exists first using PostgreSQL's information_schema
    op.execute("""
        DO $$ 
        BEGIN 
            IF EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'outbox_messages' AND column_name = 'recipient_email'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'outbox_messages' AND column_name = 'recipient_contact'
            ) THEN
                ALTER TABLE outbox_messages RENAME COLUMN recipient_email TO recipient_contact;
            END IF;
        END $$;
    """)

    # Rename email to contact in customers table (if email exists and contact doesn't)
    op.execute("""
        DO $$ 
        BEGIN 
            IF EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'customers' AND column_name = 'email'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'customers' AND column_name = 'contact'
            ) THEN
                ALTER TABLE customers RENAME COLUMN email TO contact;
            END IF;
        END $$;
    """)

def downgrade():
    op.execute("""
        DO $$ 
        BEGIN 
            IF EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'outbox_messages' AND column_name = 'recipient_contact'
            ) THEN
                ALTER TABLE outbox_messages RENAME COLUMN recipient_contact TO recipient_email;
            END IF;
        END $$;
    """)
    op.execute("""
        DO $$ 
        BEGIN 
            IF EXISTS (
                SELECT 1 FROM information_schema.columns 
                WHERE table_name = 'customers' AND column_name = 'contact'
            ) THEN
                ALTER TABLE customers RENAME COLUMN contact TO email;
            END IF;
        END $$;
    """)
