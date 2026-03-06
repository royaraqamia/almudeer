"""
Al-Mudeer - Persistent Task Queue

Handles background jobs (AI analysis, etc.) robustly with database persistence.

P1-1 FIX: Added dead letter queue for failed tasks after max retries.
"""

import json
from datetime import datetime
from typing import Optional, Dict, List, Any
from db_helper import get_db, execute_sql, fetch_one, fetch_all, commit_db, DB_TYPE

# Dead letter queue configuration
MAX_RETRY_COUNT = 3
DEAD_LETTER_RETENTION_DAYS = 30


async def enqueue_task(
    task_type: str,
    payload: Dict[str, Any],
    priority: int = 0
) -> int:
    """
    Queue a background task.
    priority: Higher runs first (default 0)
    """
    async with get_db() as db:
        now = datetime.utcnow()
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        payload_json = json.dumps(payload)

        if DB_TYPE == "postgresql":
            sql = """
                INSERT INTO task_queue (task_type, payload, priority, status, created_at, updated_at)
                VALUES ($1, $2, $3, 'pending', $4, $4)
                RETURNING id
            """
            row = await fetch_one(db, sql, [task_type, payload_json, priority, ts_value])
            await commit_db(db)
            return row["id"]
        else:
            # SQLite
            sql = """
                INSERT INTO task_queue (task_type, payload, priority, status, created_at, updated_at)
                VALUES (?, ?, ?, 'pending', ?, ?)
            """
            await execute_sql(db, sql, [task_type, payload_json, priority, ts_value, ts_value])

            # Get ID
            row = await fetch_one(db, "SELECT last_insert_rowid() as id")
            task_id = row["id"]
            await commit_db(db)
            return task_id


async def fetch_next_task(worker_id: str = "worker-1") -> Optional[Dict]:
    """
    Fetch and lock the next pending task.
    Returns task dict or None.
    """
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        # Atomic fetch-and-update (skip locked)
        if DB_TYPE == "postgresql":
            # PostgreSQL FOR UPDATE SKIP LOCKED
            sql = """
                UPDATE task_queue
                SET status = 'processing', worker_id = $1, processed_at = $2, updated_at = $2
                WHERE id = (
                    SELECT id FROM task_queue
                    WHERE status = 'pending'
                    ORDER BY priority DESC, created_at ASC
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED
                )
                RETURNING id, task_type, payload
            """
            row = await fetch_one(db, sql, [worker_id, ts_value])
            if row:
                await commit_db(db)
                return {
                    "id": row["id"],
                    "task_type": row["task_type"],
                    "payload": json.loads(row["payload"])
                }
            return None

        else:
            # SQLite (Simulated atomic lock)
            # 1. Find candidate
            find_sql = """
                SELECT id, task_type, payload FROM task_queue
                WHERE status = 'pending'
                ORDER BY priority DESC, created_at ASC
                LIMIT 1
            """
            row = await fetch_one(db, find_sql)
            if not row:
                return None

            task_id = row["id"]

            # 2. Try to lock
            update_sql = """
                UPDATE task_queue
                SET status = 'processing', worker_id = ?, processed_at = ?, updated_at = ?
                WHERE id = ? AND status = 'pending'
            """
            try:
                await execute_sql(db, update_sql, [worker_id, ts_value, ts_value, task_id])
                await commit_db(db)
                # Success
                return {
                    "id": task_id,
                    "task_type": row["task_type"],
                    "payload": json.loads(row["payload"])
                }
            except:
                 # Race condition failed
                return None


async def complete_task(task_id: int):
    """Mark task as completed."""
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        await execute_sql(
            db,
            "UPDATE task_queue SET status = 'completed', completed_at = ?, updated_at = ? WHERE id = ?",
            [ts_value, ts_value, task_id]
        )
        await commit_db(db)


