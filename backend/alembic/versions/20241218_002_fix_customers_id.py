"""Fix customers id column to use proper SERIAL for PostgreSQL

Revision ID: 002_fix_customers_id
Revises: 001_initial
Create Date: 2024-12-18

This migration fixes the customers table id column to properly use
a sequence in PostgreSQL. The table may have been created without
proper auto-increment, causing NULL constraint violations on insert.
"""
from typing import Sequence, Union

from alembic import op
import os

# revision identifiers, used by Alembic.
revision: str = '002_fix_customers_id'
down_revision: Union[str, None] = '001_initial'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Fix customers.id column to use proper auto-increment sequence"""
    
    if DB_TYPE != "postgresql":
        # SQLite handles this correctly, no changes needed
        return
    
    # For PostgreSQL, we need to:
    # 1. Create a sequence if it doesn't exist
    # 2. Set the column default to use the sequence
    # 3. Set the sequence to the max existing id
    
    op.execute("""
        DO $$
        BEGIN
            -- Create sequence if it doesn't exist
            IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'customers_id_seq') THEN
                CREATE SEQUENCE customers_id_seq;
            END IF;
            
            -- Set the column default to use the sequence
            ALTER TABLE customers 
            ALTER COLUMN id SET DEFAULT nextval('customers_id_seq');
            
            -- Make the column NOT NULL if it isn't already
            ALTER TABLE customers 
            ALTER COLUMN id SET NOT NULL;
            
            -- Set sequence to max value + 1 to avoid conflicts
            PERFORM setval('customers_id_seq', COALESCE((SELECT MAX(id) FROM customers), 0) + 1, false);
            
            -- Associate sequence with the column (for pg_dump etc)
            ALTER SEQUENCE customers_id_seq OWNED BY customers.id;
        END
        $$;
    """)


def downgrade() -> None:
    """Remove the sequence (not recommended)"""
    if DB_TYPE != "postgresql":
        return
    
    op.execute("""
        ALTER TABLE customers ALTER COLUMN id DROP DEFAULT;
        DROP SEQUENCE IF EXISTS customers_id_seq;
    """)
