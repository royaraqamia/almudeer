"""
Al-Mudeer - Base Database Models
Database configuration, connection utilities, and table initialization
Supports both SQLite (development) and PostgreSQL (production)
"""

from datetime import datetime, timedelta, timezone
from typing import Optional, List, Any
import json
import asyncio

from db_helper import (
    DB_TYPE,
    DATABASE_PATH,
    DATABASE_URL,
    POSTGRES_AVAILABLE,
    get_db,
    execute_sql,
    commit_db
)
from db_pool import ID_PK, TIMESTAMP_NOW, INT_TYPE, TEXT_TYPE
from db_helper import fetch_all, fetch_one

# User Roles
ROLES = {
    "owner": "Administrator with full access",
    "admin": "Administrator with full access",
    "agent": "Support agent with access to messages and customers",
    "manager": "Team manager with reporting access",
    "member": "Basic team member"
}


async def init_enhanced_tables():
    """Initialize enhanced tables for Messaging integration"""
    async with get_db() as db:
        
        # email_configs table removed
        
        # Telegram Bot Configuration per license
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS telegram_configs (
                id {ID_PK},
                license_key_id INTEGER UNIQUE NOT NULL,
                bot_token TEXT NOT NULL,
                bot_username TEXT,
                webhook_secret TEXT,
                is_active BOOLEAN DEFAULT TRUE,
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Unified Inbox - All incoming messages
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS inbox_messages (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                channel TEXT NOT NULL,
                channel_message_id TEXT,
                sender_id TEXT,
                sender_name TEXT,
                sender_contact TEXT,
                subject TEXT,
                body TEXT NOT NULL,
                received_at TIMESTAMP,
                intent TEXT,
                urgency TEXT,
                sentiment TEXT,
                language TEXT,
                dialect TEXT,
                ai_summary TEXT,
                ai_draft_response TEXT,
                status TEXT DEFAULT 'pending',
                processed_at TIMESTAMP,
                deleted_at TIMESTAMP,
                reply_to_platform_id TEXT,
                reply_to_body_preview TEXT,
                reply_to_sender_name TEXT,
                reply_to_id INTEGER,
                attachments TEXT,
                is_forwarded BOOLEAN DEFAULT FALSE,
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Outbox - Approved/Sent messages
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS outbox_messages (
                id {ID_PK},
                inbox_message_id INTEGER,
                license_key_id INTEGER NOT NULL,
                channel TEXT NOT NULL,
                recipient_id TEXT,
                subject TEXT,
                body TEXT NOT NULL,
                attachments TEXT,
                status TEXT DEFAULT 'pending',
                approved_at TIMESTAMP,
                sent_at TIMESTAMP,
                deleted_at TIMESTAMP,
                error_message TEXT,
                reply_to_platform_id TEXT,
                reply_to_body_preview TEXT,
                reply_to_id INTEGER,
                reply_to_sender_name TEXT,
                is_forwarded BOOLEAN DEFAULT FALSE,
                delivery_status TEXT DEFAULT 'pending', -- Updated: Real-time status tracking
                retry_count INTEGER DEFAULT 0, -- P1-6 FIX: Track retry attempts
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (inbox_message_id) REFERENCES inbox_messages(id),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        # Migration for delivery_status
        try:
            await execute_sql(db, "ALTER TABLE outbox_messages ADD COLUMN delivery_status TEXT DEFAULT 'pending'")
        except: pass
        
        # P1-6 FIX: Migration for retry_count column
        try:
            await execute_sql(db, "ALTER TABLE outbox_messages ADD COLUMN retry_count INTEGER DEFAULT 0")
        except: pass  # Column may already exist
        
        # Telegram Phone Sessions (MTProto for user accounts)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS telegram_phone_sessions (
                id {ID_PK},
                license_key_id INTEGER UNIQUE NOT NULL,
                phone_number TEXT NOT NULL,
                session_data_encrypted TEXT NOT NULL,
                user_id TEXT,
                user_first_name TEXT,
                user_last_name TEXT,
                user_username TEXT,
                is_active BOOLEAN DEFAULT TRUE,
                last_synced_at TIMESTAMP,
                created_at {TIMESTAMP_NOW},
                updated_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
 
        # Telegram Entities (Persistent memory for peer resolution)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS telegram_entities (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                entity_id TEXT NOT NULL,
                access_hash TEXT NOT NULL,
                entity_type TEXT DEFAULT 'user',
                username TEXT,
                phone TEXT,
                updated_at {TIMESTAMP_NOW},
                UNIQUE(license_key_id, entity_id),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Telegram Chat Sessions
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS telegram_chats (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                chat_id TEXT NOT NULL,
                chat_type TEXT,
                username TEXT,
                first_name TEXT,
                last_name TEXT,
                is_blocked BOOLEAN DEFAULT FALSE,
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
                UNIQUE(license_key_id, chat_id)
            )
        """)
        
        # Performance indexes for frequent queries
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_inbox_license_status
            ON inbox_messages(license_key_id, status)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_inbox_license_created
            ON inbox_messages(license_key_id, created_at)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_outbox_license_status
            ON outbox_messages(license_key_id, status)
        """)
        # Language/dialect quick filter
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_inbox_language
            ON inbox_messages(language, dialect)
        """)


            
        # Migration for outbox_messages deleted_at
        try:
            await execute_sql(db, """
                ALTER TABLE outbox_messages ADD COLUMN deleted_at TIMESTAMP
            """)
        except:
            pass

        try:
            await execute_sql(db, """
                ALTER TABLE inbox_messages ADD COLUMN deleted_at TIMESTAMP
            """)
        except:
            pass

        # Migration for attachments column
        try:
            await execute_sql(db, """
                ALTER TABLE inbox_messages ADD COLUMN attachments TEXT
            """)
        except:
            pass

        try:
            await execute_sql(db, """
                ALTER TABLE outbox_messages ADD COLUMN attachments TEXT
            """)
        except:
            pass

        # Migration for message editing (outbox)
        try:
            await execute_sql(db, "ALTER TABLE outbox_messages ADD COLUMN edited_at TIMESTAMP")
        except: pass
        try:
            await execute_sql(db, "ALTER TABLE outbox_messages ADD COLUMN original_body TEXT")
        except: pass
        try:
            await execute_sql(db, "ALTER TABLE outbox_messages ADD COLUMN edit_count INTEGER DEFAULT 0")
        except: pass

        # Migration for message editing (inbox - for peer compatibility)
        try:
            await execute_sql(db, "ALTER TABLE inbox_messages ADD COLUMN edited_at TIMESTAMP")
        except: pass

        # Migration for outbox_messages inbox_message_id (PostgreSQL only)
        if DB_TYPE == "postgresql":
            try:
                await execute_sql(db, "ALTER TABLE outbox_messages ALTER COLUMN inbox_message_id DROP NOT NULL")
            except Exception as e:
                print(f"Postgres Migration (drop not null) skipped: {e}")

        # Migration for reply_to context columns
        for table in ["inbox_messages", "outbox_messages"]:
            for col in ["reply_to_platform_id", "reply_to_body_preview"]:
                try:
                    await execute_sql(db, f"ALTER TABLE {table} ADD COLUMN {col} TEXT")
                except:
                    pass
            try:
                await execute_sql(db, f"ALTER TABLE {table} ADD COLUMN reply_to_id INTEGER")
            except:
                pass
            try:
                await execute_sql(db, f"ALTER TABLE {table} ADD COLUMN reply_to_sender_name TEXT")
            except:
                pass

        # Unique to inbox_messages
        try:
            await execute_sql(db, "ALTER TABLE inbox_messages ADD COLUMN reply_to_sender_name TEXT")
        except:
            pass

        # Migration for is_forwarded column
        for table in ["inbox_messages", "outbox_messages"]:
            try:
                await execute_sql(db, f"ALTER TABLE {table} ADD COLUMN is_forwarded BOOLEAN DEFAULT FALSE")
            except:
                pass

        # Library Items (Notes, Images, Files, Audio, Video)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS library_items (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT, -- The ID of the user who created this item
                customer_id INTEGER,
                type TEXT NOT NULL, -- 'note', 'image', 'file', 'audio', 'video'
                title TEXT,
                content TEXT, -- For notes
                file_path TEXT, -- For media/files
                file_size INTEGER, -- In bytes
                mime_type TEXT,
                file_hash TEXT, -- For deduplication (P0-2)
                version INTEGER DEFAULT 1, -- For versioning (P3-13)
                is_shared INTEGER DEFAULT 0, -- For sharing (P3-14)
                access_count INTEGER DEFAULT 0, -- For analytics (P3-15)
                download_count INTEGER DEFAULT 0, -- For analytics (P3-15)
                last_accessed_at TIMESTAMP, -- For analytics (P3-15)
                created_by TEXT, -- User who created the item (P3-14 sharing)
                created_at {TIMESTAMP_NOW},
                updated_at {TIMESTAMP_NOW},
                deleted_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
                FOREIGN KEY (customer_id) REFERENCES customers(id)
            )
        """)

        # Performance index for searching library items
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_license_customer
            ON library_items(license_key_id, customer_id)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_user
            ON library_items(license_key_id, user_id)
        """)

        # Issue #5: Index for soft-delete filtering (performance optimization)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_deleted_at
            ON library_items(deleted_at)
        """)

        # Issue #33: Composite index for common query patterns (license + user + deleted + type)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_active_user_type
            ON library_items(license_key_id, user_id, deleted_at, type)
        """)

        # Issue #12: Index on type column for filtering
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_type
            ON library_items(type)
        """)

        # Issue #5: Composite index for active items query optimization
        if DB_TYPE == "postgresql":
            # PostgreSQL supports partial indexes
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_library_active_items
                ON library_items(license_key_id, deleted_at)
                WHERE deleted_at IS NULL
            """)

        # Migration for user_id column
        try:
            await execute_sql(db, "ALTER TABLE library_items ADD COLUMN user_id TEXT")
        except:
            pass

        # Library Item Versions (for versioning)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS library_item_versions (
                id {ID_PK},
                item_id INTEGER NOT NULL,
                license_key_id INTEGER NOT NULL,
                version INTEGER NOT NULL DEFAULT 1,
                title TEXT,
                content TEXT,
                created_at {TIMESTAMP_NOW},
                created_by TEXT,
                change_summary TEXT,
                FOREIGN KEY (item_id) REFERENCES library_items(id) ON DELETE CASCADE,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE
            )
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_versions_item_id
            ON library_item_versions(item_id)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_versions_item_version
            ON library_item_versions(item_id, version DESC)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_versions_license
            ON library_item_versions(license_key_id)
        """)

        # Library Shares (for sharing items)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS library_shares (
                id {ID_PK},
                item_id INTEGER NOT NULL,
                license_key_id INTEGER NOT NULL,
                shared_with_user_id TEXT NOT NULL,
                permission TEXT NOT NULL DEFAULT 'read',
                created_at {TIMESTAMP_NOW},
                created_by TEXT,
                expires_at TIMESTAMP,
                deleted_at TIMESTAMP,
                FOREIGN KEY (item_id) REFERENCES library_items(id) ON DELETE CASCADE,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE,
                UNIQUE(item_id, shared_with_user_id)
            )
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_shares_item_id
            ON library_shares(item_id)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_shares_user_id
            ON library_shares(shared_with_user_id)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_shares_license
            ON library_shares(license_key_id)
        """)

        # Library Attachments
        # First ensure table exists with basic structure
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS library_attachments (
                id {ID_PK},
                library_item_id INTEGER,
                license_key_id INTEGER NOT NULL,
                file_path TEXT NOT NULL,
                filename TEXT,
                file_size INTEGER,
                mime_type TEXT,
                file_hash TEXT,
                created_at {TIMESTAMP_NOW},
                created_by TEXT,
                deleted_at TIMESTAMP,
                FOREIGN KEY (library_item_id) REFERENCES library_items(id) ON DELETE CASCADE,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE
            )
        """)

        # Ensure all required columns exist (for existing deployments with incomplete schema)
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS library_item_id INTEGER
            """)
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS filename TEXT
            """)
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS file_size INTEGER
            """)
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS mime_type TEXT
            """)
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS file_hash TEXT
            """)
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS created_by TEXT
            """)
            await execute_sql(db, """
                ALTER TABLE library_attachments 
                ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP
            """)
        else:
            # SQLite: Check and add missing columns
            try:
                result = await execute_sql(db, "PRAGMA table_info(library_attachments)")
                columns = [row[1] for row in result] if result else []
                
                if "library_item_id" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN library_item_id INTEGER")
                if "filename" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN filename TEXT")
                if "file_size" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN file_size INTEGER")
                if "mime_type" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN mime_type TEXT")
                if "file_hash" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN file_hash TEXT")
                if "created_by" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN created_by TEXT")
                if "deleted_at" not in columns:
                    await execute_sql(db, "ALTER TABLE library_attachments ADD COLUMN deleted_at TIMESTAMP")
            except Exception:
                pass

        # Now create indexes (columns are guaranteed to exist)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_attachments_item_id
            ON library_attachments(library_item_id)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_attachments_license
            ON library_attachments(license_key_id)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_attachments_deleted
            ON library_attachments(deleted_at)
        """)

        # Library Analytics
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS library_analytics (
                id {ID_PK},
                item_id INTEGER NOT NULL,
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                action TEXT NOT NULL,
                timestamp {TIMESTAMP_NOW},
                client_ip TEXT,
                user_agent TEXT,
                metadata TEXT,
                FOREIGN KEY (item_id) REFERENCES library_items(id) ON DELETE CASCADE,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE
            )
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_analytics_item_id
            ON library_analytics(item_id)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_analytics_timestamp
            ON library_analytics(timestamp DESC)
        """)
        
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_analytics_action
            ON library_analytics(action)
        """)

        # FIX: Library Download Audit Logs
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS library_download_logs (
                id {ID_PK},
                item_id INTEGER NOT NULL,
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                downloaded_at {TIMESTAMP_NOW},
                client_ip TEXT,
                user_agent TEXT,
                FOREIGN KEY (item_id) REFERENCES library_items(id),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Index for audit log queries
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_download_logs_item_id
            ON library_download_logs(item_id)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_download_logs_license
            ON library_download_logs(license_key_id)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_library_download_logs_downloaded_at
            ON library_download_logs(downloaded_at)
        """)

        await commit_db(db)
        print("Enhanced tables initialized")


