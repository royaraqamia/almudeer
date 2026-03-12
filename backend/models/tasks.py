import json
from typing import List, Optional
from datetime import datetime, timezone
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE
from models.base import ID_PK, TIMESTAMP_NOW
from utils.timestamps import normalize_timestamp, generate_stable_id
from utils.json_utils import normalize_bool, normalize_priority

async def verify_task_access(
    db,
    task_id: str,
    user_id: str,
    license_id: int,
    required_action: str = 'view'
) -> bool:
    """
    Verify if a user has access to a task based on visibility and role.

    P4-1: Consolidated task visibility and permission check.
    P4-2: Updated to use task_shares table instead of assigned_to field.

    Args:
        db: Database connection
        task_id: Task ID
        user_id: User ID requesting access
        license_id: License key ID
        required_action: Action required ('view', 'edit', 'delete', 'comment')

    Returns:
        bool: True if user has access, False otherwise

    Access rules:
        - Owner (created_by): Full access to all actions
        - Shared users: Permission-based access (read/view, edit/edit+view, admin/all)
        - Others: Can only view shared tasks (visibility = 'shared')
    """
    # Get task (check both license-specific and global tasks, filter out soft-deleted)
    task = await fetch_one(
        db,
        "SELECT * FROM tasks WHERE id = ? AND (license_key_id = ? OR license_key_id = 0) AND is_deleted = 0",
        [task_id, license_id]
    )

    if not task:
        return False

    # Owner always has full access
    if task.get("created_by") == user_id:
        return True

    # Check task_shares for permission-based access
    # FIX: Add expires_at check to prevent expired shares from granting access
    now = datetime.now(timezone.utc)
    share = await fetch_one(
        db,
        """
        SELECT permission FROM task_shares
        WHERE task_id = ? AND shared_with_user_id = ? AND license_key_id = ?
        AND deleted_at IS NULL
        AND (expires_at IS NULL OR expires_at > ?)
        """,
        [task_id, user_id, license_id, now]
    )

    if share:
        permission = share.get('permission', 'read')
        # Permission-based access
        if permission == 'admin':
            return True  # Admin can do everything
        elif permission == 'edit':
            return required_action in ('view', 'edit', 'comment')
        elif permission == 'read':
            return required_action == 'view'

    # Fallback to old visibility-based access for backward compatibility
    if task.get("visibility") == "shared":
        if required_action == "view":
            return True

    return False

