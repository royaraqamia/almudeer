"""
Al-Mudeer - Task Shares Feature Tests
Comprehensive test coverage for task sharing operations

P4-2: Tests for the task_shares model functions
"""

import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

from models.task_shares import (
    share_task,
    remove_share,
    get_shared_tasks,
    list_task_shares,
    update_share_permission,
    get_user_permission_on_task,
    _invalidate_shared_tasks_cache,
    _invalidate_shared_tasks_cache_batch,
)
from db_helper import get_db, fetch_one, execute_sql


# ============ Share Task Tests ============

@pytest.mark.asyncio
class TestShareTask:
    """Test task sharing functionality"""

    async def test_share_task_success(self):
        """Test successful task sharing with read permission"""
        task_id = "test-share-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup: Create task
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        # Share task
        result = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        assert result is not None
        assert result["task_id"] == task_id
        assert result["shared_with_user_id"] == shared_with_user_id
        assert result["permission"] == "read"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_share_task_edit_permission(self):
        """Test sharing with edit permission"""
        task_id = "test-share-edit-456"
        license_id = 1
        shared_with_user_id = "user789"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        result = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="edit",
            created_by=created_by
        )

        assert result["permission"] == "edit"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_share_task_admin_permission(self):
        """Test sharing with admin permission"""
        task_id = "test-share-admin-789"
        license_id = 1
        shared_with_user_id = "user999"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        result = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="admin",
            created_by=created_by
        )

        assert result["permission"] == "admin"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_share_task_invalid_permission(self):
        """Test that invalid permission raises error"""
        task_id = "test-share-invalid-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        with pytest.raises(ValueError, match="Invalid permission"):
            await share_task(
                task_id=task_id,
                license_id=license_id,
                shared_with_user_id=shared_with_user_id,
                permission="invalid_permission",
                created_by=created_by
            )

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_share_task_not_found(self):
        """Test sharing non-existent task raises error"""
        with pytest.raises(ValueError, match="Task not found"):
            await share_task(
                task_id="non-existent-task",
                license_id=1,
                shared_with_user_id="user456",
                permission="read",
                created_by="user123"
            )

    async def test_share_task_updates_existing(self):
        """Test that sharing again updates existing share"""
        task_id = "test-share-update-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        # First share with read
        result1 = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        # Share again with edit - should update
        result2 = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="edit",
            created_by=created_by
        )

        # Both should return same share ID (updated, not duplicated)
        assert result1["id"] == result2["id"]

        # Verify permission was updated
        async with get_db() as db:
            share = await fetch_one(
                db,
                "SELECT permission FROM task_shares WHERE task_id = ? AND shared_with_user_id = ?",
                (task_id, shared_with_user_id)
            )
            assert share["permission"] == "edit"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))


# ============ Remove Share Tests ============

@pytest.mark.asyncio
class TestRemoveShare:
    """Test share removal functionality"""

    async def test_remove_share_success(self):
        """Test successful share removal (soft delete)"""
        task_id = "test-remove-share-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup: Create task and share
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        share_result = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        share_id = share_result["id"]

        # Remove share
        result = await remove_share(
            share_id=share_id,
            license_id=license_id,
            revoked_by=created_by
        )

        assert result is True

        # Verify soft delete (deleted_at is set)
        async with get_db() as db:
            share = await fetch_one(
                db,
                "SELECT deleted_at FROM task_shares WHERE id = ?",
                (share_id,)
            )
            assert share["deleted_at"] is not None

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_remove_share_not_found(self):
        """Test removing non-existent share"""
        result = await remove_share(
            share_id=99999,
            license_id=1,
            revoked_by="user123"
        )
        assert result is False


# ============ Get Shared Tasks Tests ============

@pytest.mark.asyncio
class TestGetSharedTasks:
    """Test getting shared tasks functionality"""

    async def test_get_shared_tasks_empty(self):
        """Test getting shared tasks when none exist"""
        tasks = await get_shared_tasks(
            license_id=1,
            user_id="user456",
            permission=None
        )
        assert tasks == []

    async def test_get_shared_tasks_with_permission(self):
        """Test getting shared tasks filtered by permission"""
        task_id = "test-get-shared-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="edit",
            created_by=created_by
        )

        # Get shared tasks
        tasks = await get_shared_tasks(
            license_id=license_id,
            user_id=shared_with_user_id,
            permission="edit"
        )

        assert len(tasks) == 1
        assert tasks[0]["id"] == task_id
        assert tasks[0]["share_permission"] == "edit"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))


