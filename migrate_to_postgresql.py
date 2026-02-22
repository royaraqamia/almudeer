"""
Migration script: SQLite → PostgreSQL
Converts existing SQLite database to PostgreSQL
"""

import os
import asyncio
import aiosqlite
import asyncpg
from typing import Dict, List, Any
from datetime import datetime


async def export_sqlite_data(db_path: str) -> Dict[str, List[Dict]]:
    """Export all data from SQLite database"""
    data = {}
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        
        # Export license_keys
        cursor = await db.execute("SELECT * FROM license_keys")
        rows = await cursor.fetchall()
        data['license_keys'] = [dict(row) for row in rows]
        
        # Export crm_entries
        cursor = await db.execute("SELECT * FROM crm_entries")
        rows = await cursor.fetchall()
        data['crm_entries'] = [dict(row) for row in rows]
        
        # Export usage_logs
        cursor = await db.execute("SELECT * FROM usage_logs")
        rows = await cursor.fetchall()
        data['usage_logs'] = [dict(row) for row in rows]
        
        # Export inbox_messages
        cursor = await db.execute("SELECT * FROM inbox_messages")
        rows = await cursor.fetchall()
        data['inbox_messages'] = [dict(row) for row in rows]

        # Export outbox_messages
        cursor = await db.execute("SELECT * FROM outbox_messages")
        rows = await cursor.fetchall()
        data['outbox_messages'] = [dict(row) for row in rows]

        # Export inbox_conversations
        cursor = await db.execute("SELECT * FROM inbox_conversations")
        rows = await cursor.fetchall()
        data['inbox_conversations'] = [dict(row) for row in rows]

        # Export tasks
        cursor = await db.execute("SELECT * FROM tasks")
        rows = await cursor.fetchall()
        data['tasks'] = [dict(row) for row in rows]
        
        # Export schema_migrations if exists
        try:
            cursor = await db.execute("SELECT * FROM schema_migrations")
            rows = await cursor.fetchall()
            data['schema_migrations'] = [dict(row) for row in rows]
        except:
            data['schema_migrations'] = []
    
    return data


