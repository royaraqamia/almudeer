"""
Al-Mudeer - Task Performance Index Migration
Adds composite indexes for improved task query performance.

Run this migration once to add the new indexes to existing databases.
"""

import asyncio
from db_helper import get_db, execute_sql, commit_db

async def add_task_indexes():
    """Add performance indexes to tasks and task_comments tables."""
    async with get_db() as db:
        print("Adding task performance indexes...")
        
        # Index for assignment queries
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_assigned_completed
            ON tasks(license_key_id, assigned_to, is_completed)
        """)
        print("  ✓ idx_tasks_license_assigned_completed")

        # Index for visibility filtering
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_visibility_created
            ON tasks(license_key_id, visibility, created_by)
        """)
        print("  ✓ idx_tasks_license_visibility_created")

        # Index for due date queries
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_due_date
            ON tasks(license_key_id, due_date)
        """)
        print("  ✓ idx_tasks_license_due_date")

        # Index for comment lookups
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_comments_task_created
            ON task_comments(task_id, created_at)
        """)
        print("  ✓ idx_task_comments_task_created")

        # Index for comment license filtering
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_comments_license_task
            ON task_comments(license_key_id, task_id)
        """)
        print("  ✓ idx_task_comments_license_task")

        await commit_db(db)
        print("\n✅ All task performance indexes added successfully!")

if __name__ == "__main__":
    asyncio.run(add_task_indexes())
