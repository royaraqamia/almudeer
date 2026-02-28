"""
Database connection pool manager
Supports both SQLite (current) and PostgreSQL (future migration)
"""

import os
from typing import Optional, Any
import aiosqlite

# Try to import asyncpg for PostgreSQL (optional)
try:
    import asyncpg
    POSTGRES_AVAILABLE = True
except ImportError:
    POSTGRES_AVAILABLE = False
    asyncpg = None

# Global Constants for Database Compatibility
DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()
DATABASE_PATH = os.getenv("DATABASE_PATH", "almudeer.db")
DATABASE_URL = os.getenv("DATABASE_URL")
ID_PK = "SERIAL PRIMARY KEY" if DB_TYPE == "postgresql" else "INTEGER PRIMARY KEY AUTOINCREMENT"
TIMESTAMP_NOW = "TIMESTAMP DEFAULT NOW()" if DB_TYPE == "postgresql" else "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
INT_TYPE = "INTEGER"
TEXT_TYPE = "TEXT"

def adapt_sql_for_db(sql: str) -> str:
    """Adapt SQL syntax for current database type"""
    if DB_TYPE == "postgresql":
        sql = sql.replace("INTEGER PRIMARY KEY AUTOINCREMENT", "SERIAL PRIMARY KEY")
        sql = sql.replace("AUTOINCREMENT", "")
        sql = sql.replace("TIMESTAMP DEFAULT CURRENT_TIMESTAMP", "TIMESTAMP DEFAULT NOW()")
    return sql

def _convert_sql_params(sql: str, params: list) -> str:
    """Convert SQLite ? placeholders to PostgreSQL $1, $2, etc."""
    if DB_TYPE == "postgresql" and params:
        param_index = 1
        result = ""
        i = 0
        while i < len(sql):
            if sql[i] == '?' and (i == 0 or sql[i-1] != "'"):
                result += f"${param_index}"
                param_index += 1
            else:
                result += sql[i]
            i += 1
        return result
    return sql

def _normalize_params(params: Any) -> list:
    """Normalize parameters for PostgreSQL/SQLite"""
    if params is None:
        return []
    if isinstance(params, (tuple, list)):
        params_list = list(params)
    else:
        params_list = [params]
    
    import datetime
    for i, p in enumerate(params_list):
        if isinstance(p, datetime.datetime):
            if DB_TYPE == "postgresql":
                if p.tzinfo:
                    params_list[i] = p.astimezone(datetime.timezone.utc).replace(tzinfo=None)
    return params_list