# ============ List Task Shares Tests ============

@pytest.mark.asyncio
class TestListTaskShares:
    """Test listing task shares functionality"""

    async def test_list_task_shares_empty(self):
        """Test listing shares for task with no shares"""
        task_id = "test-list-shares-123"
        license_id = 1
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        shares = await list_task_shares(
            task_id=task_id,
            license_id=license_id,
            requested_by_user_id=created_by
        )

        assert shares == []

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_list_task_shares_multiple(self):
        """Test listing multiple shares for a task"""
        task_id = "test-list-shares-multi-123"
        license_id = 1
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        # Share with multiple users
        await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id="user456",
            permission="read",
            created_by=created_by
        )
        await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id="user789",
            permission="edit",
            created_by=created_by
        )

        shares = await list_task_shares(
            task_id=task_id,
            license_id=license_id,
            requested_by_user_id=created_by
        )

        assert len(shares) == 2
        permissions = {s["shared_with_user_id"]: s["permission"] for s in shares}
        assert permissions["user456"] == "read"
        assert permissions["user789"] == "edit"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))


# ============ Update Share Permission Tests ============

@pytest.mark.asyncio
class TestUpdateSharePermission:
    """Test updating share permissions"""

    async def test_update_share_permission_success(self):
        """Test successful permission update"""
        task_id = "test-update-perm-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        share_result = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        share_id = share_result["id"]

        # Update permission
        result = await update_share_permission(
            share_id=share_id,
            license_id=license_id,
            permission="admin",
            updated_by=created_by
        )

        assert result is True

        # Verify update
        async with get_db() as db:
            share = await fetch_one(
                db,
                "SELECT permission FROM task_shares WHERE id = ?",
                (share_id,)
            )
            assert share["permission"] == "admin"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_update_share_permission_not_found(self):
        """Test updating non-existent share"""
        result = await update_share_permission(
            share_id=99999,
            license_id=1,
            permission="edit",
            updated_by="user123"
        )
        assert result is False


# ============ Get User Permission Tests ============

@pytest.mark.asyncio
class TestGetUserPermissionOnTask:
    """Test getting user permission for a task"""

    async def test_get_user_permission_no_share(self):
        """Test permission when user has no share"""
        permission = await get_user_permission_on_task(
            task_id="non-existent",
            user_id="user456",
            license_id=1
        )
        assert permission is None

    async def test_get_user_permission_with_share(self):
        """Test permission when user has share"""
        task_id = "test-get-perm-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="edit",
            created_by=created_by
        )

        permission = await get_user_permission_on_task(
            task_id=task_id,
            user_id=shared_with_user_id,
            license_id=license_id
        )

        assert permission == "edit"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))


# ============ Cache Invalidation Tests ============

@pytest.mark.asyncio
class TestCacheInvalidation:
    """Test cache invalidation functionality"""

    async def test_invalidate_shared_tasks_cache(self):
        """Test invalidating shared tasks cache for a user"""
        # This is mostly a smoke test since cache is in-memory
        await _invalidate_shared_tasks_cache(
            license_id=1,
            user_id="user456"
        )
        # Should not raise

    async def test_invalidate_shared_tasks_cache_batch(self):
        """Test batch cache invalidation"""
        await _invalidate_shared_tasks_cache_batch(
            license_id=1,
            user_ids=["user456", "user789", "user999"]
        )
        # Should not raise

    async def test_invalidate_shared_tasks_cache_no_user(self):
        """Test invalidating all caches for a license"""
        await _invalidate_shared_tasks_cache(
            license_id=1,
            user_id=None
        )
        # Should not raise


# ============ Share Expiration Tests ============

