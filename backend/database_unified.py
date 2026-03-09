"""
Al-Mudeer - Unified Database Interface
Supports both SQLite (development) and PostgreSQL (production)
Automatically switches based on DB_TYPE environment variable
"""

import os
from typing import Optional, Any
from contextlib import asynccontextmanager

# Database configuration
from db_pool import DB_TYPE, adapt_sql_for_db, db_pool
from db_helper import get_db as get_db_connection, execute_sql as execute_query

# Compat for execute_update
async def execute_update(query: str, params: tuple = None) -> int:
    """Execute update/insert and return affected rows/lastrowid"""
    res = await execute_query(query, params)
    if DB_TYPE == "postgresql":
        # PG result is usually a string like "UPDATE 1"
        try:
            return int(str(res).split()[-1])
        except:
            return 1
    else:
        # SQLite result is the cursor
        return res.lastrowid or res.rowcount

async def get_db_pool():
    return db_pool

async def close_db_pool():
    await db_pool.close()
