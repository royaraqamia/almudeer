"""Add library_download_logs table for audit trail

Revision ID: 012_add_library_download_logs
Revises: 011_add_library_items
Create Date: 2026-02-26

This migration creates the library_download_logs table for tracking
file download access for compliance and audit purposes.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '012_add_library_download_logs'
down_revision: Union[str, None] = '011_add_library_items'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()


def upgrade() -> None:
    """Create library_download_logs table and indexes"""
    
    # Helper for DB-specific syntax
    if DB_TYPE == "postgresql":
        id_pk = "SERIAL PRIMARY KEY"
        timestamp_now = "TIMESTAMP DEFAULT NOW()"
    else:
        id_pk = "INTEGER PRIMARY KEY AUTOINCREMENT"
        timestamp_now = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
    
    # Create library_download_logs table
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS library_download_logs (
            id {id_pk},
            item_id INTEGER NOT NULL,
            license_key_id INTEGER NOT NULL,
            user_id TEXT,
            downloaded_at {timestamp_now},
            client_ip TEXT,
            user_agent TEXT,
            FOREIGN KEY (item_id) REFERENCES library_items(id),
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)
    
    # Create indexes for audit log queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_download_logs_item_id
        ON library_download_logs(item_id)
    """)
    
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_download_logs_license
        ON library_download_logs(license_key_id)
    """)
    
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_download_logs_downloaded_at
        ON library_download_logs(downloaded_at)
    """)


def downgrade() -> None:
    """Drop library_download_logs table and indexes"""
    
    # Drop indexes first
    op.execute("DROP INDEX IF EXISTS idx_library_download_logs_downloaded_at")
    op.execute("DROP INDEX IF EXISTS idx_library_download_logs_license")
    op.execute("DROP INDEX IF EXISTS idx_library_download_logs_item_id")
    
    # Drop table
    op.execute("DROP TABLE IF EXISTS library_download_logs")
