"""Fix otp_code column size to store HMAC-SHA256 hash

Revision ID: 041_fix_otp_code_size
Revises: 040_add_email_auth
Create Date: 2026-04-11

The otp_code column was VARCHAR(6) but the OTP service stores HMAC-SHA256
hashes (64 hex characters). This migration increases the column size to
VARCHAR(64) to accommodate the full hash.
"""
from typing import Union
from alembic import op
import sqlalchemy as sa
import os

revision: str = '041_fix_otp_code_size'
down_revision: Union[str, None] = '040_add_email_auth'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Increase otp_code column size to VARCHAR(64)"""

    # This migration is for PostgreSQL - the otp_code column stores HMAC-SHA256 hashes (64 chars)
    op.execute("""
        ALTER TABLE user_accounts
        ALTER COLUMN otp_code TYPE VARCHAR(64);
    """)


def downgrade() -> None:
    """Revert otp_code column size back to VARCHAR(6)"""

    # Truncate any OTP codes longer than 6 chars before downgrading
    op.execute("""
        UPDATE user_accounts
        SET otp_code = NULL
        WHERE LENGTH(otp_code) > 6;
    """)
    op.execute("""
        ALTER TABLE user_accounts
        ALTER COLUMN otp_code TYPE VARCHAR(6);
    """)