async def init_task_comments_table():
    """Initialize task_comments table"""
    async with get_db() as db:
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS task_comments (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                license_key_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                user_name TEXT,
                content TEXT NOT NULL,
                attachments TEXT, -- JSON string
                created_at {TIMESTAMP_NOW},
                FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        try:
            await execute_sql(db, "ALTER TABLE task_comments ADD COLUMN attachments TEXT")
            print("Migrated task_comments: added attachments")
        except Exception:
            pass

async def init_tasks_table():
    """Initialize tasks table"""
    async with get_db() as db:
        await execute_sql(db, f"""
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                license_key_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                description TEXT,
                is_completed BOOLEAN DEFAULT FALSE,
                due_date TIMESTAMP,
                priority TEXT DEFAULT 'medium',
                color BIGINT,
                sub_tasks TEXT,  -- JSON string
                alarm_enabled BOOLEAN DEFAULT FALSE,
                alarm_time TIMESTAMP,
                recurrence TEXT, -- recurrence pattern (daily, weekly, etc.)
                category TEXT,
                order_index REAL DEFAULT 0.0,
                created_by TEXT,
                assigned_to TEXT,
                attachments TEXT, -- JSON string
                visibility TEXT DEFAULT 'shared',
                created_at {TIMESTAMP_NOW},
                updated_at TIMESTAMP,
                synced_at TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        await init_task_comments_table()
        
        # Migrations for existing tables
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN alarm_enabled BOOLEAN DEFAULT FALSE")
            print("Migrated tasks: added alarm_enabled")
        except Exception:
            pass
            
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN alarm_time TIMESTAMP")
            print("Migrated tasks: added alarm_time")
        except Exception:
            pass
            
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN color INTEGER")
            print("Migrated tasks: added color")
        except Exception:
            pass
            
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN sub_tasks TEXT")
            print("Migrated tasks: added sub_tasks")
        except Exception:
            pass
 
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN recurrence TEXT")
            print("Migrated tasks: added recurrence")
        except Exception:
            pass
 
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN category TEXT")
            print("Migrated tasks: added category")
        except Exception:
            pass
 
        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN visibility TEXT DEFAULT 'shared'")
            print("Migrated tasks: added visibility")
        except Exception:
            pass

        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN created_by TEXT")
            print("Migrated tasks: added created_by")
        except Exception:
            pass

        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN assigned_to TEXT")
            print("Migrated tasks: added assigned_to")
        except Exception:
            pass

        try:
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN attachments TEXT")
            print("Migrated tasks: added attachments")
        except Exception:
            pass

        # Indexes for performance
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_completed
            ON tasks(license_key_id, is_completed)
        """)

        # FIX: Additional composite indexes for common query patterns
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_assigned_completed
            ON tasks(license_key_id, assigned_to, is_completed)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_visibility_created
            ON tasks(license_key_id, visibility, created_by)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_due_date
            ON tasks(license_key_id, due_date)
        """)

        # FIX DB-001: Add missing indexes for analytics and search queries
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_visibility_completed
            ON tasks(license_key_id, visibility, is_completed)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_category
            ON tasks(license_key_id, category)
            WHERE category IS NOT NULL
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_license_priority
            ON tasks(license_key_id, priority)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_tasks_due_date_active
            ON tasks(due_date)
            WHERE is_completed = FALSE AND due_date IS NOT NULL
        """)

        # Index for task comments lookup
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_comments_task_created
            ON task_comments(task_id, created_at)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_task_comments_license_task
            ON task_comments(license_key_id, task_id)
        """)

        await commit_db(db)
        print("Tasks table initialized with optimized indexes")

async def get_tasks(
    license_id: int,
    user_id: str,
    since: Optional[datetime] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = 0,
    cursor: Optional[str] = None  # Cursor for pagination (task ID or timestamp)
) -> List[dict]:
    """Get tasks for a license. Private tasks only visible to creator.

    Supports both offset-based and cursor-based pagination.
    Cursor-based is preferred for large datasets.
    
    P4-2: Also includes tasks shared with the user via task_shares table.
    """
    if license_id <= 0:
        return []

    async with get_db() as db:
        # P4-2: Include tasks shared with user via task_shares
        # Use UNION instead of DISTINCT to avoid ORDER BY issues
        # FIX: Only return share_permission for tasks shared WITH the user (not owned by user)
        # FIX: Filter out soft-deleted tasks (is_deleted = 0)
        # FIX: Add expires_at check to prevent expired shares from granting access
        now = datetime.now(timezone.utc)
        base_query = """
            SELECT t.*,
                   CASE WHEN t.created_by = ? THEN NULL ELSE ts.permission END as share_permission
            FROM tasks t
            LEFT JOIN task_shares ts ON t.id = ts.task_id
                AND ts.shared_with_user_id = ?
                AND ts.license_key_id = ?
                AND ts.deleted_at IS NULL
                AND (ts.expires_at IS NULL OR ts.expires_at > ?)
            WHERE t.license_key_id = ?
            AND t.is_deleted = 0
            AND (
                t.visibility = 'shared'
                OR t.created_by = ?
                OR ts.id IS NOT NULL
            )
        """
        params = [user_id, user_id, license_id, now, license_id, user_id]

        # FIX BUG-012: Use consistent timestamp for cursor and since filters
        # Cursor uses updated_at for consistency with since filter
        # This prevents skipping or duplicating tasks when both are used together
        if cursor:
            # FIX: Use updated_at instead of created_at for cursor
            # This ensures consistency with the 'since' filter
            base_query += " AND t.updated_at < ?"
            params.append(cursor)

        if since:
            # Incremental sync: fetch tasks updated after this timestamp
            base_query += " AND (t.updated_at > ? OR t.synced_at > ?)"
            params.extend([since, since])

        # Unified Sorting: Active/Completed -> order_index -> newest
        # FIX BUG-012: Sort by updated_at DESC for cursor-based pagination
        # This ensures cursor position matches the filter timestamp
        base_query += " ORDER BY t.is_completed ASC, t.order_index ASC, t.updated_at DESC"

        if limit is not None:
            base_query += f" LIMIT {limit} OFFSET {offset}"

        rows = await fetch_all(db, base_query, tuple(params))
        return [_parse_task_row(dict(row)) for row in rows]

async def _get_task_by_id_raw(db, license_id: int, task_id: str) -> Optional[dict]:
    """Internal helper to get task by ID without permission check (for create/update)."""
    row = await fetch_one(db, """
        SELECT * FROM tasks
        WHERE (license_key_id = ? OR license_key_id = 0)
        AND id = ?
        AND is_deleted = 0
    """, (license_id, task_id))
    return _parse_task_row(dict(row)) if row else None


async def get_task(license_id: int, task_id: str, user_id: str) -> Optional[dict]:
    """Get a specific task (check both license and global). Respects private visibility.

    P4-1: Uses verify_task_access for permission checking.
    P4-2: Also fetches share permission for the user.
    """
    async with get_db() as db:
        # First check if task exists (filter out soft-deleted tasks)
        row = await fetch_one(db, """
            SELECT * FROM tasks
            WHERE (license_key_id = ? OR license_key_id = 0)
            AND id = ?
            AND is_deleted = 0
        """, (license_id, task_id))

        if not row:
            return None

        # P4-1: Use consolidated access check
        task_dict = dict(row)
        has_access = await verify_task_access(db, task_id, user_id, license_id, 'view')

        if not has_access:
            return None

        # P4-2: Fetch user's share permission if they're not the owner
        # FIX: Add expires_at check to prevent expired shares from granting access
        if task_dict.get('created_by') != user_id:
            now = datetime.now(timezone.utc)
            share = await fetch_one(
                db,
                """
                SELECT permission FROM task_shares
                WHERE task_id = ? AND shared_with_user_id = ? AND license_key_id = ?
                AND deleted_at IS NULL
                AND (expires_at IS NULL OR expires_at > ?)
                """,
                [task_id, user_id, license_id, now]
            )
            if share:
                task_dict['share_permission'] = share.get('permission')

        return _parse_task_row(task_dict)

def _parse_task_row(row: dict) -> dict:
    """Helper to parse JSON fields and normalize types"""
    import json

    # FIX BUG-002: Normalize boolean fields explicitly using unified utility
    # Handle various boolean representations: int (0/1), bool, string, None
    row['is_completed'] = normalize_bool(row.get('is_completed'), False)
    row['alarm_enabled'] = normalize_bool(row.get('alarm_enabled'), False)

    # FIX BUG-003: Normalize priority field (ensure string format) using unified utility
    row['priority'] = normalize_priority(row.get('priority'), 'medium')

    # Parse JSON fields
    if row.get('sub_tasks') and isinstance(row['sub_tasks'], str):
        try:
            row['sub_tasks'] = json.loads(row['sub_tasks'])
        except:
            row['sub_tasks'] = []
    elif not row.get('sub_tasks'):
        row['sub_tasks'] = []

    if row.get('attachments') and isinstance(row['attachments'], str):
        try:
            row['attachments'] = json.loads(row['attachments'])
        except:
            row['attachments'] = []
    elif not row.get('attachments'):
        row['attachments'] = []

    return row

def compute_task_role(task: dict, user_id: str, share_permission: Optional[str] = None) -> str:
    """
    Compute user's role/permission level for a task.
    Returns: 'owner', 'admin', 'editor', 'viewer'

    P4-2: Updated to use share permission instead of assigned_to.
    FIX BUG-011: Properly handle 'read' permission to return 'viewer' role.
    """
    if task.get('created_by') == user_id:
        return 'owner'
    
    if share_permission:
        if share_permission == 'admin':
            return 'admin'
        elif share_permission == 'edit':
            return 'editor'
        elif share_permission == 'read':
            return 'viewer'  # FIX BUG-011: Explicitly return 'viewer' for read permission
    
    # Fallback to old assigned_to for backward compatibility
    if task.get('assigned_to') == user_id and task.get('visibility') != 'private':
        return 'editor'
    
    return 'viewer'

def can_edit_task(task: dict, user_id: str, share_permission: Optional[str] = None) -> bool:
    """
    Check if user can edit a task based on role and visibility.
    - Owner: always can edit
    - Admin/Editor (via share): can edit shared tasks
    - Viewer: read-only
    
    P4-2: Updated to use share permission.
    """
    role = compute_task_role(task, user_id, share_permission)
    if role == 'owner':
        return True
    if role in ('admin', 'editor'):
        return True
    return False

def can_delete_task(task: dict, user_id: str) -> bool:
    """
    Check if user can delete a task.
    Only owners can delete tasks.
    """
    return compute_task_role(task, user_id) == 'owner'

def can_comment_on_task(task: dict, user_id: str, share_permission: Optional[str] = None) -> bool:
    """
    Check if user can comment on a task.
    - Owner: always can comment
    - Admin/Editor (via share): can comment on shared tasks
    - Viewer: cannot comment
    
    P4-2: Updated to use share permission.
    """
    role = compute_task_role(task, user_id, share_permission)
    if role == 'owner':
        return True
    if role in ('admin', 'editor'):
        return True
    return False

def _parse_comment_row(row: dict) -> dict:
    """Helper to parse JSON fields for comments"""
    import json
    if row.get('attachments') and isinstance(row['attachments'], str):
        try:
            row['attachments'] = json.loads(row['attachments'])
        except:
            row['attachments'] = []
    elif not row.get('attachments'):
        row['attachments'] = []
    return row

async def create_task(license_id: int, task_data: dict) -> dict:
    """Create or update a task atomically (Upsert) with LWW

    FIX BUG-004: Enhanced LWW with client timestamp + server timestamp for better conflict resolution.
    FIX: Use database-agnostic syntax for clock skew tolerance (works on both SQLite and PostgreSQL).
    FIX: Configurable clock skew tolerance via environment variable (default: 5 seconds).
    """
    import os
    
    # FIX: Configurable clock skew tolerance (default 5 seconds, max 60 seconds)
    # Environment variable: TASK_LWW_CLOCK_SKEW_SECONDS
    try:
        clock_skew_seconds = int(os.getenv('TASK_LWW_CLOCK_SKEW_SECONDS', '5'))
        clock_skew_seconds = max(1, min(clock_skew_seconds, 60))  # Clamp between 1-60 seconds
    except (ValueError, TypeError):
        clock_skew_seconds = 5  # Fallback to default
    
    async with get_db() as db:
        try:
            # Convert list to JSON string if needed
            import json

            sub_tasks_val = task_data.get('sub_tasks')
            if isinstance(sub_tasks_val, list):
                sub_tasks_val = json.dumps(sub_tasks_val)

            # Normalize updated_at to UTC
            updated_at = normalize_timestamp(task_data.get('updated_at'))

            # FIX BUG-004: Store client timestamp separately for better conflict resolution
            client_updated_at = updated_at

            # SECURITY FIX: Ensure created_by is never NULL.
            # Primary source: JWT user_id (set in routes/tasks.py before calling this function)
            # Fallback: license_id (for legacy clients or edge cases)
            # Note: In multi-user licenses, the route layer should always provide the actual user_id
            created_by = task_data.get('created_by')
            if not created_by:
                created_by = str(license_id)
                logger.warning(f"Task {task_data.get('id')} missing created_by, defaulting to license_id {license_id}")

            # FIX: Use database-agnostic clock skew tolerance with configurable value
            # PostgreSQL: EXTRACT(EPOCH FROM ...) returns seconds
            # SQLite: strftime('%s', ...) returns seconds as string
            if DB_TYPE == "sqlite":
                clock_skew_condition = f"""
                    ABS(strftime('%s', excluded.updated_at) - strftime('%s', tasks.updated_at)) < {clock_skew_seconds}
                    AND excluded.updated_at >= tasks.updated_at
                """
            else:
                # PostgreSQL
                clock_skew_condition = f"""
                    ABS(EXTRACT(EPOCH FROM (excluded.updated_at - tasks.updated_at))) < {clock_skew_seconds}
                    AND excluded.updated_at >= tasks.updated_at
                """

            await execute_sql(db, f"""
                INSERT INTO tasks (
                    id, license_key_id, title, description, is_completed, due_date,
                    priority, color, sub_tasks, alarm_enabled, alarm_time, recurrence,
                    category, order_index, created_by, assigned_to, attachments, visibility, created_at, updated_at, synced_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    description = excluded.description,
                    is_completed = excluded.is_completed,
                    due_date = excluded.due_date,
                    priority = excluded.priority,
                    color = excluded.color,
                    sub_tasks = excluded.sub_tasks,
                    alarm_enabled = excluded.alarm_enabled,
                    alarm_time = excluded.alarm_time,
                    recurrence = excluded.recurrence,
                    category = excluded.category,
                    order_index = excluded.order_index,
                    assigned_to = excluded.assigned_to,
                    attachments = excluded.attachments,
                    visibility = excluded.visibility,
                    is_deleted = 0,
                    updated_at = excluded.updated_at,
                    synced_at = CURRENT_TIMESTAMP
                WHERE tasks.license_key_id = ? AND (
                    tasks.updated_at IS NULL
                    OR excluded.updated_at > tasks.updated_at
                    OR ({clock_skew_condition})
            """, (
                task_data['id'],
                license_id,
                task_data['title'],
                task_data.get('description'),
                task_data.get('is_completed', False),
                task_data.get('due_date'),
                task_data.get('priority', 'medium'),
                task_data.get('color'),
                sub_tasks_val,
                task_data.get('alarm_enabled', False),
                task_data.get('alarm_time'),
                task_data.get('recurrence'),
                task_data.get('category'),
                task_data.get('order_index', 0.0),
                created_by,
                task_data.get('assigned_to'),
                # FIX: Convert Pydantic models to dicts before JSON serialization
                json.dumps([att.model_dump() if hasattr(att, 'model_dump') else att for att in (task_data.get('attachments', []) or [])]),
                task_data.get('visibility', 'shared'),
                updated_at,
                license_id  # For the WHERE clause in ON CONFLICT
            ))
            await commit_db(db)
            # Use internal helper to get task without permission check (we just created it)
            async with get_db() as db:
                return await _get_task_by_id_raw(db, license_id, task_data['id'])
        except Exception as e:
            # Transaction will be automatically rolled back by the context manager
            import logging
            logging.error(f"Failed to create/update task {task_data.get('id')}: {e}")
            raise

async def update_task(license_id: int, task_id: str, task_data: dict) -> Optional[dict]:
    """Update a task with LWW conflict resolution"""
    fields = []
    values = []

    import json

    for key, val in task_data.items():
        if val is not None and key not in ['id', 'license_key_id', 'updated_at']:
            if key == 'sub_tasks' and isinstance(val, list):
                val = json.dumps(val)
            # FIX: Convert Pydantic models to dicts before JSON serialization
            if key == 'attachments' and isinstance(val, list):
                val = json.dumps([att.model_dump() if hasattr(att, 'model_dump') else att for att in val])

            fields.append(f"{key} = ?")
            values.append(val)

    if not fields:
        # No fields to update, just return current task
        async with get_db() as db:
            return await _get_task_by_id_raw(db, license_id, task_id)

    # Normalize updated_at to UTC
    updated_at = normalize_timestamp(task_data.get('updated_at'))
    fields.append("updated_at = ?")
    values.append(updated_at)
    
    # Set synced_at to mark task as synced
    fields.append("synced_at = CURRENT_TIMESTAMP")

    values.append(license_id)
    values.append(task_id)
    values.append(updated_at) # For the LWW check in WHERE

    query = f"UPDATE tasks SET {', '.join(fields)} WHERE license_key_id = ? AND id = ? AND (updated_at IS NULL OR ? >= updated_at)"

    async with get_db() as db:
        await execute_sql(db, query, tuple(values))
        await commit_db(db)
        # Use internal helper to get task without permission check (we just updated it)
        async with get_db() as db:
            return await _get_task_by_id_raw(db, license_id, task_id)

async def delete_task(license_id: int, task_id: str) -> bool:
    """Delete a task (soft delete - sets is_deleted flag)
    
    FIX: Use soft delete to maintain data integrity and allow for undo operations.
    """
    async with get_db() as db:
        await execute_sql(db, """
            UPDATE tasks 
            SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP
            WHERE license_key_id = ? AND id = ?
        """, (license_id, task_id))
        await commit_db(db)
        return True

async def add_task_comment(license_id: int, task_id: str, comment_data: dict) -> dict:
    """Add a comment to a task"""
    import uuid
    comment_id = str(uuid.uuid4())
    now = datetime.utcnow()
    
    async with get_db() as db:
        await execute_sql(db, """
            INSERT INTO task_comments (id, task_id, license_key_id, user_id, user_name, content, attachments, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            comment_id,
            task_id,
            license_id,
            comment_data["user_id"],
            comment_data.get("user_name"),
            comment_data["content"],
            # FIX: Convert Pydantic models to dicts before JSON serialization
            json.dumps([att.model_dump() if hasattr(att, 'model_dump') else att for att in (comment_data.get("attachments", []) or [])]),
            now
        ))
        await commit_db(db)
        
    return {
        "id": comment_id,
        "task_id": task_id,
        "user_id": comment_data["user_id"],
        "user_name": comment_data.get("user_name"),
        "content": comment_data["content"],
        "attachments": comment_data.get("attachments", []),
        "created_at": now
    }

async def get_task_comments(license_id: int, task_id: str) -> List[dict]:
    """Get all comments for a task"""
    async with get_db() as db:
        query = "SELECT * FROM task_comments WHERE license_key_id = ? AND task_id = ? ORDER BY created_at ASC"
        rows = await fetch_all(db, query, (license_id, task_id))
        return [_parse_comment_row(dict(row)) for row in rows]