class DatabasePool:
    """Unified database connection pool manager"""
    
    def __init__(self):
        self.db_type = DB_TYPE
        self.pool: Optional[Any] = None
        self.sqlite_path = DATABASE_PATH
        
        # PostgreSQL connection string
        self.postgres_url = DATABASE_URL
    
    async def initialize(self):
        """Initialize the appropriate database connection pool"""
        if self.db_type == "postgresql" and POSTGRES_AVAILABLE and self.postgres_url:
            await self._init_postgres()
        else:
            # Use SQLite (current default)
            self._init_sqlite()
    
    def _init_sqlite(self):
        """Initialize SQLite (no pooling, but prepared for future)"""
        # SQLite doesn't need explicit pooling, but we prepare the interface
        self.pool = None
        self.db_type = "sqlite"
    
    async def _init_postgres(self):
        """Initialize PostgreSQL connection pool"""
        if not POSTGRES_AVAILABLE:
            raise ImportError("asyncpg is required for PostgreSQL. Install with: pip install asyncpg")

        if not self.postgres_url:
            raise ValueError("DATABASE_URL environment variable required for PostgreSQL")

        # P1-5: Configurable pool settings via environment variables
        min_size = int(os.getenv("DB_POOL_MIN_SIZE", "10"))  # Keep 10 connections warm (increased from 5)
        max_size = int(os.getenv("DB_POOL_MAX_SIZE", "50"))  # Allow up to 50 concurrent (increased from 30)
        query_timeout = int(os.getenv("DB_QUERY_TIMEOUT", "60"))  # Configurable timeout
        max_inactive_connection_lifetime = int(os.getenv("DB_MAX_IDLE", "300"))  # 5 minutes
        
        # Create connection pool with optimized settings for scalability
        self.pool = await asyncpg.create_pool(
            self.postgres_url,
            min_size=min_size,
            max_size=max_size,
            command_timeout=query_timeout,
            statement_cache_size=100,
            max_inactive_connection_lifetime=max_inactive_connection_lifetime,
            # P1-5: Additional performance settings
            max_queries=50000,  # Recycle connections after 50k queries
            max_cached_statement_lifetime=300,  # Cache statements for 5 minutes
        )
        self.db_type = "postgresql"
    
    async def acquire(self):
        """Acquire a database connection"""
        if self.db_type == "postgresql" and self.pool:
            return await self.pool.acquire()
        elif self.db_type == "sqlite":
            # Return SQLite connection (no pooling)
            return await aiosqlite.connect(self.sqlite_path)
        else:
            raise RuntimeError("Database not initialized")
    
    async def release(self, conn):
        """Release a database connection
        
        P0-5 FIX: Added error handling to prevent connection leaks.
        Even if close() fails, we ensure the connection reference is cleared.
        """
        try:
            if self.db_type == "postgresql" and self.pool:
                await self.pool.release(conn)
            elif self.db_type == "sqlite":
                await conn.close()
        except Exception as e:
            # P0-5 FIX: Log the error but don't re-raise
            # Re-raising could cause the caller to retry, leading to more leaks
            from logging_config import get_logger
            logger = get_logger(__name__)
            logger.error(f"Failed to release database connection: {e}")
        finally:
            # P0-5 FIX: Always clear the connection reference
            # This ensures garbage collection can proceed even if close failed
            conn = None
    
    async def execute(self, query: str, params: Any = None):
        """Execute a query (convenience method)"""
        query = adapt_sql_for_db(query)
        params_list = _normalize_params(params)
        
        conn = await self.acquire()
        try:
            if self.db_type == "postgresql":
                pg_query = _convert_sql_params(query, params_list)
                if params_list:
                    result = await conn.execute(pg_query, *params_list)
                else:
                    result = await conn.execute(pg_query)
            else:
                cursor = await conn.execute(query, params_list or ())
                await conn.commit()
                result = cursor
            return result
        finally:
            await self.release(conn)
    
    async def fetch(self, query: str, params: Any = None):
        """Fetch rows from database"""
        query = adapt_sql_for_db(query)
        params_list = _normalize_params(params)
        
        conn = await self.acquire()
        try:
            if self.db_type == "postgresql":
                pg_query = _convert_sql_params(query, params_list)
                if params_list:
                    rows = await conn.fetch(pg_query, *params_list)
                else:
                    rows = await conn.fetch(pg_query)
                return [dict(row) for row in rows]
            else:
                conn.row_factory = aiosqlite.Row
                cursor = await conn.execute(query, params_list or ())
                rows = await cursor.fetchall()
                return [dict(row) for row in rows]
        finally:
            await self.release(conn)
    
    async def fetchone(self, query: str, params: Any = None):
        """Fetch a single row"""
        query = adapt_sql_for_db(query)
        params_list = _normalize_params(params)
        
        conn = await self.acquire()
        try:
            if self.db_type == "postgresql":
                pg_query = _convert_sql_params(query, params_list)
                if params_list:
                    row = await conn.fetchrow(pg_query, *params_list)
                else:
                    row = await conn.fetchrow(pg_query)
                return dict(row) if row else None
            else:
                conn.row_factory = aiosqlite.Row
                cursor = await conn.execute(query, params_list or ())
                row = await cursor.fetchone()
                return dict(row) if row else None
        finally:
            await self.release(conn)
    
    async def close(self):
        """Close the connection pool"""
        if self.db_type == "postgresql" and self.pool:
            await self.pool.close()


# Global database pool instance
db_pool = DatabasePool()

