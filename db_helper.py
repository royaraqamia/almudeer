"""
Database Helper - Unified interface for SQLite and PostgreSQL
"""

import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Iterable, List, Any

from db_pool import (
    db_pool, 
    DB_TYPE,
    DATABASE_PATH,
    DATABASE_URL,
    POSTGRES_AVAILABLE,
    adapt_sql_for_db,
    _convert_sql_params,
    _normalize_params
)


@asynccontextmanager
async def get_db():
    """Get database connection context manager using global pool"""
    
    conn = await db_pool.acquire()
    try:
        # SQLite specific: ensure foreign keys are enabled if it's a new connection
        if DB_TYPE == "sqlite":
            await conn.execute("PRAGMA foreign_keys = ON")
        yield conn
    finally:
        await db_pool.release(conn)


async def execute_sql(db, sql: str, params=None):
    """Execute SQL with proper parameter handling"""
    sql = adapt_sql_for_db(sql)
    if DB_TYPE == "postgresql":
        # Convert SQLite-style ? placeholders to $1, $2, ... for asyncpg
        if params:
            params = list(_normalize_params(params))
            sql = _convert_sql_params(sql, params)
            return await db.execute(sql, *params)
        else:
            return await db.execute(sql)
    else:
        if params:
            return await db.execute(sql, params)
        else:
            return await db.execute(sql)


async def fetch_all(db, sql: str, params=None):
    """Fetch all rows"""
    sql = adapt_sql_for_db(sql)
    if DB_TYPE == "postgresql":
        if params:
            params = list(_normalize_params(params))
            sql = _convert_sql_params(sql, params)
            rows = await db.fetch(sql, *params)
        else:
            rows = await db.fetch(sql)
        return [dict(row) for row in rows]
    else:
        if params:
            cursor = await db.execute(sql, params)
        else:
            cursor = await db.execute(sql)
        rows = await cursor.fetchall()
        if cursor.description:
            columns = [desc[0] for desc in cursor.description]
            return [dict(zip(columns, row)) for row in rows]
        return []


async def fetch_one(db, sql: str, params=None):
    """Fetch one row"""
    sql = adapt_sql_for_db(sql)
    if DB_TYPE == "postgresql":
        if params:
            params = list(_normalize_params(params))
            sql = _convert_sql_params(sql, params)
            row = await db.fetchrow(sql, *params)
        else:
            row = await db.fetchrow(sql)
        return dict(row) if row else None
    else:
        if params:
            cursor = await db.execute(sql, params)
        else:
            cursor = await db.execute(sql)
        row = await cursor.fetchone()
        if row and cursor.description:
            columns = [desc[0] for desc in cursor.description]
            return dict(zip(columns, row))
        return None


async def commit_db(db):
    """Commit database transaction"""
    if DB_TYPE != "postgresql":
        await db.commit()


async def rollback_db(db):
    """Rollback database transaction (PostgreSQL only)"""
    if DB_TYPE == "postgresql":
        try:
            await db.execute("ROLLBACK")
        except Exception as e:
            # Log but don't raise - rollback failure is secondary
            from logging_config import get_logger
            get_logger(__name__).warning(f"Rollback failed: {e}")

