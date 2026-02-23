"""
Al-Mudeer - License Key Database Management
Supports both SQLite (development) and PostgreSQL (production)
"""

import os
from datetime import datetime, timedelta, timezone
from typing import Optional
import hashlib
import secrets

from db_helper import (
    get_db,
    execute_sql,
    fetch_one,
    fetch_all,
    commit_db,
    DB_TYPE,
    DATABASE_PATH,
    DATABASE_URL,
    POSTGRES_AVAILABLE
)

from db_pool import adapt_sql_for_db


async def init_database():
    """Initialize the database with required tables (supports both SQLite and PostgreSQL)"""
    async with get_db() as conn:
        if DB_TYPE == "postgresql":
            try:
                await _init_postgresql_tables(conn)
            except Exception as e:
                from logging_config import get_logger
                get_logger(__name__).debug(f"PostgreSQL tables already exist or partial init: {e}")

            # Add new columns individually to avoid one failure blocking others
            from logging_config import get_logger
            logger = get_logger(__name__)
            
            # 1. Handle Rename with data preservation
            try:
                await execute_sql(conn, "ALTER TABLE license_keys RENAME COLUMN company_name TO full_name")
                logger.info("Successfully renamed column company_name to full_name in license_keys")
            except Exception:
                # If rename fails, ensure full_name exists
                try:
                    await execute_sql(conn, "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS full_name VARCHAR(255)")
                except Exception as e:
                    logger.debug(f"Migration note: full_name column check: {e}")

            # 2. Add other missing columns
            migrations = [
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS profile_image_url TEXT",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS referral_code VARCHAR(50) UNIQUE",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS referred_by_id INTEGER REFERENCES license_keys(id)",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS is_trial BOOLEAN DEFAULT FALSE",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS referral_count INTEGER DEFAULT 0",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS username VARCHAR(255) UNIQUE",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP",
                "ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS token_version INTEGER DEFAULT 1",
                "ALTER TABLE device_sessions ADD COLUMN IF NOT EXISTS device_secret_hash VARCHAR(255)",
                "ALTER TABLE device_sessions ADD COLUMN IF NOT EXISTS device_name VARCHAR(255)",
                "ALTER TABLE device_sessions ADD COLUMN IF NOT EXISTS location VARCHAR(255)",
                "ALTER TABLE device_sessions ADD COLUMN IF NOT EXISTS user_agent TEXT"
            ]
            
            for m in migrations:
                try:
                    await execute_sql(conn, m)
                except Exception as e:
                    logger.debug(f"Migration item skipped: {m} - {e}")
        else:
            await _init_sqlite_tables(conn)
            # Migrations for existing SQLite tables
            try:
                await execute_sql(conn, "ALTER TABLE license_keys ADD COLUMN full_name TEXT")
            except: pass
            try:
                # Copy data from company_name to full_name if needed
                await execute_sql(conn, "UPDATE license_keys SET full_name = company_name WHERE full_name IS NULL")
            except: pass
            try:
                await execute_sql(conn, "ALTER TABLE license_keys ADD COLUMN profile_image_url TEXT")
            except: pass
            try:
                await execute_sql(conn, "ALTER TABLE license_keys ADD COLUMN token_version INTEGER DEFAULT 1")
            except: pass
            try:
                await execute_sql(conn, "ALTER TABLE device_sessions ADD COLUMN device_secret_hash VARCHAR(255)")
            except: pass
            try:
                await execute_sql(conn, "ALTER TABLE device_sessions ADD COLUMN device_name VARCHAR(255)")
            except: pass
            try:
                await execute_sql(conn, "ALTER TABLE device_sessions ADD COLUMN location VARCHAR(255)")
            except: pass
            try:
                await execute_sql(conn, "ALTER TABLE device_sessions ADD COLUMN user_agent TEXT")
            except: pass
            await commit_db(conn)
    
    # === Startup migration: Backfill username for all license_keys ===
    # The presence system relies on license_keys.username to match peers.
    # If username is NULL, "last seen" will never display for that user.
    try:
        from logging_config import get_logger
        logger = get_logger(__name__)
        
        async with get_db() as db:
            # First, ensure the tables are initialized if they haven't been already
            # (In case this runs after an aborted previous startup)
            if DB_TYPE == "postgresql":
                # Ensure last_seen_at column exists in customers (it might be missing in very old versions)
                try:
                    await execute_sql(db, "ALTER TABLE customers ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP")
                except Exception: pass
            
            # Find all license_keys with NULL username
            missing = await fetch_all(db, """
                SELECT lk.id, u.email 
                FROM license_keys lk
                JOIN users u ON u.license_key_id = lk.id 
                WHERE lk.username IS NULL
                ORDER BY u.id ASC
            """, [])
            
            if missing:
                logger.info(f"Backfilling username for {len(missing)} license keys")
                for row in missing:
                    email = row.get("email")
                    license_id = row["id"]
                    if email:
                        try:
                            await execute_sql(db, "UPDATE license_keys SET username = ? WHERE id = ? AND username IS NULL", (email, license_id))
                            logger.info(f"  Backfilled username='{email}' for license_key id={license_id}")
                        except Exception as e:
                            logger.warning(f"  Failed to backfill username for license_key id={license_id}: {e}")
                await commit_db(db)
                logger.info("Username backfill migration complete")
    except Exception as e:
        from logging_config import get_logger
        get_logger(__name__).warning(f"Username backfill migration skipped or failed: {e}")
    
    return


