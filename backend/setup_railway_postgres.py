"""
Railway PostgreSQL Setup Helper
Helps set up and test PostgreSQL connection on Railway
"""

import os
import asyncio
import sys


async def test_postgres_connection(database_url: str):
    """Test PostgreSQL connection"""
    try:
        import asyncpg
    except ImportError:
        print("ERROR: asyncpg not installed. Install with: pip install asyncpg")
        return False
    
    try:
        print("Testing PostgreSQL connection...")
        # Railway PostgreSQL requires SSL
        conn = await asyncpg.connect(
            database_url,
            ssl='require'
        )
        
        # Test query
        version = await conn.fetchval('SELECT version()')
        print(f"SUCCESS: Connected to PostgreSQL!")
        print(f"   Version: {version.split(',')[0]}")
        
        # Check if tables exist
        tables = await conn.fetch("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
        """)
        
        if tables:
            print(f"\nFound {len(tables)} tables:")
            for table in tables:
                print(f"   - {table['table_name']}")
        else:
            print("\nWARNING: No tables found. Run migration first.")
        
        await conn.close()
        return True
        
    except Exception as e:
        import traceback
        print(f"ERROR: Connection failed: {e}")
        print(f"Error type: {type(e).__name__}")
        traceback.print_exc()
        return False


async def create_schema_if_not_exists(database_url: str):
    """Create schema if it doesn't exist"""
    try:
        import asyncpg
    except ImportError:
        print("ERROR: asyncpg not installed")
        return False
    
    try:
        print("Creating database schema...")
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
        
        # Create indexes
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_license_key_hash ON license_keys(key_hash)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_crm_license_id ON crm_entries(license_key_id)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_crm_created_at ON crm_entries(created_at)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_usage_logs_license_id ON usage_logs(license_key_id)")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_license_expires_at ON license_keys(expires_at)")
        
        print("SUCCESS: Schema created successfully!")
        await conn.close()
        return True
        
    except Exception as e:
        print(f"ERROR: Schema creation failed: {e}")
        return False


def main():
    """Main function"""
    database_url = os.getenv("DATABASE_URL")
    
    if not database_url:
        print("ERROR: DATABASE_URL environment variable not set")
        print("\nTo get your Railway PostgreSQL URL:")
        print("   1. Go to Railway Dashboard")
        print("   2. Click on your PostgreSQL service")
        print("   3. Go to 'Variables' tab")
        print("   4. Copy DATABASE_URL")
        print("\n   Then run:")
        print("   export DATABASE_URL='your_url_here'")
        print("   python setup_railway_postgres.py")
        sys.exit(1)
    
    print("Railway PostgreSQL Setup Helper\n")
    print(f"Database URL: {database_url[:50]}...\n")
    
    # Test connection
    if not asyncio.run(test_postgres_connection(database_url)):
        sys.exit(1)
    
    # Ask if user wants to create schema
    print("\nDo you want to create the database schema? (y/n): ", end="")
    response = input().strip().lower()
    
    if response == 'y':
        if asyncio.run(create_schema_if_not_exists(database_url)):
            print("\nSUCCESS: Setup complete!")
            print("\nNext steps:")
            print("   1. Run migration: python migrate_to_postgresql.py")
            print("   2. Set DB_TYPE=postgresql")
            print("   3. Restart your application")
        else:
            sys.exit(1)
    else:
        print("\nSkipping schema creation")
        print("\nNext steps:")
        print("   1. Run migration: python migrate_to_postgresql.py")
        print("   2. Set DB_TYPE=postgresql")
        print("   3. Restart your application")


if __name__ == "__main__":
    main()

