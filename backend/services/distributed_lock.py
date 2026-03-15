import os
import asyncio
import time
from datetime import datetime, timezone
from logging_config import get_logger
from db_helper import get_db, execute_sql, fetch_one, DB_TYPE

logger = get_logger(__name__)

class DistributedLock:
    """
    Distributed lock mechanism using a dedicated Database table.
    Works for both SQLite and PostgreSQL.
    Uses a heartbeat (keep-alive) to ensure the lock is released if the process crashes.
    """

    def __init__(self, lock_id: int, lock_name: str = "telegram_listener", on_reacquire_callback=None):
        self.lock_id = lock_id
        self.lock_name = lock_name
        self.locked = False
        self._keepalive_task = None
        self._lock_timeout = 30 # Seconds until lock expires without heartbeat
        self._on_reacquire_callback = on_reacquire_callback  # Called when lock is re-acquired after failure
        
    async def acquire(self) -> bool:
        """Try to acquire the distributed lock"""
        try:
            async with get_db() as db:
                await self._ensure_table_exists(db)
                
                now = int(time.time())
                
                # 1. Clean up expired locks first
                await execute_sql(db, "DELETE FROM system_locks WHERE lock_name = ? AND expires_at < ?", [self.lock_name, now])
                if DB_TYPE != "postgresql":
                    from db_helper import commit_db
                    await commit_db(db)
                
                # 2. Try to insert the lock
                try:
                    await execute_sql(
                        db, 
                        "INSERT INTO system_locks (lock_name, expires_at, holder_pid) VALUES (?, ?, ?)", 
                        [self.lock_name, now + self._lock_timeout, os.getpid()]
                    )
                    if DB_TYPE != "postgresql":
                        from db_helper import commit_db
                        await commit_db(db)
                        
                    self.locked = True
                    self._start_keepalive()
                    logger.info(f"Acquired distributed lock '{self.lock_name}' (PID {os.getpid()})")
                    return True
                except Exception:
                    # Could not insert (lock already held by another active process)
                    return False
                        
        except Exception as e:
            logger.error(f"Error acquiring distributed lock '{self.lock_name}': {e}")
            return False

    async def release(self):
        """Release the lock"""
        if not self.locked:
            return

        # Stop heartbeat first
        if self._keepalive_task:
            self._keepalive_task.cancel()
            try:
                await self._keepalive_task
            except asyncio.CancelledError:
                pass
            self._keepalive_task = None

        try:
            async with get_db() as db:
                await execute_sql(
                    db, 
                    "DELETE FROM system_locks WHERE lock_name = ? AND holder_pid = ?", 
                    [self.lock_name, os.getpid()]
                )
                if DB_TYPE != "postgresql":
                    from db_helper import commit_db
                    await commit_db(db)
            
            logger.info(f"Released distributed lock '{self.lock_name}'")
            self.locked = False

        except Exception as e:
            logger.error(f"Error releasing distributed lock '{self.lock_name}': {e}")

    async def _ensure_table_exists(self, db):
        """Ensure the system_locks table exists"""
        sql = """
            CREATE TABLE IF NOT EXISTS system_locks (
                lock_name TEXT PRIMARY KEY,
                expires_at INTEGER,
                holder_pid INTEGER,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """
        # Note: commit_db is handled by execute_sql or context manager in some db_helper versions, 
        # but here we follow the safe pattern.
        await execute_sql(db, sql)
        if DB_TYPE != "postgresql":
            from db_helper import commit_db
            await commit_db(db)

    def _start_keepalive(self):
        """Start background task to refresh the lock expiry"""
        if self._keepalive_task:
            return

        async def keepalive():
            logger.debug(f"Starting keep-alive for lock '{self.lock_name}'")
            consecutive_failures = 0
            max_consecutive_failures = 5
            reattempt_delay = 30  # Seconds to wait before trying to re-acquire lock

            while True:  # Outer loop for potential re-acquisition
                while self.locked:
                    try:
                        # Sleep for a fraction of the timeout (more frequent than before)
                        # Use 1/4 of timeout instead of 1/3 for extra safety margin
                        await asyncio.sleep(self._lock_timeout // 4)

                        # P0-5 FIX: Enhanced retry logic for transient database connection errors
                        # Critical for preventing lock loss due to temporary connection issues
                        max_retries = 3
                        base_delay = 1.0  # seconds

                        for attempt in range(max_retries):
                            try:
                                async with get_db() as db:
                                    now = int(time.time())
                                    await execute_sql(
                                        db,
                                        "UPDATE system_locks SET expires_at = ? WHERE lock_name = ? AND holder_pid = ?",
                                        [now + self._lock_timeout, self.lock_name, os.getpid()]
                                    )
                                    if DB_TYPE != "postgresql":
                                        from db_helper import commit_db
                                        await commit_db(db)

                                    logger.debug(f"Refreshed lock '{self.lock_name}'")
                                consecutive_failures = 0  # Reset on success
                                break  # Success - exit retry loop

                            except Exception as e:
                                if attempt < max_retries - 1:
                                    import random
                                    delay = base_delay * (2 ** attempt) + random.uniform(0, 0.5)
                                    logger.warning(f"Lock keepalive failed (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {delay:.2f}s...")
                                    await asyncio.sleep(delay)
                                else:
                                    logger.error(f"Lock keepalive failed after {max_retries} attempts: {e}")
                                    # Re-raise to let the outer handler deal with it
                                    raise

                    except asyncio.CancelledError:
                        return
                    except Exception as e:
                        consecutive_failures += 1
                        logger.error(f"Error refreshing distributed lock '{self.lock_name}' (failure {consecutive_failures}/{max_consecutive_failures}): {e}")

                        # If too many consecutive failures, the lock is likely lost
                        # Release local state to prevent stale lock assumption
                        if consecutive_failures >= max_consecutive_failures:
                            logger.critical(f"Lock keepalive failed {consecutive_failures} times consecutively. Releasing local lock state for '{self.lock_name}'.")
                            self.locked = False

                            # Stop the keepalive task
                            if self._keepalive_task:
                                self._keepalive_task.cancel()
                                try:
                                    await self._keepalive_task
                                except asyncio.CancelledError:
                                    pass
                                self._keepalive_task = None
                            break

                        await asyncio.sleep(5)

                # Lock was lost due to keepalive failures - attempt re-acquisition
                if consecutive_failures >= max_consecutive_failures:
                    logger.info(f"Waiting {reattempt_delay}s before attempting to re-acquire lock '{self.lock_name}'...")
                    await asyncio.sleep(reattempt_delay)

                    logger.info(f"Attempting to re-acquire distributed lock '{self.lock_name}'...")
                    try:
                        # Clean up any stale lock entry for this PID
                        async with get_db() as db:
                            await execute_sql(
                                db,
                                "DELETE FROM system_locks WHERE lock_name = ? AND holder_pid = ?",
                                [self.lock_name, os.getpid()]
                            )
                            if DB_TYPE != "postgresql":
                                from db_helper import commit_db
                                await commit_db(db)

                        # Try to re-acquire
                        acquired = await self.acquire()
                        if acquired:
                            logger.info(f"Successfully re-acquired distributed lock '{self.lock_name}' after connection recovery.")
                            consecutive_failures = 0
                            # Call callback if provided (e.g., to restart monitor task)
                            if self._on_reacquire_callback:
                                try:
                                    if asyncio.iscoroutinefunction(self._on_reacquire_callback):
                                        await self._on_reacquire_callback()
                                    else:
                                        self._on_reacquire_callback()
                                except Exception as e:
                                    logger.error(f"Error in lock re-acquire callback: {e}")
                            # Continue the outer loop to keep monitoring
                        else:
                            logger.warning(f"Could not re-acquire lock '{self.lock_name}' - it is held by another process. Service will remain in standby mode.")
                            # Exit the keepalive task - service is no longer the leader
                            return

                    except Exception as e:
                        logger.error(f"Error during lock re-acquisition: {e}")
                        # Continue waiting and retrying
                        continue

        self._keepalive_task = asyncio.create_task(keepalive())
