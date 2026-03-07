"""Fix notifications id column to use SERIAL/IDENTITY for PostgreSQL

Revision ID: 031_fix_notifications_id_sequence
Revises: 030_add_reply_count
Create Date: 2026-03-07

This migration fixes the notifications table id column to properly auto-increment
in PostgreSQL by converting it to IDENTITY type if it's not already.

"""
from alembic import op
import sqlalchemy as sa
import os

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

revision = '031_fix_notifications_id_sequence'
down_revision = '030_add_reply_count'
branch_labels = None
depends_on = None


def upgrade():
    """Fix notifications id column for PostgreSQL"""
    
    if DB_TYPE == "postgresql":
        # Check if the sequence exists and fix it
        # In PostgreSQL, we need to ensure the id column uses IDENTITY or has a proper sequence
        
        # First, check if the column is already IDENTITY
        op.execute("""
            DO $$
            BEGIN
                -- If id column is not IDENTITY, convert it
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name = 'notifications' 
                    AND column_name = 'id' 
                    AND is_identity = 'YES'
                ) THEN
                    -- Drop the existing primary key constraint
                    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_pkey;
                    
                    -- Add identity property to the column
                    ALTER TABLE notifications ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY;
                    
                    -- Re-add primary key constraint
                    ALTER TABLE notifications ADD PRIMARY KEY (id);
                END IF;
            END $$;
        """)
        
        # Reset the sequence to max(id) + 1 to avoid conflicts with existing data
        op.execute("""
            SELECT setval('notifications_id_seq', COALESCE((SELECT MAX(id) + 1 FROM notifications), 1), false);
        """)
        
        print("Fixed notifications id column for PostgreSQL")
    else:
        # SQLite - no action needed, AUTOINCREMENT should work
        print("SQLite detected - no fix needed for notifications id")


def downgrade():
    """Revert notifications id column changes"""
    
    if DB_TYPE == "postgresql":
        # Convert back to regular INTEGER (not recommended)
        op.execute("""
            ALTER TABLE notifications ALTER COLUMN id DROP IDENTITY;
        """)
        print("Reverted notifications id column")
    else:
        print("SQLite - no downgrade needed")