async def fail_task(task_id: int, error_msg: str, retry_count: Optional[int] = None):
    """
    Mark task as failed or move to dead letter queue after max retries.
    
    P1-1 FIX: Tasks that fail more than MAX_RETRY_COUNT times are moved to dead letter queue.
    """
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        # Get current retry count
        if retry_count is None:
            task_row = await fetch_one(db, "SELECT retry_count FROM task_queue WHERE id = ?", [task_id])
            retry_count = (task_row.get("retry_count") if task_row else 0) + 1
        
        if retry_count >= MAX_RETRY_COUNT:
            # P1-1 FIX: Move to dead letter queue
            await execute_sql(
                db,
                """
                UPDATE task_queue 
                SET status = 'dead_letter', 
                    error_message = ?, 
                    updated_at = ?,
                    retry_count = ?,
                    dead_lettered_at = ?
                WHERE id = ?
                """,
                [str(error_msg), ts_value, retry_count, ts_value, task_id]
            )
            logger = None
            try:
                from logging_config import get_logger
                logger = get_logger(__name__)
            except:
                pass
            if logger:
                logger.warning(f"Task {task_id} moved to dead letter queue after {retry_count} retries: {error_msg}")
        else:
            # Reset to pending for retry
            await execute_sql(
                db,
                """
                UPDATE task_queue 
                SET status = 'pending', 
                    error_message = ?, 
                    updated_at = ?,
                    retry_count = ?
                WHERE id = ?
                """,
                [str(error_msg), ts_value, retry_count, task_id]
            )
        
        await commit_db(db)


async def retry_stuck_tasks(timeout_minutes: int = 15):
    """Reset tasks stuck in 'processing' state for too long."""
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    cutoff = now.timestamp() - (timeout_minutes * 60)

    async with get_db() as db:
        if DB_TYPE == "postgresql":
            sql = """
                UPDATE task_queue
                SET status = 'pending', worker_id = NULL, updated_at = $1
                WHERE status = 'processing'
                AND processed_at < to_timestamp($2)
            """
            await execute_sql(db, sql, [ts_value, cutoff])
        else:
            sql = """
                UPDATE task_queue
                SET status = 'pending', worker_id = NULL, updated_at = ?
                WHERE status = 'processing'
                AND strftime('%s', processed_at) < ?
            """
            await execute_sql(db, sql, [ts_value, cutoff])
        
        await commit_db(db)


async def get_dead_letter_tasks(limit: int = 100) -> List[Dict]:
    """
    P1-1 FIX: Get tasks in dead letter queue for inspection/retry.
    """
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            sql = """
                SELECT id, task_type, payload, error_message, retry_count, dead_lettered_at
                FROM task_queue
                WHERE status = 'dead_letter'
                ORDER BY dead_lettered_at DESC
                LIMIT $1
            """
            rows = await fetch_all(db, sql, [limit])
        else:
            sql = """
                SELECT id, task_type, payload, error_message, retry_count, dead_lettered_at
                FROM task_queue
                WHERE status = 'dead_letter'
                ORDER BY dead_lettered_at DESC
                LIMIT ?
            """
            rows = await fetch_all(db, sql, [limit])
        
        return [
            {
                **row,
                "payload": json.loads(row["payload"]) if isinstance(row["payload"], str) else row["payload"]
            }
            for row in rows
        ]


async def retry_dead_letter_task(task_id: int) -> bool:
    """
    P1-1 FIX: Manually retry a task from dead letter queue.
    Returns True if successful, False if task not found.
    """
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        # Check if task exists and is in dead letter
        task_row = await fetch_one(
            db,
            "SELECT id FROM task_queue WHERE id = ? AND status = 'dead_letter'",
            [task_id]
        )
        
        if not task_row:
            return False
        
        # Reset to pending
        await execute_sql(
            db,
            """
            UPDATE task_queue
            SET status = 'pending',
                error_message = NULL,
                retry_count = 0,
                updated_at = ?
            WHERE id = ?
            """,
            [ts_value, task_id]
        )
        
        await commit_db(db)
        return True


async def purge_dead_letter_tasks(older_than_days: int = 30) -> int:
    """
    P1-1 FIX: Permanently delete old dead letter tasks.
    Returns number of deleted tasks.
    """
    now = datetime.utcnow()
    cutoff = now.timestamp() - (older_than_days * 24 * 60 * 60)

    async with get_db() as db:
        if DB_TYPE == "postgresql":
            sql = """
                DELETE FROM task_queue
                WHERE status = 'dead_letter'
                AND dead_lettered_at < to_timestamp($1)
            """
            cursor = await db.execute(sql, [cutoff])
        else:
            sql = """
                DELETE FROM task_queue
                WHERE status = 'dead_letter'
                AND strftime('%s', dead_lettered_at) < ?
            """
            cursor = await db.execute(sql, [cutoff])
        
        await commit_db(db)
        return cursor.rowcount
