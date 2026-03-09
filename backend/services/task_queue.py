"""
Al-Mudeer - Background Task Queue Service
Wrapper around DB-backed task queue for backward compatibility
and easy injection.
"""

from typing import Optional, Dict, Any, List
from models.task_queue import enqueue_task, fetch_next_task, complete_task, fail_task

# Re-export key functions
async def enqueue_ai_task(task_type: str, payload: Dict[str, Any]) -> int:
    """Queue an AI task."""
    return await enqueue_task(task_type, payload)

async def get_ai_task_status(task_id: int) -> Optional[Dict[str, Any]]:
    """
    Get task status.
    Note: For now, we don't have a direct 'get_status' in models.task_queue optimized for polling.
    We'll assume client polls DB or we implement a read helper if needed.
    """
    # TODO: Implement read helper in models if needed
    return None

class TaskQueue:
    """Legacy wrapper if needed"""
    pass

async def get_task_queue():
    return TaskQueue()
