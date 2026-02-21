"""
Create PostgreSQL schema
"""

import os
import asyncio
import asyncpg


async def create_schema():
    """Create database schema"""
    database_url = os.getenv("DATABASE_URL")
    
    if not database_url:
        print("ERROR: DATABASE_URL not set")
        return
    
    print("Creating PostgreSQL schema...")
    
    try:
        # Try with SSL first (for public URLs)
        try:
            conn = await asyncpg.connect(database_url, ssl='require')
        except:
            conn = await asyncpg.connect(database_url)
        
        # Create tables
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS license_keys (
                id SERIAL PRIMARY KEY,
                key_hash TEXT UNIQUE NOT NULL,
                full_name TEXT NOT NULL,
                contact_email TEXT,
                is_active BOOLEAN DEFAULT TRUE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                expires_at TIMESTAMP,
                max_requests_per_day INTEGER DEFAULT 100,
                requests_today INTEGER DEFAULT 0,
                last_request_date DATE
            )
        """)
        
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS usage_logs (
                id SERIAL PRIMARY KEY,
                license_key_id INTEGER REFERENCES license_keys(id),
                action_type TEXT NOT NULL,
                input_preview TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS crm_entries (
                id SERIAL PRIMARY KEY,
                license_key_id INTEGER REFERENCES license_keys(id),
                sender_name TEXT,
                sender_contact TEXT,
                message_type TEXT,
                intent TEXT,
                extracted_data TEXT,
                original_message TEXT,
                draft_response TEXT,
                status TEXT DEFAULT 'جديد',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP
            )
        """)
        
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                license_key_id INTEGER NOT NULL REFERENCES license_keys(id),
                title TEXT NOT NULL,
                description TEXT,
                is_completed BOOLEAN DEFAULT FALSE,
                due_date TIMESTAMP,
                priority TEXT DEFAULT 'medium',
                color BIGINT,
                sub_tasks TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP
            )
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS inbox_messages (
                id SERIAL PRIMARY KEY,
                license_key_id INTEGER NOT NULL REFERENCES license_keys(id),
                channel TEXT NOT NULL,
                channel_message_id TEXT,
                sender_id TEXT,
                sender_name TEXT,
                sender_contact TEXT,
                subject TEXT,
                body TEXT NOT NULL,
                received_at TIMESTAMP,
                attachments TEXT,
                intent TEXT,
                urgency TEXT,
                sentiment TEXT,
                status TEXT DEFAULT 'pending',
                reply_to_platform_id TEXT,
                reply_to_body_preview TEXT,
                reply_to_sender_name TEXT,
                reply_to_id INTEGER,
                platform_status TEXT,
                platform_message_id TEXT,
                is_forwarded BOOLEAN DEFAULT FALSE,
                deleted_at TIMESTAMP,
                original_sender TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS outbox_messages (
                id SERIAL PRIMARY KEY,
                license_key_id INTEGER NOT NULL REFERENCES license_keys(id),
                inbox_message_id INTEGER REFERENCES inbox_messages(id),
                channel TEXT NOT NULL,
                recipient_id TEXT,
                recipient_email TEXT,
                subject TEXT,
                body TEXT NOT NULL,
                attachments TEXT,
                status TEXT DEFAULT 'pending',
                sent_at TIMESTAMP,
                error_message TEXT,
                reply_to_platform_id TEXT,
                is_forwarded BOOLEAN DEFAULT FALSE,
                deleted_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS inbox_conversations (
                license_key_id INTEGER NOT NULL REFERENCES license_keys(id),
                sender_contact TEXT NOT NULL,
                sender_name TEXT,
                channel TEXT,
                last_message_id INTEGER,
                last_message_body TEXT,
                last_message_at TIMESTAMP,
                status TEXT,
                unread_count INTEGER DEFAULT 0,
                message_count INTEGER DEFAULT 0,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (license_key_id, sender_contact)
            )
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS knowledge_documents (
                id SERIAL PRIMARY KEY,
                license_key_id INTEGER NOT NULL REFERENCES license_keys(id),
                user_id TEXT,
                source TEXT DEFAULT 'manual',
                text TEXT,
                file_path TEXT,
                file_size INTEGER,
                mime_type TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP,
                deleted_at TIMESTAMP
            )
        """)
        
        # Create indexes
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_license_key_hash ON license_keys(key_hash)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_crm_license_id ON crm_entries(license_key_id)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_crm_created_at ON crm_entries(created_at)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_usage_logs_license_id ON usage_logs(license_key_id)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_license_expires_at ON license_keys(expires_at)")
        
        print("SUCCESS: Schema created!")
        await conn.close()
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(create_schema())