async def _init_sqlite_tables(db):
    """Initialize SQLite tables"""
    # License keys table
    await db.execute("""
        CREATE TABLE IF NOT EXISTS license_keys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key_hash TEXT UNIQUE NOT NULL,
            license_key_encrypted TEXT,
            full_name TEXT NOT NULL,
            profile_image_url TEXT,
            contact_email TEXT,
            username TEXT UNIQUE,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP,
            last_seen_at TIMESTAMP,
            referral_code TEXT UNIQUE,
            referred_by_id INTEGER,
            is_trial BOOLEAN DEFAULT FALSE,
            referral_count INTEGER DEFAULT 0,
            phone TEXT,
            email TEXT,
            token_version INTEGER DEFAULT 1,
            FOREIGN KEY (referred_by_id) REFERENCES license_keys(id)
        )
    """)
    
    # CRM entries table
    await db.execute("""
        CREATE TABLE IF NOT EXISTS crm_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            license_key_id INTEGER,
            sender_name TEXT,
            sender_contact TEXT,
            message_type TEXT,
            intent TEXT,
            extracted_data TEXT,
            original_message TEXT,
            draft_response TEXT,
            status TEXT DEFAULT 'جديد',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)

    # Customers table (for detailed profile)
    await db.execute("""
        CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            license_key_id INTEGER,
            name TEXT,
            contact TEXT UNIQUE NOT NULL,
            phone TEXT,
            email TEXT,
            type TEXT DEFAULT 'Regular',
            total_spend REAL DEFAULT 0.0,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)

    # Orders table
    await db.execute("""
        CREATE TABLE IF NOT EXISTS orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_ref TEXT UNIQUE NOT NULL,
            customer_contact TEXT,
            status TEXT DEFAULT 'Pending',
            total_amount REAL,
            items TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP,
            FOREIGN KEY (customer_contact) REFERENCES customers(contact)
        )
    """)

    # App Config table (Source of Truth for Versioning)
    await db.execute("""
        CREATE TABLE IF NOT EXISTS app_config (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Version History table
    await db.execute("""
        CREATE TABLE IF NOT EXISTS version_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version TEXT NOT NULL,
            build_number INTEGER NOT NULL,
            release_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            changelog_ar TEXT,
            changelog_en TEXT,
            changes_json TEXT
        )
    """)

    # Update Events table (for analytics)
    await db.execute("""
        CREATE TABLE IF NOT EXISTS update_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event TEXT NOT NULL,
            from_build INTEGER,
            to_build INTEGER,
            device_id TEXT,
            device_type TEXT,
            license_key TEXT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Knowledge Base Documents
    await db.execute("""
        CREATE TABLE IF NOT EXISTS knowledge_documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            license_key_id INTEGER NOT NULL,
            user_id TEXT,
            source TEXT DEFAULT 'manual',
            text TEXT,
            file_path TEXT,
            file_size INTEGER,
            mime_type TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP,
            deleted_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)

    # Device Sessions table (Refresh Token Rotation & Management)
    await db.execute("""
        CREATE TABLE IF NOT EXISTS device_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            license_key_id INTEGER NOT NULL,
            family_id VARCHAR(255) NOT NULL,
            refresh_token_jti VARCHAR(255) NOT NULL,
            device_fingerprint TEXT,
            ip_address VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP NOT NULL,
            is_revoked BOOLEAN DEFAULT FALSE,
            device_secret_hash VARCHAR(255),
            device_name VARCHAR(255),
            location VARCHAR(255),
            user_agent TEXT,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """)

    # Create indexes for performance
    await db.execute("""
        CREATE INDEX IF NOT EXISTS idx_license_key_hash 
        ON license_keys(key_hash)
    """)
    
    await db.execute("""
        CREATE INDEX IF NOT EXISTS idx_crm_license_id 
        ON crm_entries(license_key_id)
    """)
    
    await db.execute("""
        CREATE INDEX IF NOT EXISTS idx_crm_created_at 
        ON crm_entries(created_at)
    """)
    
    await db.execute("""
        CREATE INDEX IF NOT EXISTS idx_license_expires_at 
        ON license_keys(expires_at)
    """)
    
    await db.execute("""
        CREATE INDEX IF NOT EXISTS idx_device_sessions_jti 
        ON device_sessions(refresh_token_jti)
    """)
    
    await db.execute("""
        CREATE INDEX IF NOT EXISTS idx_device_sessions_family 
        ON device_sessions(family_id)
    """)
    
    await db.commit()


async def _init_postgresql_tables(conn):
    """Initialize PostgreSQL tables"""
    # 1. Device Sessions table (Refresh Token Rotation & Management)
    # This MUST be first because subsequent migrations and sequence fixes depend on it.
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS device_sessions (
            id SERIAL PRIMARY KEY,
            license_key_id INTEGER NOT NULL,
            family_id VARCHAR(255) NOT NULL,
            refresh_token_jti VARCHAR(255) NOT NULL,
            device_fingerprint TEXT,
            ip_address VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW(),
            last_used_at TIMESTAMP DEFAULT NOW(),
            expires_at TIMESTAMP NOT NULL,
            is_revoked BOOLEAN DEFAULT FALSE,
            device_secret_hash VARCHAR(255),
            device_name VARCHAR(255),
            location VARCHAR(255),
            user_agent TEXT
        )
    """))

    # 2. License keys table
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS license_keys (
            id SERIAL PRIMARY KEY,
            key_hash VARCHAR(255) UNIQUE NOT NULL,
            license_key_encrypted TEXT,
            full_name VARCHAR(255) NOT NULL,
            profile_image_url TEXT,
            contact_email VARCHAR(255),
            username VARCHAR(255) UNIQUE,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT NOW(),
            expires_at TIMESTAMP,
            referral_code VARCHAR(50) UNIQUE,
            referred_by_id INTEGER REFERENCES license_keys(id),
            is_trial BOOLEAN DEFAULT FALSE,
            referral_count INTEGER DEFAULT 0,
            last_seen_at TIMESTAMP,
            phone VARCHAR(255),
            email VARCHAR(255),
            token_version INTEGER DEFAULT 1
        )
    """))
    
    # CRM entries table
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS crm_entries (
            id SERIAL PRIMARY KEY,
            license_key_id INTEGER,
            sender_name VARCHAR(255),
            sender_contact VARCHAR(255),
            message_type VARCHAR(255),
            intent VARCHAR(255),
            extracted_data TEXT,
            original_message TEXT,
            draft_response TEXT,
            status VARCHAR(255) DEFAULT 'جديد',
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """))

    # Customers table (for detailed profile)
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS customers (
            id SERIAL PRIMARY KEY,
            license_key_id INTEGER,
            name VARCHAR(255),
            contact VARCHAR(255) UNIQUE NOT NULL,
            phone VARCHAR(255),
            email VARCHAR(255),
            type VARCHAR(50) DEFAULT 'Regular',
            total_spend REAL DEFAULT 0.0,
            notes TEXT,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """))

    # Migration: Ensure 'contact' column exists if the table was created by older logic
    try:
        await conn.execute("ALTER TABLE customers ADD COLUMN IF NOT EXISTS contact VARCHAR(255) UNIQUE")
    except Exception:
        pass

    # Orders table
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            order_ref VARCHAR(255) UNIQUE NOT NULL,
            customer_contact VARCHAR(255),
            status VARCHAR(50) DEFAULT 'Pending',
            total_amount REAL,
            items TEXT,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP,
            FOREIGN KEY (customer_contact) REFERENCES customers(contact)
        )
    """))

    # App Config table (Source of Truth for Versioning)
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS app_config (
            key VARCHAR(255) PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP DEFAULT NOW()
        )
    """))

    # Version History table
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS version_history (
            id SERIAL PRIMARY KEY,
            version VARCHAR(50) NOT NULL,
            build_number INTEGER NOT NULL,
            release_date TIMESTAMP DEFAULT NOW(),
            changelog_ar TEXT,
            changelog_en TEXT,
            changes_json TEXT
        )
    """))

    # Update Events table (for analytics)
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS update_events (
            id SERIAL PRIMARY KEY,
            event VARCHAR(50) NOT NULL,
            from_build INTEGER,
            to_build INTEGER,
            device_id TEXT,
            device_type TEXT,
            license_key TEXT,
            timestamp TIMESTAMP DEFAULT NOW()
        )
    """))

    # Knowledge Base Documents
    await conn.execute(adapt_sql_for_db("""
        CREATE TABLE IF NOT EXISTS knowledge_documents (
            id SERIAL PRIMARY KEY,
            license_key_id INTEGER NOT NULL,
            user_id TEXT,
            source VARCHAR(255) DEFAULT 'manual',
            text TEXT,
            file_path TEXT,
            file_size INTEGER,
            mime_type VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP,
            deleted_at TIMESTAMP,
            FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
        )
    """))

    # Fix sequences if out of sync to prevent "duplicate key value violates unique constraint" errors
    try:
        tables_with_sequences = [
            ("license_keys", "license_keys_id_seq"),
            ("crm_entries", "crm_entries_id_seq"),
            ("customers", "customers_id_seq"),
            ("orders", "orders_id_seq"),
            ("version_history", "version_history_id_seq"),
            ("update_events", "update_events_id_seq"),
            ("knowledge_documents", "knowledge_documents_id_seq"),
            ("device_sessions", "device_sessions_id_seq")
        ]
        
        for table, seq in tables_with_sequences:
            try:
                # Ensure the table exists before trying to fix its sequence
                # Note: adaptation of SQL for PG is handled in execute_sql and adapt_sql_for_db
                await conn.execute(f"SELECT setval('{seq}', COALESCE((SELECT MAX(id) FROM {table}), 1), COALESCE((SELECT MAX(id) FROM {table}) IS NOT NULL, false))")
            except Exception as e:
                from logging_config import get_logger
                get_logger(__name__).debug(f"Sequence fix skipped for {table}: {e}")
                pass
    except Exception:
        pass

    # Add foreign key to device_sessions after license_keys is created
    await conn.execute(adapt_sql_for_db("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'device_sessions_license_key_id_fkey') THEN
                ALTER TABLE device_sessions
                ADD CONSTRAINT device_sessions_license_key_id_fkey
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id);
            END IF;
        END
        $$;
    """))

    # Create indexes for performance
    await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_license_key_hash 
        ON license_keys(key_hash)
    """)
    
    await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_crm_license_id 
        ON crm_entries(license_key_id)
    """)
    
    await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_crm_created_at 
        ON crm_entries(created_at)
    """)
    
    await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_license_expires_at 
        ON license_keys(expires_at)
    """)
    
    await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_device_sessions_jti 
        ON device_sessions(refresh_token_jti)
    """)
    
    await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_device_sessions_family 
        ON device_sessions(family_id)
    """)