async def init_customers_and_analytics():
    """Initialize customers, analytics, notifications and related tables.

    Uses the generic db_helper layer so it works for both SQLite (dev)
    and PostgreSQL (production).
    """
    async with get_db() as db:
        # WhatsApp Configuration
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS whatsapp_configs (
                id {ID_PK},
                license_key_id INTEGER NOT NULL UNIQUE,
                phone_number_id TEXT NOT NULL,
                access_token TEXT NOT NULL,
                business_account_id TEXT,
                verify_token TEXT NOT NULL,
                webhook_secret TEXT,
                is_active BOOLEAN DEFAULT TRUE,
                created_at {TIMESTAMP_NOW},
                updated_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        # Team Members (Multi-User Support)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS team_members (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                username TEXT NOT NULL,
                name TEXT NOT NULL,
                password_hash TEXT,
                role TEXT NOT NULL DEFAULT 'agent',
                permissions TEXT,
                is_active BOOLEAN DEFAULT TRUE,
                last_login_at TIMESTAMP,
                created_at {TIMESTAMP_NOW},
                invited_by INTEGER,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
                FOREIGN KEY (invited_by) REFERENCES team_members(id),
                UNIQUE(license_key_id, username)
            )
        """)

        # Team Activity Log
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS team_activity_log (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                team_member_id INTEGER,
                action TEXT NOT NULL,
                details TEXT,
                ip_address TEXT,
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
                FOREIGN KEY (team_member_id) REFERENCES team_members(id)
            )
        """)

        # Notifications (the main notifications table used by the dashboard)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS notifications (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                type TEXT NOT NULL,
                priority TEXT DEFAULT 'normal',
                title TEXT NOT NULL,
                message TEXT NOT NULL,
                link TEXT,
                is_read BOOLEAN DEFAULT FALSE,
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        # Push Subscriptions (Web Push notifications for browsers/devices)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS push_subscriptions (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                endpoint TEXT NOT NULL UNIQUE,
                subscription_info TEXT NOT NULL,
                user_agent TEXT,
                is_active BOOLEAN DEFAULT TRUE,
                created_at {TIMESTAMP_NOW},
                updated_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        # Customer Profiles
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS customers (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                name TEXT,
                contact TEXT UNIQUE NOT NULL,
                phone TEXT,
                company TEXT,
                notes TEXT,
                tags TEXT,
                last_contact_at TIMESTAMP,
                is_vip BOOLEAN DEFAULT FALSE,
                has_whatsapp BOOLEAN DEFAULT FALSE,
                has_telegram BOOLEAN DEFAULT FALSE,
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        try:
            await execute_sql(db, "ALTER TABLE customers ADD COLUMN IF NOT EXISTS has_whatsapp BOOLEAN DEFAULT FALSE")
        except: pass
        try:
                await execute_sql(db, "ALTER TABLE customers ADD COLUMN IF NOT EXISTS has_telegram BOOLEAN DEFAULT FALSE")
        except: pass
        try:
            await execute_sql(db, "ALTER TABLE customers ADD COLUMN IF NOT EXISTS contact TEXT")
            # If we just added contact, we might want to make it UNIQUE if possible, 
            # but that's complex without knowing current data. 
            # The next init will handle it if IF NOT EXISTS works properly on table creation.
        except: pass

        # Knowledge Base Documents
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS knowledge_documents (
                id {ID_PK},
                license_key_id INTEGER NOT NULL,
                user_id TEXT,
                source TEXT DEFAULT 'manual',
                text TEXT,
                file_path TEXT,
                file_size INTEGER,
                mime_type TEXT,
                created_at {TIMESTAMP_NOW},
                updated_at TIMESTAMP,
                deleted_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        # Orders Table
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS orders (
                id {ID_PK},
                order_ref TEXT UNIQUE NOT NULL,
                customer_contact TEXT,
                status TEXT DEFAULT 'Pending',
                total_amount REAL,
                items TEXT,
                created_at {TIMESTAMP_NOW},
                updated_at TIMESTAMP,
                FOREIGN KEY (customer_contact) REFERENCES customers(contact)
            )
        """)

        # Link inbox messages to customers
        await execute_sql(db, """
            CREATE TABLE IF NOT EXISTS customer_messages (
                customer_id INTEGER,
                inbox_message_id INTEGER,
                PRIMARY KEY (customer_id, inbox_message_id),
                FOREIGN KEY (customer_id) REFERENCES customers(id),
                FOREIGN KEY (inbox_message_id) REFERENCES inbox_messages(id)
            )
        """)

        # User preferences (UI + AI behavior / tone)
        await execute_sql(db, """
            CREATE TABLE IF NOT EXISTS user_preferences (
                license_key_id INTEGER PRIMARY KEY,
                dark_mode BOOLEAN DEFAULT FALSE,
                notifications_enabled BOOLEAN DEFAULT TRUE,
                notification_sound BOOLEAN DEFAULT TRUE,
                language TEXT DEFAULT 'ar',
                onboarding_completed BOOLEAN DEFAULT FALSE,
                tone TEXT DEFAULT 'formal',
                custom_tone_guidelines TEXT,
                business_name TEXT,
                industry TEXT,
                products_services TEXT,
                preferred_languages TEXT,
                reply_length TEXT,
                formality_level TEXT,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_customers_license_last_contact
            ON customers(license_key_id, last_contact_at)
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_notifications_license_created
            ON notifications(license_key_id, created_at)
        """)

        # Inbox Conversations (for chat optimization)
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS inbox_conversations (
                license_key_id INTEGER NOT NULL,
                sender_contact TEXT NOT NULL,
                sender_name TEXT,
                channel TEXT,
                last_message_id INTEGER,
                last_message_body TEXT,
                last_message_at TIMESTAMP,
                status TEXT,
                unread_count INTEGER DEFAULT 0,
                message_count INTEGER DEFAULT 0,
                updated_at {TIMESTAMP_NOW},
                PRIMARY KEY (license_key_id, sender_contact),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        await commit_db(db)
        print("Customers & Notifications tables initialized")


# ============ Utility Functions ============

def simple_encrypt(text: str) -> str:
    """Encrypt sensitive data using enhanced security module"""
    try:
        from security import encrypt_sensitive_data
        return encrypt_sensitive_data(text)
    except ImportError:
        # Fallback to simple XOR if enhanced security not available
        key = os.getenv("ENCRYPTION_KEY", "almudeer-secret-key-2024")
        encrypted = []
        for i, char in enumerate(text):
            encrypted.append(chr(ord(char) ^ ord(key[i % len(key)])))
        return ''.join(encrypted)


def simple_decrypt(encrypted: str) -> str:
    """Decrypt sensitive data using enhanced security module"""
    try:
        from security import decrypt_sensitive_data
        return decrypt_sensitive_data(encrypted)
    except ImportError:
        # Fallback to simple XOR if enhanced security not available
        return simple_encrypt(encrypted)  # XOR is symmetric


def init_models():
    """Initialize models synchronously"""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.create_task(init_enhanced_tables())
            asyncio.create_task(init_customers_and_analytics())
        else:
            loop.run_until_complete(init_enhanced_tables())
            loop.run_until_complete(init_customers_and_analytics())
    except RuntimeError:
        asyncio.run(init_enhanced_tables())
        asyncio.run(init_customers_and_analytics())
