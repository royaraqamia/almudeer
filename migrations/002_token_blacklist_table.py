"""
Al-Mudeer - Token Blacklist Table Migration
Creates a fallback table for token blacklist when Redis is unavailable

Run this migration to add the token_blacklist table for production resilience.
"""

import asyncio
from db_helper import get_db, execute_sql, commit_db
from database import DB_TYPE


async def migrate():
    """Create token_blacklist table for DB fallback"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # PostgreSQL version with proper indexing
            await execute_sql(db, """
                CREATE TABLE IF NOT EXISTS token_blacklist (
                    id SERIAL PRIMARY KEY,
                    jti VARCHAR(64) UNIQUE NOT NULL,
                    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                )
            """)
            # Index for fast lookups by JTI
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_token_blacklist_jti 
                ON token_blacklist(jti)
            """)
            # Index for cleanup of expired entries
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_token_blacklist_expires 
                ON token_blacklist(expires_at)
            """)
        else:
            # SQLite version
            await execute_sql(db, """
                CREATE TABLE IF NOT EXISTS token_blacklist (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    jti TEXT UNIQUE NOT NULL,
                    expires_at TEXT NOT NULL,
                    created_at TEXT DEFAULT (datetime('now'))
                )
            """)
            # Index for fast lookups
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_token_blacklist_jti 
                ON token_blacklist(jti)
            """)
            # Index for cleanup
            await execute_sql(db, """
                CREATE INDEX IF NOT EXISTS idx_token_blacklist_expires 
                ON token_blacklist(expires_at)
            """)
        
        await commit_db(db)
    
    print("Token blacklist table migration completed successfully")


if __name__ == "__main__":
    asyncio.run(migrate())
