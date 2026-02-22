from typing import List, Optional
from datetime import datetime
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db
from models.base import ID_PK, TIMESTAMP_NOW

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
            await execute_sql(db, "ALTER TABLE tasks ADD COLUMN order_index REAL DEFAULT 0.0")
            print("Migrated tasks: added order_index")
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
        
        await commit_db(db)
        print("Tasks table initialized")

async def get_tasks(
    license_id: int, 
    since: Optional[datetime] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = 0
) -> List[dict]:
    """Get all tasks for a license + global tasks (license_id 0), optionally since a specific time, with pagination"""
    async with get_db() as db:
        # Include license_id and global (0)
        query = "SELECT * FROM tasks WHERE (license_key_id = ? OR license_key_id = 0)"
        params = [license_id]
        
        if since:
            query += " AND (updated_at > ? OR synced_at > ?)"
            params.extend([since, since])
            
        query += " ORDER BY created_at DESC"
        
        if limit is not None:
            query += f" LIMIT {limit} OFFSET {offset}"
        
        rows = await fetch_all(db, query, tuple(params))
        return [_parse_task_row(dict(row)) for row in rows]

async def get_task(license_id: int, task_id: str) -> Optional[dict]:
    """Get a specific task (check both license and global)"""
    async with get_db() as db:
        row = await fetch_one(db, """
            SELECT * FROM tasks 
            WHERE (license_key_id = ? OR license_key_id = 0) AND id = ?
        """, (license_id, task_id))
        return _parse_task_row(dict(row)) if row else None

def _parse_task_row(row: dict) -> dict:
    """Helper to parse JSON fields"""
    import json
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
    """Create or update a task atomically (Upsert)"""
    async with get_db() as db:
        # Convert list to JSON string if needed
        import json
        sub_tasks_val = task_data.get('sub_tasks')
        if isinstance(sub_tasks_val, list):
            sub_tasks_val = json.dumps(sub_tasks_val)
            
        await execute_sql(db, """
            INSERT INTO tasks (
                id, license_key_id, title, description, is_completed, due_date, 
                priority, color, sub_tasks, alarm_enabled, alarm_time, recurrence,
                category, order_index, created_by, assigned_to, attachments, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
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
                updated_at = excluded.updated_at
            WHERE tasks.license_key_id = ? AND (tasks.updated_at IS NULL OR excluded.updated_at > tasks.updated_at)
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
            task_data.get('updated_at', datetime.utcnow().isoformat()), # Insert specific updated_at to respect client LWW
            license_id  # For the WHERE clause in ON CONFLICT
        ))
        await commit_db(db)
        return await get_task(license_id, task_data['id'])

async def update_task(license_id: int, task_id: str, task_data: dict) -> Optional[dict]:
    """Update a task"""
    fields = []
    values = []
    
    # helper to add field if present
    import json
    for key, val in task_data.items():
        if val is not None and key not in ['id', 'license_key_id']:
            # Handle special field types for database
            if key == 'sub_tasks' and isinstance(val, list):
                val = json.dumps(val)
            if key == 'attachments' and isinstance(val, list):
                val = json.dumps(val)
                
            fields.append(f"{key} = ?")
            values.append(val)
            
    if not fields:
        return await get_task(license_id, task_id)
        
    fields.append("updated_at = CURRENT_TIMESTAMP")
    values.append(license_id)
    values.append(task_id)
    
    query = f"UPDATE tasks SET {', '.join(fields)} WHERE license_key_id = ? AND id = ?"
    
    async with get_db() as db:
        await execute_sql(db, query, tuple(values))
        await commit_db(db)
        return await get_task(license_id, task_id)

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
