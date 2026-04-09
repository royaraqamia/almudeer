"""Add email authentication support with user_accounts table

Revision ID: 040_add_email_auth
Revises: 039_add_library_items_created_by
Create Date: 2026-04-09

This migration adds:
1. user_accounts table for email/password authentication
2. OTP verification fields (otp_code, otp_expires_at, otp_attempts)
3. Password reset fields (reset_token, reset_token_expires_at)
4. Approval workflow fields (is_email_verified, is_approved_by_admin, approval_status)
5. approval_status column to license_keys table for backward compatibility
"""
from typing import Union
from alembic import op
import sqlalchemy as sa
import os

revision: str = '040_add_email_auth'
down_revision: Union[str, None] = '039_add_library_items_created_by'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create user_accounts table and add approval_status to license_keys"""
    
    db_type = os.getenv("DB_TYPE", "sqlite").lower()

    # 1. Create user_accounts table for email/password authentication
    if db_type == "postgresql":
        op.execute("""
            CREATE TABLE IF NOT EXISTS user_accounts (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) NOT NULL UNIQUE,
                password_hash VARCHAR(255) NOT NULL,
                full_name VARCHAR(255),
                license_key_id INTEGER REFERENCES license_keys(id),
                is_email_verified BOOLEAN DEFAULT FALSE,
                is_approved_by_admin BOOLEAN DEFAULT FALSE,
                approval_status VARCHAR(20) DEFAULT 'pending',
                otp_code VARCHAR(6),
                otp_expires_at TIMESTAMP,
                otp_attempts INTEGER DEFAULT 0,
                reset_token TEXT,
                reset_token_expires_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_login TIMESTAMP
            );
        """)
    else:
        # SQLite
        op.execute("""
            CREATE TABLE IF NOT EXISTS user_accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email VARCHAR(255) NOT NULL UNIQUE,
                password_hash VARCHAR(255) NOT NULL,
                full_name TEXT,
                license_key_id INTEGER REFERENCES license_keys(id),
                is_email_verified BOOLEAN DEFAULT 0,
                is_approved_by_admin BOOLEAN DEFAULT 0,
                approval_status VARCHAR(20) DEFAULT 'pending',
                otp_code VARCHAR(6),
                otp_expires_at TIMESTAMP,
                otp_attempts INTEGER DEFAULT 0,
                reset_token TEXT,
                reset_token_expires_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_login TIMESTAMP
            );
        """)

    # 2. Create indexes for performance
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_user_accounts_email
        ON user_accounts(email);
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_user_accounts_license_key
        ON user_accounts(license_key_id);
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_user_accounts_approval_status
        ON user_accounts(approval_status);
    """)

    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_user_accounts_reset_token
        ON user_accounts(reset_token);
    """)

    # 3. Add approval_status to license_keys for backward compatibility
    if db_type == "postgresql":
        op.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'license_keys' AND column_name = 'approval_status'
                ) THEN
                    ALTER TABLE license_keys ADD COLUMN approval_status VARCHAR(20) DEFAULT 'pending';
                END IF;
            END $$;
        """)
    else:
        # SQLite: Use ALTER TABLE ADD COLUMN (SQLite 3.35+ supports this)
        try:
            op.execute("ALTER TABLE license_keys ADD COLUMN approval_status VARCHAR(20) DEFAULT 'pending'")
        except Exception:
            # Column may already exist
            pass

    # 4. Backfill: Mark existing active licenses as approved
    op.execute("""
        UPDATE license_keys
        SET approval_status = 'approved'
        WHERE approval_status = 'pending' AND is_active = TRUE;
    """)

    # 5. Create function to auto-update updated_at timestamp (PostgreSQL only)
    if db_type == "postgresql":
        op.execute("""
            CREATE OR REPLACE FUNCTION update_user_accounts_updated_at()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW.updated_at = CURRENT_TIMESTAMP;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        """)

        # 6. Create trigger for updated_at (PostgreSQL only)
        op.execute("""
            DROP TRIGGER IF EXISTS trg_user_accounts_updated_at ON user_accounts;
            CREATE TRIGGER trg_user_accounts_updated_at
                BEFORE UPDATE ON user_accounts
                FOR EACH ROW
                EXECUTE FUNCTION update_user_accounts_updated_at();
        """)


def downgrade() -> None:
    """Remove user_accounts table and approval_status from license_keys"""
    
    db_type = os.getenv("DB_TYPE", "sqlite").lower()
    
    if db_type == "postgresql":
        # Drop trigger and function
        op.execute("DROP TRIGGER IF EXISTS trg_user_accounts_updated_at ON user_accounts")
        op.execute("DROP FUNCTION IF EXISTS update_user_accounts_updated_at")

    # Drop indexes
    op.execute("DROP INDEX IF EXISTS idx_user_accounts_email")
    op.execute("DROP INDEX IF EXISTS idx_user_accounts_license_key")
    op.execute("DROP INDEX IF EXISTS idx_user_accounts_approval_status")
    op.execute("DROP INDEX IF EXISTS idx_user_accounts_reset_token")

    # Drop table
    op.execute("DROP TABLE IF EXISTS user_accounts")

    # Remove column from license_keys (only supported in PostgreSQL)
    if db_type == "postgresql":
        op.execute("ALTER TABLE license_keys DROP COLUMN IF EXISTS approval_status")
