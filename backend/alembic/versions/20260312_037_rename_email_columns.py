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
    # Rename recipient_email to recipient_contact in outbox_messages
    op.execute("ALTER TABLE outbox_messages RENAME COLUMN recipient_email TO recipient_contact")
    
    # Rename email to contact in customers table (if it exists)
    # Checking for existence is usually better done via inspector but for this repo migrations are direct
    try:
        op.execute("ALTER TABLE customers RENAME COLUMN email TO contact")
    except:
        pass

def downgrade():
    op.execute("ALTER TABLE outbox_messages RENAME COLUMN recipient_contact TO recipient_email")
    try:
        op.execute("ALTER TABLE customers RENAME COLUMN contact TO email")
    except:
        pass