async def create_postgresql_schema(conn: asyncpg.Connection):
    """Create PostgreSQL schema"""
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS license_keys (
            id SERIAL PRIMARY KEY,
            key_hash TEXT UNIQUE NOT NULL,
            full_name TEXT NOT NULL,
            contact_email TEXT,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP,
            expires_at TIMESTAMP
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
    
    # Create indexes
    await conn.execute("CREATE INDEX IF NOT EXISTS idx_license_key_hash ON license_keys(key_hash)")
    await conn.execute("CREATE INDEX IF NOT EXISTS idx_crm_license_id ON crm_entries(license_key_id)")
    await conn.execute("CREATE INDEX IF NOT EXISTS idx_crm_created_at ON crm_entries(created_at)")
    await conn.execute("CREATE INDEX IF NOT EXISTS idx_usage_logs_license_id ON usage_logs(license_key_id)")
    await conn.execute("CREATE INDEX IF NOT EXISTS idx_license_expires_at ON license_keys(expires_at)")


async def import_data_to_postgresql(conn: asyncpg.Connection, data: Dict[str, List[Dict]]):
    """Import data into PostgreSQL"""
    
    # Import license_keys
    if data['license_keys']:
        for row in data['license_keys']:
            # Convert SQLite boolean (0/1) to Python boolean
            is_active = row.get('is_active', True)
            if isinstance(is_active, int):
                is_active = bool(is_active)
            
            # Convert datetime strings to datetime objects
            created_at = row.get('created_at')
            if created_at and isinstance(created_at, str):
                try:
                    created_at = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                except:
                    created_at = None
            
            expires_at = row.get('expires_at')
            if expires_at and isinstance(expires_at, str):
                try:
                    expires_at = datetime.fromisoformat(expires_at.replace('Z', '+00:00'))
                except:
                    expires_at = None
            
            
            await conn.execute("""
                INSERT INTO license_keys 
                (id, key_hash, full_name, contact_email, is_active, created_at, expires_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (id) DO NOTHING
            """, 
                row.get('id'),
                row.get('key_hash'),
                row.get('full_name', row.get('company_name')),
                row.get('contact_email'),
                is_active,
                created_at,
                expires_at
            )
    
    # Import inbox_messages
    if data.get('inbox_messages'):
        for row in data['inbox_messages']:
            await conn.execute("""
                INSERT INTO inbox_messages
                (id, license_key_id, channel, channel_message_id, sender_id, sender_name,
                 sender_contact, subject, body, received_at, attachments, intent, urgency,
                 sentiment, status, reply_to_platform_id, reply_to_body_preview,
                 reply_to_sender_name, reply_to_id, platform_status, platform_message_id,
                 is_forwarded, deleted_at, original_sender, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25)
                ON CONFLICT (id) DO NOTHING
            """,
                row.get('id'), row.get('license_key_id'), row.get('channel'),
                row.get('channel_message_id'), row.get('sender_id'), row.get('sender_name'),
                row.get('sender_contact'), row.get('subject'), row.get('body'),
                row.get('received_at'), row.get('attachments'), row.get('intent'),
                row.get('urgency'), row.get('sentiment'), row.get('status'),
                row.get('reply_to_platform_id'), row.get('reply_to_body_preview'),
                row.get('reply_to_sender_name'), row.get('reply_to_id'),
                row.get('platform_status'), row.get('platform_message_id'),
                bool(row.get('is_forwarded', False)), row.get('deleted_at'),
                row.get('original_sender'), row.get('created_at')
            )

    # Import outbox_messages
    if data.get('outbox_messages'):
        for row in data['outbox_messages']:
            await conn.execute("""
                INSERT INTO outbox_messages
                (id, license_key_id, inbox_message_id, channel, recipient_id, recipient_email,
                 subject, body, attachments, status, sent_at, error_message,
                 reply_to_platform_id, is_forwarded, deleted_at, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
                ON CONFLICT (id) DO NOTHING
            """,
                row.get('id'), row.get('license_key_id'), row.get('inbox_message_id'),
                row.get('channel'), row.get('recipient_id'), row.get('recipient_email'),
                row.get('subject'), row.get('body'), row.get('attachments'),
                row.get('status'), row.get('sent_at'), row.get('error_message'),
                row.get('reply_to_platform_id'), bool(row.get('is_forwarded', False)),
                row.get('deleted_at'), row.get('created_at')
            )

    # Import inbox_conversations
    if data.get('inbox_conversations'):
        for row in data['inbox_conversations']:
            await conn.execute("""
                INSERT INTO inbox_conversations
                (license_key_id, sender_contact, sender_name, channel, last_message_id,
                 last_message_body, last_message_at, status, unread_count, message_count, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                ON CONFLICT (license_key_id, sender_contact) DO NOTHING
            """,
                row.get('license_key_id'), row.get('sender_contact'), row.get('sender_name'),
                row.get('channel'), row.get('last_message_id'), row.get('last_message_body'),
                row.get('last_message_at'), row.get('status'), row.get('unread_count', 0),
                row.get('message_count', 0), row.get('updated_at')
            )

    # Import tasks
    if data.get('tasks'):
        for row in data['tasks']:
            await conn.execute("""
                INSERT INTO tasks
                (id, license_key_id, title, description, is_completed, due_date,
                 priority, color, sub_tasks, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                ON CONFLICT (id) DO NOTHING
            """,
                row.get('id'), row.get('license_key_id'), row.get('title'),
                row.get('description'), bool(row.get('is_completed', False)),
                row.get('due_date'), row.get('priority'), row.get('color'),
                row.get('sub_tasks'), row.get('created_at'), row.get('updated_at')
            )
    
    # Import usage_logs
    if data['usage_logs']:
        for row in data['usage_logs']:
            # Convert datetime strings
            created_at = row.get('created_at')
            if created_at and isinstance(created_at, str):
                try:
                    created_at = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                except:
                    created_at = None
            
            await conn.execute("""
                INSERT INTO usage_logs
                (id, license_key_id, action_type, input_preview, created_at)
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (id) DO NOTHING
            """,
                row.get('id'),
                row.get('license_key_id'),
                row.get('action_type'),
                row.get('input_preview'),
                created_at
            )
    
    # Import schema_migrations
    if data['schema_migrations']:
        for row in data['schema_migrations']:
            # Convert datetime strings
            applied_at = row.get('applied_at')
            if applied_at and isinstance(applied_at, str):
                try:
                    applied_at = datetime.fromisoformat(applied_at.replace('Z', '+00:00'))
                except:
                    applied_at = None
            
            await conn.execute("""
                INSERT INTO schema_migrations (version, name, applied_at)
                VALUES ($1, $2, $3)
                ON CONFLICT (version) DO NOTHING
            """,
                row.get('version'),
                row.get('name'),
                applied_at
            )


async def migrate(sqlite_path: str, postgres_url: str):
    """Main migration function"""
    print("Starting SQLite -> PostgreSQL migration...")
    
    # Step 1: Export SQLite data
    print("Exporting data from SQLite...")
    data = await export_sqlite_data(sqlite_path)
    print(f"SUCCESS: Exported {len(data['license_keys'])} license keys")
    print(f"SUCCESS: Exported {len(data['crm_entries'])} CRM entries")
    print(f"SUCCESS: Exported {len(data['usage_logs'])} usage logs")
    
    # Step 2: Connect to PostgreSQL
    print("Connecting to PostgreSQL...")
    # Try with SSL first (for public URLs), fallback to no SSL (for internal)
    try:
        conn = await asyncpg.connect(postgres_url, ssl='require')
    except:
        # If SSL fails, try without (for internal Railway URLs)
        conn = await asyncpg.connect(postgres_url)
    
    try:
        # Step 3: Create schema
        print("Creating PostgreSQL schema...")
        await create_postgresql_schema(conn)
        print("SUCCESS: Schema created")
        
        # Step 4: Import data
        print("Importing data to PostgreSQL...")
        await import_data_to_postgresql(conn, data)
        print("SUCCESS: Data imported")
        
        # Step 5: Verify
        print("Verifying migration...")
        count = await conn.fetchval("SELECT COUNT(*) FROM license_keys")
        print(f"SUCCESS: Verified {count} license keys in PostgreSQL")
        
        print("\nMigration completed successfully!")
        print("\nIMPORTANT: Update your environment variables:")
        print("   export DB_TYPE=postgresql")
        print("   export DATABASE_URL=your_postgres_url")
        print("\n   Then restart your application.")
        
    finally:
        await conn.close()


if __name__ == "__main__":
    import sys
    
    sqlite_path = os.getenv("DATABASE_PATH", "almudeer.db")
    postgres_url = os.getenv("DATABASE_URL")
    
    if not postgres_url:
        print("❌ ERROR: DATABASE_URL environment variable required")
        print("   Example: postgresql://user:password@localhost:5432/almudeer")
        sys.exit(1)
    
    if not os.path.exists(sqlite_path):
        print(f"❌ ERROR: SQLite database not found: {sqlite_path}")
        sys.exit(1)
    
    asyncio.run(migrate(sqlite_path, postgres_url))

