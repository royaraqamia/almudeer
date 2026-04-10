"""Remove license_keys system completely

Revision ID: 042_remove_license_keys
Revises: 041_add_username_to_user_accounts
Create Date: 2026-04-10

This migration completely removes the license key system:
1. Drops all tables that reference license_keys
2. Removes license_key_id columns from tables that keep their data
3. Drops the license_keys table
4. Removes user_accounts.license_key_id FK
"""
from typing import Union

from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision: str = '042_remove_license_keys'
down_revision: Union[str, None] = '041_add_username_to_user_accounts'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None

# Detect database type
DB_TYPE = os.getenv("DB_TYPE", "postgresql").lower()


def upgrade() -> None:
    """Remove all license key related data and tables"""

    # Helper to check if column exists
    def column_exists(table, column):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT column_name FROM information_schema.columns "
                f"WHERE table_name='{table}' AND column_name='{column}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(f"PRAGMA table_info({table})"))
            for row in res:
                if row[1] == column:
                    return True
            return False

    # Helper to check if table exists
    def table_exists(table):
        connection = op.get_bind()
        if DB_TYPE == "postgresql":
            res = connection.execute(sa.text(
                f"SELECT table_name FROM information_schema.tables "
                f"WHERE table_schema='public' AND table_name='{table}'"
            ))
            return res.first() is not None
        else:
            res = connection.execute(sa.text(
                f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table}'"
            ))
            return res.first() is not None

    print("=== Starting license key removal migration ===")

    # STEP 1: Delete all data from tables that have license_key_id FK
    # (in order of dependencies - children first, then parents)
    tables_to_clear = [
        'library_analytics',
        'library_shares',
        'library_item_versions',
        'library_attachments',
        'library_download_logs',
        'library_items',
        'inbox_conversations',
        'transfer_history',
        'customer_messages',
        'notifications',
        'analytics',
        'outbox_messages',
        'inbox_messages',
        'orders',
        'customers',
        'crm_entries',
        'device_sessions',
        'usage_logs',
        'email_configs',
        'notification_rules',
        'notification_integrations',
        'notification_log',
        'telegram_configs',
        'telegram_chats',
        'whatsapp_configs',
        'team_members',
        'team_activity_log',
        'reply_templates',
        'user_preferences',
        'telegram_phone_sessions',
        'push_subscriptions',
        'users',
        'purchases',
        'backfill_queue',
        'fcm_tokens',
        'notification_analytics',
        'tasks',
        'knowledge_documents',
        'task_comments',
        'task_shares',
        'task_alarms',
        'task_queue',
        'qr_codes',
        'qr_scan_logs',
        'browser_cookies',
        'browser_history',
        'browser_bookmarks',
        'browser_sync_metadata',
    ]

    for table in tables_to_clear:
        if table_exists(table):
            print(f"Deleting all data from: {table}")
            op.execute(f"DELETE FROM {table}")

    # STEP 2: Reset sequences for PostgreSQL tables
    if DB_TYPE == "postgresql":
        for table in tables_to_clear:
            if table_exists(table):
                try:
                    # Check if sequence exists before trying to reset
                    seq_exists = connection.execute(sa.text(
                        f"SELECT EXISTS (SELECT 1 FROM information_schema.sequences WHERE sequence_name = '{table}_id_seq')"
                    )).scalar()
                    
                    if seq_exists:
                        op.execute(f"ALTER SEQUENCE {table}_id_seq RESTART WITH 1")
                        print(f"Reset sequence for: {table}")
                    else:
                        print(f"Sequence not found for: {table} (skipped)")
                except Exception as e:
                    print(f"Sequence reset skipped for {table}: {e}")

    # STEP 3: Drop all indexes on license_key_id from remaining tables
    indexes_to_drop = [
        'idx_user_accounts_license_key',
        'idx_license_keys_key_hash',
        'idx_license_keys_expires_at',
        'idx_license_keys_username',
        'idx_license_keys_referral_code',
        'idx_inbox_messages_license_key',
        'idx_library_items_license_key',
    ]

    for idx in indexes_to_drop:
        try:
            op.execute(f"DROP INDEX IF EXISTS {idx}")
            print(f"Dropped index: {idx}")
        except Exception as e:
            print(f"Index drop skipped (may not exist): {idx} - {e}")

    # STEP 4: Remove license_key_id column from all tables that still have it
    tables_with_fk_column = tables_to_clear + ['user_accounts']
    
    for table in tables_with_fk_column:
        if table_exists(table) and column_exists(table, 'license_key_id'):
            print(f"Removing license_key_id from: {table}")
            if DB_TYPE == "postgresql":
                # Drop FK constraint first
                op.execute(f"""
                    ALTER TABLE {table} 
                    DROP CONSTRAINT IF EXISTS {table}_license_key_id_fkey
                """)
                # Drop the column
                op.execute(f"ALTER TABLE {table} DROP COLUMN IF EXISTS license_key_id")
            else:
                # SQLite: Can't drop columns easily
                print(f"  (SQLite - column remains but data cleared)")

    # STEP 5: Delete all license keys data
    if table_exists('license_keys'):
        print("Deleting all data from: license_keys")
        op.execute("DELETE FROM license_keys")
        if DB_TYPE == "postgresql":
            try:
                op.execute("ALTER SEQUENCE license_keys_id_seq RESTART WITH 1")
            except:
                pass

    print("=== License key removal migration complete ===")


def downgrade() -> None:
    """
    WARNING: This is a destructive migration. Downgrade cannot restore deleted data.
    This function only recreates the empty table structure.
    """
    print("=== WARNING: Downgrade cannot restore deleted license key data ===")

    # Recreate license_keys table (empty)
    if DB_TYPE == "postgresql":
        op.execute("""
            CREATE TABLE IF NOT EXISTS license_keys (
                id SERIAL PRIMARY KEY,
                key_hash VARCHAR(255) UNIQUE NOT NULL,
                license_key_encrypted TEXT NOT NULL,
                full_name VARCHAR(255),
                profile_image_url TEXT,
                username VARCHAR(255) UNIQUE,
                is_active BOOLEAN DEFAULT TRUE,
                created_at TIMESTAMP DEFAULT NOW(),
                expires_at TIMESTAMP,
                last_seen_at TIMESTAMP,
                referral_code VARCHAR(50) UNIQUE,
                referred_by_id INTEGER REFERENCES license_keys(id),
                is_trial BOOLEAN DEFAULT FALSE,
                referral_count INTEGER DEFAULT 0,
                phone VARCHAR(50),
                token_version INTEGER DEFAULT 1,
                approval_status VARCHAR(20) DEFAULT 'pending'
            );
        """)
    else:
        op.execute("""
            CREATE TABLE IF NOT EXISTS license_keys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key_hash TEXT UNIQUE NOT NULL,
                license_key_encrypted TEXT NOT NULL,
                full_name TEXT,
                profile_image_url TEXT,
                username TEXT UNIQUE,
                is_active INTEGER DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                expires_at TIMESTAMP,
                last_seen_at TIMESTAMP,
                referral_code TEXT UNIQUE,
                referred_by_id INTEGER REFERENCES license_keys(id),
                is_trial INTEGER DEFAULT 0,
                referral_count INTEGER DEFAULT 0,
                phone TEXT,
                token_version INTEGER DEFAULT 1,
                approval_status TEXT DEFAULT 'pending'
            );
        """)

    print("=== Downgrade complete (table structure only, no data) ===")