def hash_license_key(key: str) -> str:
    """Hash a license key for secure storage"""
    return hashlib.sha256(key.encode()).hexdigest()


async def generate_license_key(
    full_name: str,
    days_valid: int = 365,
    is_trial: bool = False,
    referred_by_id: Optional[int] = None,
    username: Optional[str] = None
) -> str:
    """Generate a new license key and store it in the database"""
    # Generate a readable license key format: MUDEER-XXXX-XXXX-XXXX
    raw_key = f"MUDEER-{secrets.token_hex(2).upper()}-{secrets.token_hex(2).upper()}-{secrets.token_hex(2).upper()}"
    key_hash = hash_license_key(raw_key)
    
    # Generate a unique referral code (short)
    referral_code = secrets.token_hex(3).upper() # 6 characters
    
    # Encrypt the original key for storage
    from security import encrypt_sensitive_data
    encrypted_key = encrypt_sensitive_data(raw_key)
    
    expires_at = datetime.now() + timedelta(days=days_valid)
    
    from db_helper import get_db, execute_sql, fetch_one, commit_db
    
    async with get_db() as db:
        try:
            if DB_TYPE == "postgresql":
                if referred_by_id:
                    # Use a CTE to insert and increment referral count atomically
                    # Note: db_pool handles postgres parameter replacement automatically
                    row = await fetch_one(db, """
                        WITH new_key AS (
                            INSERT INTO license_keys (key_hash, license_key_encrypted, full_name, expires_at, is_trial, referred_by_id, referral_code, username)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            RETURNING id, referred_by_id
                        )
                        UPDATE license_keys 
                        SET referral_count = referral_count + 1 
                        FROM new_key WHERE license_keys.id = new_key.referred_by_id
                        RETURNING new_key.id
                    """, [key_hash, encrypted_key, full_name, expires_at, is_trial, referred_by_id, referral_code, username])
                else:
                    row = await fetch_one(db, """
                        INSERT INTO license_keys (key_hash, license_key_encrypted, full_name, expires_at, is_trial, referred_by_id, referral_code, username)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        RETURNING id
                    """, [key_hash, encrypted_key, full_name, expires_at, is_trial, referred_by_id, referral_code, username])
                
                return raw_key
            else:
                cursor = await execute_sql(db, """
                    INSERT INTO license_keys (key_hash, license_key_encrypted, full_name, expires_at, is_trial, referred_by_id, referral_code, username)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (key_hash, encrypted_key, full_name, expires_at.isoformat(), is_trial, referred_by_id, referral_code, username))
                
                if referred_by_id:
                    await execute_sql(db, "UPDATE license_keys SET referral_count = referral_count + 1 WHERE id = ?", [referred_by_id])
                
                await commit_db(db)
                return raw_key
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).error(f"Failed to generate license key: {e}")
            raise
    
    return raw_key


async def get_license_key_by_id(license_id: int) -> Optional[str]:
    """Get the original license key by ID (decrypted)"""
    from security import decrypt_sensitive_data
    from logging_config import get_logger
    
    logger = get_logger(__name__)
    
    from db_helper import get_db, fetch_one
    
    async with get_db() as db:
        row = await fetch_one(db, """
            SELECT license_key_encrypted FROM license_keys WHERE id = ?
        """, [license_id])
        
        if not row:
            logger.warning(f"Subscription {license_id} not found")
            return None
        
        if not row.get('license_key_encrypted'):
            logger.warning(f"License key encrypted field is NULL for subscription {license_id} - this is an old subscription created before encryption was added")
            return None
        
        encrypted_key = row['license_key_encrypted']
        try:
            decrypted = decrypt_sensitive_data(encrypted_key)
            return decrypted
        except Exception as e:
            logger.error(f"Failed to decrypt license key for subscription {license_id}: {e}")
            return None


async def validate_license_key(key: str) -> dict:
    """Validate a license key and return its details"""
    # Try cache first
    try:
        from cache import get_cached_license_validation, cache_license_validation
        cached_result = await get_cached_license_validation(key)
        if cached_result is not None:
            return cached_result
    except ImportError:
        # Cache not available, continue with DB lookup
        pass
    
    key_hash = hash_license_key(key)
    
    from db_helper import get_db, fetch_one
    async with get_db() as db:
        row = await fetch_one(db, """
            SELECT * FROM license_keys WHERE key_hash = ?
        """, [key_hash])
        
        if not row:
            return {"valid": False, "error": "مفتاح الاشتراك غير صالح"}
        
        row_dict = dict(row)
    
    # Check if active
    if not row_dict["is_active"]:
        return {"valid": False, "error": "تم تعطيل هذا الاشتراك"}
    
    # Helper for robust date parsing
    def parse_datetime(val) -> Optional[datetime]:
        if not val:
            return None
        if isinstance(val, datetime):
            return val
        if hasattr(val, 'isoformat'): # Handle other date-like objects
            return datetime.fromisoformat(val.isoformat())
        try:
            # Handle standard ISO strings and split out potential timezone/extra info
            clean_val = str(val).replace('Z', '+00:00').split('.')[0] # Remove microsecs if bothering
            if ' ' in clean_val and 'T' not in clean_val:
                clean_val = clean_val.replace(' ', 'T')
            return datetime.fromisoformat(clean_val)
        except (ValueError, TypeError):
            return None

    # Check expiration
    expires_at = parse_datetime(row_dict.get("expires_at"))
    if expires_at:
        # Normalize to aware UTC for comparison
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        
        now_utc = datetime.now(timezone.utc)
        if now_utc > expires_at:
            return {"valid": False, "error": "انتهت صلاحية الاشتراك"}
    
    # Prepare result
    expires_at_str = None
    if row_dict.get("expires_at"):
        if isinstance(row_dict["expires_at"], str):
            expires_at_str = row_dict["expires_at"]
        elif hasattr(row_dict["expires_at"], 'isoformat'):
            expires_at_str = row_dict["expires_at"].isoformat()
        else:
            expires_at_str = str(row_dict["expires_at"])
    
    result = {
        "valid": True,
        "license_id": row_dict["id"],
        "full_name": row_dict.get("full_name") or row_dict.get("company_name"),
        "profile_image_url": row_dict.get("profile_image_url"),
        "created_at": str(row_dict["created_at"]) if row_dict.get("created_at") else None,
        "expires_at": expires_at_str,
        "is_trial": bool(row_dict.get("is_trial")),
        "referral_code": row_dict.get("referral_code"),
        "referral_count": row_dict.get("referral_count", 0),
        "username": row_dict.get("username"),
        "requests_remaining": 999999 # Unlimited
    }
    
    # Cache the result (5 minutes TTL)
    try:
        from cache import cache_license_validation
        await cache_license_validation(key, result, ttl=300)
    except ImportError:
        pass
    
    return result


async def increment_usage(license_id: int, action_type: str, input_preview: str = None):
    """Increment usage counter (Legacy - No longer used)"""
    # Logic removed to simplify system: max daily requests no longer enforced
    return


async def save_crm_entry(
    license_id: int,
    sender_name: str,
    sender_contact: str,
    message_type: str,
    intent: str,
    extracted_data: str,
    original_message: str,
    draft_response: str
) -> int:
    """Save a CRM entry and return its ID"""
    async with get_db() as db:
        # Note: adapt_sql_for_db in execute_sql handles PostgreSQL placeholder conversion
        # but RETURNING is PG specific. db_helper handles this via the centralized adapt_sql.
        
        # Actually for INSERT RETURNING, we might need a custom approach if it's not handled automatically.
        # But execute_sql uses db_pool.execute, which returns the result. For PG it's the result of conn.execute.
        # For SQLite it returns the cursor.
        
        sql = """
            INSERT INTO crm_entries 
            (license_key_id, sender_name, sender_contact, message_type, intent, 
             extracted_data, original_message, draft_response)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        params = [license_id, sender_name, sender_contact, message_type, intent,
                  extracted_data, original_message, draft_response]
        
        if DB_TYPE == "postgresql":
            sql += " RETURNING id"
            row = await fetch_one(db, sql, params)
            return row["id"] if row else 0
        else:
            # For SQLite, execute_sql returns the cursor (standard behavior in my update to db_pool)
            cursor = await execute_sql(db, sql, params)
            await commit_db(db)
            return cursor.lastrowid


async def get_crm_entries(license_id: int, limit: int = 50) -> list:
    """Get CRM entries for a license"""
    async with get_db() as db:
        rows = await fetch_all(db, """
            SELECT * FROM crm_entries 
            WHERE license_key_id = ? 
            ORDER BY created_at DESC 
            LIMIT ?
        """, [license_id, limit])
        return [dict(row) for row in rows]


async def get_entry_by_id(entry_id: int, license_id: int) -> Optional[dict]:
    """Get a specific CRM entry"""
    async with get_db() as db:
        row = await fetch_one(db, """
            SELECT * FROM crm_entries 
            WHERE id = ? AND license_key_id = ?
        """, [entry_id, license_id])
        return dict(row) if row else None


# Initialize demo license key for testing
async def create_demo_license():
    """Create a demo license key if none exists"""
    async with get_db() as db:
        row = await fetch_one(db, "SELECT COUNT(*) as count FROM license_keys")
        count = row["count"] if row else 0
    
    if count == 0:
        # Create demo license
        demo_key = await generate_license_key(
            full_name="مستخدم تجريبي",
            days_valid=365
        )
        print(f"Demo License Key Created: {demo_key}")
        return demo_key
    return None


async def get_customer(contact: str) -> Optional[dict]:
    """Get customer details by contact (SQLite only for now for simplicity)"""
    # Assuming SQLite for tools MVP
    async with get_db() as db:
        row = await fetch_one(db, "SELECT * FROM customers WHERE contact = ?", [contact])
        return dict(row) if row else None
    return None

async def get_order_by_ref(order_ref: str) -> Optional[dict]:
    """Get order details by reference"""
    async with get_db() as db:
        row = await fetch_one(db, "SELECT * FROM orders WHERE order_ref = ?", [order_ref])
        return dict(row) if row else None
    return None

async def upsert_customer_lead(name: str, contact: str, notes: str) -> int:
    """Create or update a customer lead using atomic UPSERT patterns"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # Senior Pattern: Atomic UPSERT with RETURNING for PostgreSQL
            sql = """
                INSERT INTO customers (name, contact, type, notes) 
                VALUES (?, ?, 'Lead', ?)
                ON CONFLICT (contact) DO UPDATE 
                SET notes = CASE 
                    WHEN customers.notes IS NULL OR customers.notes = '' THEN EXCLUDED.notes 
                    ELSE customers.notes || '\n' || EXCLUDED.notes 
                END,
                updated_at = NOW()
                RETURNING id
            """
            row = await fetch_one(db, sql, [name, contact, notes])
            return row["id"] if row else 0
        else:
            # SQLite UPSERT (supported in 3.24+)
            sql = """
                INSERT INTO customers (name, contact, type, notes) 
                VALUES (?, ?, 'Lead', ?)
                ON CONFLICT(contact) DO UPDATE SET
                notes = CASE 
                    WHEN notes IS NULL OR notes = '' THEN excluded.notes 
                    ELSE notes || '\n' || excluded.notes 
                END,
                updated_at = CURRENT_TIMESTAMP
            """
            cursor = await execute_sql(db, sql, [name, contact, notes])
            await commit_db(db)
            
            # If the conflict resolution didn't return an ID automatically, fetch it
            row = await fetch_one(db, "SELECT id FROM customers WHERE contact = ?", [contact])
            return row["id"] if row else 0
    return 0


async def save_update_event(
    event: str,
    from_build: int,
    to_build: int,
    device_id: Optional[str] = None,
    device_type: Optional[str] = None,
    license_key: Optional[str] = None
):
    """Save an update event to the database"""
    async with get_db() as db:
        await execute_sql(db, """
            INSERT INTO update_events 
            (event, from_build, to_build, device_id, device_type, license_key)
            VALUES (?, ?, ?, ?, ?, ?)
        """, [event, from_build, to_build, device_id, device_type, license_key])
        await commit_db(db)


async def get_update_events(limit: int = 100) -> list:
    """Get recent update events"""
    async with get_db() as db:
        rows = await fetch_all(db, """
            SELECT * FROM update_events 
            ORDER BY timestamp DESC 
            LIMIT ?
        """, [limit])
        return [dict(row) for row in rows]


# ============ App Config & Versioning ============

async def get_app_config(key: str) -> Optional[str]:
    """Get a configuration value by key"""
    async with get_db() as db:
        row = await fetch_one(db, "SELECT value FROM app_config WHERE key = ?", [key])
        return row["value"] if row else None


async def get_all_app_config() -> dict:
    """Get all configuration values as a dictionary"""
    async with get_db() as db:
        rows = await fetch_all(db, "SELECT key, value FROM app_config")
        return {row["key"]: row["value"] for row in rows}


async def set_app_config(key: str, value: str):
    """Set a configuration value"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                INSERT INTO app_config (key, value, updated_at) 
                VALUES (?, ?, NOW())
                ON CONFLICT (key) DO UPDATE 
                SET value = EXCLUDED.value, updated_at = NOW()
            """, [key, value])
        else:
            await execute_sql(db, """
                INSERT INTO app_config (key, value, updated_at) 
                VALUES (?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(key) DO UPDATE 
                SET value = excluded.value, updated_at = CURRENT_TIMESTAMP
            """, [key, value])
        await commit_db(db)


async def add_version_history(
    version: str,
    build_number: int,
    changelog_ar: str,
    changelog_en: str,
    changes_json: str
):
    """Add a new version to history"""
    async with get_db() as db:
        await execute_sql(db, """
            INSERT INTO version_history 
            (version, build_number, changelog_ar, changelog_en, changes_json)
            VALUES (?, ?, ?, ?, ?)
        """, [version, build_number, changelog_ar, changelog_en, changes_json])
        await commit_db(db)


async def get_version_history_list(limit: int = 10) -> list:
    """Get recent version history"""
    async with get_db() as db:
        rows = await fetch_all(db, """
            SELECT * FROM version_history 
            ORDER BY build_number DESC 
            LIMIT ?
        """, [limit])
        return [dict(row) for row in rows]


# ============ Version Analytics ============

async def get_version_distribution() -> list:
    """Get distribution of users across build numbers based on update events"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # Get latest build per device from update events
            rows = await fetch_all(db, """
                WITH latest_builds AS (
                    SELECT DISTINCT ON (COALESCE(device_id, license_key))
                        COALESCE(device_id, license_key) as identifier,
                        from_build as build_number,
                        device_type,
                        timestamp
                    FROM update_events
                    WHERE from_build IS NOT NULL
                    ORDER BY COALESCE(device_id, license_key), timestamp DESC
                )
                SELECT 
                    build_number,
                    device_type,
                    COUNT(*) as user_count
                FROM latest_builds
                GROUP BY build_number, device_type
                ORDER BY build_number DESC
            """)
            return rows
        else:
            # SQLite version using subquery
            rows = await fetch_all(db, """
                SELECT 
                    from_build as build_number,
                    device_type,
                    COUNT(DISTINCT COALESCE(device_id, license_key)) as user_count
                FROM update_events
                WHERE from_build IS NOT NULL
                GROUP BY from_build, device_type
                ORDER BY from_build DESC
            """)
            return rows


async def get_update_funnel(days: int = 30) -> dict:
    """Get update funnel metrics (viewed -> clicked -> installed)"""
    cutoff = datetime.now() - timedelta(days=days)
    
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            row = await fetch_one(db, """
                SELECT 
                    COUNT(*) FILTER (WHERE event = 'viewed') as views,
                    COUNT(*) FILTER (WHERE event = 'clicked_update') as clicks,
                    COUNT(*) FILTER (WHERE event = 'clicked_later') as laters,
                    COUNT(*) FILTER (WHERE event = 'installed') as installs,
                    COUNT(DISTINCT COALESCE(device_id, license_key)) as unique_devices
                FROM update_events
                WHERE timestamp >= ?
            """, [cutoff])
            return row or {}
        else:
            cutoff_str = cutoff.isoformat()
            row = await fetch_one(db, """
                SELECT 
                    SUM(CASE WHEN event = 'viewed' THEN 1 ELSE 0 END) as views,
                    SUM(CASE WHEN event = 'clicked_update' THEN 1 ELSE 0 END) as clicks,
                    SUM(CASE WHEN event = 'clicked_later' THEN 1 ELSE 0 END) as laters,
                    SUM(CASE WHEN event = 'installed' THEN 1 ELSE 0 END) as installs,
                    COUNT(DISTINCT COALESCE(device_id, license_key)) as unique_devices
                FROM update_events
                WHERE timestamp >= ?
            """, [cutoff_str])
            if row:
                return {
                    "views": row.get("views") or 0,
                    "clicks": row.get("clicks") or 0,
                    "laters": row.get("laters") or 0,
                    "installs": row.get("installs") or 0,
                    "unique_devices": row.get("unique_devices") or 0
                }
            return {}


async def get_time_to_update_metrics() -> dict:
    """Calculate median and average time from update release to adoption"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # Get time between 'viewed' and 'installed' events per device
            row = await fetch_one(db, """
                WITH update_times AS (
                    SELECT 
                        COALESCE(device_id, license_key) as identifier,
                        MIN(CASE WHEN event = 'viewed' THEN timestamp END) as first_view,
                        MIN(CASE WHEN event = 'installed' THEN timestamp END) as installed_at
                    FROM update_events
                    WHERE event IN ('viewed', 'installed')
                    GROUP BY identifier
                    HAVING MIN(CASE WHEN event = 'installed' THEN timestamp END) IS NOT NULL
                )
                SELECT 
                    COUNT(*) as total_updates,
                    AVG(EXTRACT(EPOCH FROM (installed_at - first_view))) as avg_seconds,
                    PERCENTILE_CONT(0.5) WITHIN GROUP (
                        ORDER BY EXTRACT(EPOCH FROM (installed_at - first_view))
                    ) as median_seconds
                FROM update_times
                WHERE first_view IS NOT NULL
            """, [])
            if row:
                return {
                    "total_updates": row.get("total_updates") or 0,
                    "avg_hours": round((row.get("avg_seconds") or 0) / 3600, 1),
                    "median_hours": round((row.get("median_seconds") or 0) / 3600, 1)
                }
            return {"total_updates": 0, "avg_hours": 0, "median_hours": 0}
        else:
            # SQLite doesn't have PERCENTILE_CONT, return simpler metrics
            row = await fetch_one(db, """
                SELECT COUNT(DISTINCT device_id) as total_updates
                FROM update_events
                WHERE event = 'installed'
            """, [])
            return {
                "total_updates": row.get("total_updates") if row else 0,
                "avg_hours": 0,
                "median_hours": 0,
                "note": "Detailed metrics available with PostgreSQL"
            }
