"""
Al-Mudeer - Task Queue Table Migration
Creates the task_queue table for persistent background jobs
"""

from logging_config import get_logger

logger = get_logger(__name__)


async def create_task_queue_table():
    """
    Create the task_queue table.
    """
    from db_helper import get_db, execute_sql, commit_db, DB_TYPE
    
    logger.info("Creating task_queue table...")
    
    async with get_db() as db:
        # Create task_queue table
        if DB_TYPE == "postgresql":
            await execute_sql(db, """
                CREATE TABLE IF NOT EXISTS task_queue (
                    id SERIAL PRIMARY KEY,
                    task_type TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    status TEXT DEFAULT 'pending',
                    priority INTEGER DEFAULT 0,
                    worker_id TEXT,
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW(),
                    processed_at TIMESTAMP,
                    completed_at TIMESTAMP
                )
            """)
        else:
            await execute_sql(db, """
                CREATE TABLE IF NOT EXISTS task_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    task_type TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    status TEXT DEFAULT 'pending',
                    priority INTEGER DEFAULT 0,
                    worker_id TEXT,
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    processed_at TIMESTAMP,
                    completed_at TIMESTAMP
                )
            """)
        
        # Create indexes
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_queue_status_priority
            ON task_queue(status, priority DESC, created_at ASC)
        """)
        
        await commit_db(db)
        logger.info("✅ Task queue table created!")
