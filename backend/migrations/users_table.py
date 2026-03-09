"""
Al-Mudeer - Users Table Migration
Creates users table for JWT authentication
"""


USERS_TABLE_SQLITE = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    name TEXT,
    license_key_id INTEGER,
    role TEXT DEFAULT 'user',
    is_active BOOLEAN DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_license ON users(license_key_id);
"""

USERS_TABLE_POSTGRESQL = """
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    license_key_id INTEGER REFERENCES license_keys(id),
    role VARCHAR(50) DEFAULT 'user',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_license ON users(license_key_id);
"""


async def create_users_table():
    """Create users table for JWT authentication"""
    import os
    from db_helper import get_db, execute_sql
    from logging_config import get_logger
    
    logger = get_logger(__name__)
    db_type = os.getenv("DB_TYPE", "sqlite").lower()
    
    sql = USERS_TABLE_POSTGRESQL if db_type == "postgresql" else USERS_TABLE_SQLITE
    
    # Split into individual statements
    statements = [s.strip() for s in sql.split(';') if s.strip()]
    
    async with get_db() as db:
        for statement in statements:
            try:
                await execute_sql(db, statement)
            except Exception as e:
                if "already exists" not in str(e).lower():
                    logger.debug(f"Users table creation note: {e}")
    
    logger.info("Users table created/verified for JWT auth")