@pytest.mark.asyncio
class TestShareExpiration:
    """Test task share expiration functionality - BUG-002 FIX"""

    async def test_share_with_expiration_date(self):
        """Test creating a share with an expiration date"""
        task_id = "test-expire-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"
        expires_at = datetime.now(timezone.utc) + timedelta(days=7)

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        result = await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        # Manually set expires_at since share_task doesn't support it yet
        async with get_db() as db:
            await execute_sql(db, """
                UPDATE task_shares SET expires_at = ? WHERE task_id = ? AND shared_with_user_id = ?
            """, (expires_at, task_id, shared_with_user_id))

        # Verify expiration was set
        async with get_db() as db:
            share = await fetch_one(db, """
                SELECT expires_at FROM task_shares WHERE task_id = ? AND shared_with_user_id = ?
            """, (task_id, shared_with_user_id))
            assert share is not None
            assert share['expires_at'] is not None

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_expired_share_not_returned(self):
        """Test that expired shares are not returned by get_shared_tasks"""
        task_id = "test-expire-456"
        license_id = 1
        shared_with_user_id = "user789"
        created_by = "user123"
        expired_time = datetime.now(timezone.utc) - timedelta(hours=1)

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))
            
            # Create share with expired expires_at
            await execute_sql(db, """
                INSERT INTO task_shares (task_id, license_key_id, shared_with_user_id, permission, created_at, expires_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            """, (task_id, license_id, shared_with_user_id, "read", expired_time))

        # Get shared tasks - should NOT include expired share
        shared_tasks = await get_shared_tasks(
            license_id=license_id,
            user_id=shared_with_user_id
        )

        # Expired share should be filtered out
        task_ids = [t['id'] for t in shared_tasks]
        assert task_id not in task_ids

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_non_expired_share_returned(self):
        """Test that non-expired shares are returned by get_shared_tasks"""
        task_id = "test-expire-789"
        license_id = 1
        shared_with_user_id = "user999"
        created_by = "user123"
        future_time = datetime.now(timezone.utc) + timedelta(days=30)

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))
            
            # Create share with future expires_at
            await execute_sql(db, """
                INSERT INTO task_shares (task_id, license_key_id, shared_with_user_id, permission, created_at, expires_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            """, (task_id, license_id, shared_with_user_id, "read", future_time))

        # Get shared tasks - SHOULD include non-expired share
        shared_tasks = await get_shared_tasks(
            license_id=license_id,
            user_id=shared_with_user_id
        )

        # Non-expired share should be included
        task_ids = [t['id'] for t in shared_tasks]
        assert task_id in task_ids

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_null_expires_at_share_returned(self):
        """Test that shares with null expires_at are always returned"""
        task_id = "test-expire-null-123"
        license_id = 1
        shared_with_user_id = "user_null"
        created_by = "user123"

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))
            
            # Create share with NULL expires_at (never expires)
            await execute_sql(db, """
                INSERT INTO task_shares (task_id, license_key_id, shared_with_user_id, permission, created_at, expires_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, NULL)
            """, (task_id, license_id, shared_with_user_id, "read"))

        # Get shared tasks - SHOULD include share with null expires_at
        shared_tasks = await get_shared_tasks(
            license_id=license_id,
            user_id=shared_with_user_id
        )

        # Share with null expires_at should be included
        task_ids = [t['id'] for t in shared_tasks]
        assert task_id in task_ids

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_verify_task_access_with_expired_share(self):
        """Test that verify_task_access returns False for expired shares"""
        from models.tasks import verify_task_access
        
        task_id = "test-expire-access-123"
        license_id = 1
        shared_with_user_id = "user_access_test"
        created_by = "user123"
        expired_time = datetime.now(timezone.utc) - timedelta(hours=2)

        # Setup
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))
            
            # Create share with expired expires_at
            await execute_sql(db, """
                INSERT INTO task_shares (task_id, license_key_id, shared_with_user_id, permission, created_at, expires_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            """, (task_id, license_id, shared_with_user_id, "edit", expired_time))

        # Verify access - should return False due to expired share
        async with get_db() as db:
            has_access = await verify_task_access(
                db=db,
                task_id=task_id,
                user_id=shared_with_user_id,
                license_id=license_id,
                required_action='view'
            )
            assert has_access is False

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
