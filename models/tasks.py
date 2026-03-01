from typing import List, Optional
from datetime import datetime, timezone
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db
from models.base import ID_PK, TIMESTAMP_NOW
from utils.timestamps import normalize_timestamp, generate_stable_id

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
        - Assignee: Can view, edit, comment on shared tasks
        - Others: Can only view shared tasks
    """
    # Get task
    task = await fetch_one(
        db,
        "SELECT * FROM tasks WHERE id = ? AND license_key_id = ?",
        [task_id, license_id]
    )
    
    if not task:
        return False
    
    # Owner always has full access
    if task.get("created_by") == user_id:
        return True
    
    # For non-owners, task must be shared
    if task.get("visibility") != "shared":
        return False
    
    # Assignee can edit and comment
    if task.get("assigned_to") == user_id:
        if required_action in ("view", "edit", "comment"):
            return True
        return False
    
    # Others can only view shared tasks
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
    """
    if license_id <= 0:
        return []

    async with get_db() as db:
        query = """
            SELECT * FROM tasks
            WHERE license_key_id = ?
            AND (visibility = 'shared' OR created_by = ?)
        """
        params = [license_id, user_id]

        # Cursor-based pagination (more efficient for large datasets)
        if cursor:
            query += " AND created_at < ?"
            params.append(cursor)

        if since:
            query += " AND (updated_at > ? OR synced_at > ?)"
            params.extend([since, since])

        # Unified Sorting: Active/Completed -> order_index -> newest
        query += " ORDER BY is_completed ASC, order_index ASC, created_at DESC"

        if limit is not None:
            query += f" LIMIT {limit} OFFSET {offset}"

        rows = await fetch_all(db, query, tuple(params))
        return [_parse_task_row(dict(row)) for row in rows]

async def get_task(license_id: int, task_id: str, user_id: str) -> Optional[dict]:
    """Get a specific task (check both license and global). Respects private visibility.

    P4-1: Uses verify_task_access for permission checking.
    """
    async with get_db() as db:
        # First check if task exists
        row = await fetch_one(db, """
            SELECT * FROM tasks
            WHERE (license_key_id = ? OR license_key_id = 0)
            AND id = ?
        """, (license_id, task_id))

        if not row:
            return None
        
        # P4-1: Use consolidated access check
        task_dict = dict(row)
        has_access = await verify_task_access(db, task_id, user_id, license_id, 'view')
        
        if not has_access:
            return None

        return _parse_task_row(task_dict)

def _parse_task_row(row: dict) -> dict:
    """Helper to parse JSON fields and normalize types"""
    import json
    
    # FIX BUG-002: Normalize boolean fields explicitly
    row['is_completed'] = bool(row.get('is_completed', False))
    row['alarm_enabled'] = bool(row.get('alarm_enabled', False))
    
    # FIX BUG-003: Normalize priority field (ensure string format)
    priority_val = row.get('priority', 'medium')
    if isinstance(priority_val, int):
        # Convert integer index to string (mobile sends 0,1,2,3)
        priority_map = ['low', 'medium', 'high', 'urgent']
        row['priority'] = priority_map[priority_val] if 0 <= priority_val < len(priority_map) else 'medium'
    else:
        row['priority'] = priority_val or 'medium'
    
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

def compute_task_role(task: dict, user_id: str) -> str:
    """
    Compute user's role/permission level for a task.
    Returns: 'owner', 'assignee', or 'viewer'
    """
    if task.get('created_by') == user_id:
        return 'owner'
    if task.get('assigned_to') == user_id:
        return 'assignee'
    return 'viewer'

def can_edit_task(task: dict, user_id: str) -> bool:
    """
    Check if user can edit a task based on role and visibility.
    - Owner: always can edit
    - Assignee: can edit shared tasks, update status, add comments
    - Viewer: read-only
    """
    role = compute_task_role(task, user_id)
    if role == 'owner':
        return True
    if role == 'assignee' and task.get('visibility') != 'private':
        return True
    return False

def can_delete_task(task: dict, user_id: str) -> bool:
    """
    Check if user can delete a task.
    Only owners can delete tasks.
    """
    return compute_task_role(task, user_id) == 'owner'

def can_comment_on_task(task: dict, user_id: str) -> bool:
    """
    Check if user can comment on a task.
    - Owner: always can comment
    - Assignee: can comment on shared tasks
    - Viewer: cannot comment
    """
    role = compute_task_role(task, user_id)
    if role == 'owner':
        return True
    if role == 'assignee' and task.get('visibility') != 'private':
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
    """
    async with get_db() as db:
        # Convert list to JSON string if needed
        import json

        sub_tasks_val = task_data.get('sub_tasks')
        if isinstance(sub_tasks_val, list):
            sub_tasks_val = json.dumps(sub_tasks_val)

        # Normalize updated_at to UTC
        updated_at = normalize_timestamp(task_data.get('updated_at'))
        
        # FIX BUG-004: Store client timestamp separately for better conflict resolution
        client_updated_at = updated_at

        await execute_sql(db, """
            INSERT INTO tasks (
                id, license_key_id, title, description, is_completed, due_date,
                priority, color, sub_tasks, alarm_enabled, alarm_time, recurrence,
                category, order_index, created_by, assigned_to, attachments, visibility, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
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
                updated_at = excluded.updated_at
            WHERE tasks.license_key_id = ? AND (
                -- FIX BUG-004: Enhanced LWW with tolerance for clock skew (5 second window)
                tasks.updated_at IS NULL
                OR excluded.updated_at > tasks.updated_at
                OR (
                    -- If timestamps are very close (< 5s), prefer the one with more recent client timestamp
                    ABS(EXTRACT(EPOCH FROM (excluded.updated_at - tasks.updated_at))) < 5
                    AND excluded.updated_at >= tasks.updated_at
                )
            )
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
            task_data.get('created_by'),
            task_data.get('assigned_to'),
            json.dumps(task_data.get('attachments', [])),
            task_data.get('visibility', 'shared'),
            updated_at,
            license_id  # For the WHERE clause in ON CONFLICT
        ))
        await commit_db(db)
        return await get_task(license_id, task_data['id'])

async def update_task(license_id: int, task_id: str, task_data: dict) -> Optional[dict]:
    """Update a task with LWW conflict resolution"""
    fields = []
    values = []

    import json

    for key, val in task_data.items():
        if val is not None and key not in ['id', 'license_key_id', 'updated_at']:
            if key == 'sub_tasks' and isinstance(val, list):
                val = json.dumps(val)
            if key == 'attachments' and isinstance(val, list):
                val = json.dumps(val)

            fields.append(f"{key} = ?")
            values.append(val)

    if not fields:
        return await get_task(license_id, task_id, None)

    # Normalize updated_at to UTC
    updated_at = normalize_timestamp(task_data.get('updated_at'))
    fields.append("updated_at = ?")
    values.append(updated_at)

    values.append(license_id)
    values.append(task_id)
    values.append(updated_at) # For the LWW check in WHERE

    query = f"UPDATE tasks SET {', '.join(fields)} WHERE license_key_id = ? AND id = ? AND (updated_at IS NULL OR ? >= updated_at)"

    async with get_db() as db:
        await execute_sql(db, query, tuple(values))
        await commit_db(db)
        return await get_task(license_id, task_id, None)

async def delete_task(license_id: int, task_id: str) -> bool:
    """Delete a task"""
    async with get_db() as db:
        await execute_sql(db, """
            DELETE FROM tasks 
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
            json.dumps(comment_data.get("attachments", [])),
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
