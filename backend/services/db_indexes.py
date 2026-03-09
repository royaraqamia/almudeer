"""
Al-Mudeer - Database Index Optimization
Creates indexes for frequently queried columns to improve performance
"""

# SQL for creating optimized indexes
# Run these during database initialization

SQLITE_INDEXES = """
-- License key lookups (most common query)
CREATE INDEX IF NOT EXISTS idx_license_keys_hash ON license_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_license_keys_active ON license_keys(is_active, expires_at);

-- Inbox message queries (very frequent)
CREATE INDEX IF NOT EXISTS idx_inbox_license_channel ON inbox_messages(license_key_id, channel);
CREATE INDEX IF NOT EXISTS idx_inbox_created ON inbox_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inbox_is_read ON inbox_messages(license_key_id, is_read);
CREATE INDEX IF NOT EXISTS idx_inbox_urgency ON inbox_messages(license_key_id, urgency);

-- CRM entries (customer queries)
CREATE INDEX IF NOT EXISTS idx_crm_license ON crm_entries(license_id);
CREATE INDEX IF NOT EXISTS idx_crm_created ON crm_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_crm_sender ON crm_entries(sender_contact);

-- Usage tracking
CREATE INDEX IF NOT EXISTS idx_usage_license_date ON usage_logs(license_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_action ON usage_logs(action_type);

-- Telegram/Email integrations
CREATE INDEX IF NOT EXISTS idx_email_license ON email_integrations(license_key_id);
CREATE INDEX IF NOT EXISTS idx_telegram_license ON telegram_integrations(license_key_id);

-- Customers table
CREATE INDEX IF NOT EXISTS idx_customers_license ON customers(license_key_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);

-- Notifications
CREATE INDEX IF NOT EXISTS idx_notifications_license ON user_notifications(license_key_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON user_notifications(created_at DESC);
"""

POSTGRESQL_INDEXES = """
-- License key lookups (most common query)
CREATE INDEX IF NOT EXISTS idx_license_keys_hash ON license_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_license_keys_active ON license_keys(is_active, expires_at);

-- Inbox message queries (very frequent) - with partial indexes
CREATE INDEX IF NOT EXISTS idx_inbox_license_channel ON inbox_messages(license_key_id, channel);
CREATE INDEX IF NOT EXISTS idx_inbox_created ON inbox_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inbox_unread ON inbox_messages(license_key_id) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_inbox_urgent ON inbox_messages(license_key_id) WHERE urgency = 'عاجل';

-- CRM entries (customer queries)
CREATE INDEX IF NOT EXISTS idx_crm_license ON crm_entries(license_id);
CREATE INDEX IF NOT EXISTS idx_crm_created ON crm_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_crm_sender ON crm_entries(sender_contact);

-- Usage tracking with date-based partitioning support
CREATE INDEX IF NOT EXISTS idx_usage_license_date ON usage_logs(license_id, created_at DESC);

-- Telegram/Email integrations
CREATE INDEX IF NOT EXISTS idx_email_license ON email_integrations(license_key_id);
CREATE INDEX IF NOT EXISTS idx_telegram_license ON telegram_integrations(license_key_id);

-- Customers table
CREATE INDEX IF NOT EXISTS idx_customers_license ON customers(license_key_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);

-- Notifications with partial index for unread
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON user_notifications(license_key_id) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_created ON user_notifications(created_at DESC);
"""


async def create_indexes():
    """Create all database indexes for optimal query performance"""
    import os
    from db_helper import get_db, execute_sql
    from logging_config import get_logger
    
    logger = get_logger(__name__)
    db_type = os.getenv("DB_TYPE", "sqlite").lower()
    
    indexes_sql = POSTGRESQL_INDEXES if db_type == "postgresql" else SQLITE_INDEXES
    
    # Split into individual statements
    statements = [s.strip() for s in indexes_sql.split(';') if s.strip() and not s.strip().startswith('--')]
    
    created_count = 0
    async with get_db() as db:
        for statement in statements:
            try:
                await execute_sql(db, statement)
                created_count += 1
            except Exception as e:
                # Index might already exist or table doesn't exist yet
                if "already exists" not in str(e).lower():
                    logger.debug(f"Index creation skipped: {e}")
    
    logger.info(f"Database indexes verified/created: {created_count} indexes")
    return created_count
