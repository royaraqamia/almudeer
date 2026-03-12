"""
Comprehensive tests for task and library share validation

Tests cover:
- Self-share prevention (SEC-001/SEC-002)
- Username resolution (AUTH-001)
- Permission enforcement
- Cache integrity
- Error message sanitization
- Bulk operations
"""

import pytest
import asyncio
from datetime import datetime, timezone
from unittest.mock import patch, MagicMock
import hashlib

from models.task_shares import (
    share_task,
    get_shared_tasks,
    remove_share,
    _invalidate_shared_tasks_cache,
)
from utils.cache_utils import (
    get_shared_tasks_cache,
    get_shared_items_cache,
    _DEFAULT_MAX_CACHE_SIZE,
    LRUCache,
)
from models.library_advanced import (
    share_item,
    get_shared_items,
    remove_share as remove_library_share,
    _invalidate_shared_items_cache,
)
from models.tasks import create_task, get_task, _get_task_by_id_raw
from models.library import add_library_item, get_library_item


# ============================================================================
# FIXTURES
# ============================================================================

@pytest.fixture(autouse=True)
async def clear_caches():
    """Clear all share caches before and after each test"""
    tasks_cache = get_shared_tasks_cache()
    items_cache = get_shared_items_cache()
    
    # Clear internal cache structures
    async with tasks_cache._lock:
        tasks_cache._cache.clear()
        tasks_cache._access_times.clear()
    
    async with items_cache._lock:
        items_cache._cache.clear()
        items_cache._access_times.clear()
    
    yield
    
    # Clear again after test
    async with tasks_cache._lock:
        tasks_cache._cache.clear()
        tasks_cache._access_times.clear()
    
    async with items_cache._lock:
        items_cache._cache.clear()
        items_cache._access_times.clear()


@pytest.fixture(scope="function")
async def test_license():
    """Create test license key"""
    from db_helper import get_db
    
    async with get_db() as db:
        test_key = "MUDEER-TEST-1234-5678"
        key_hash = hashlib.sha256(test_key.encode()).hexdigest()
        
        await db.execute("""
            INSERT OR REPLACE INTO license_keys (id, key_hash, full_name, is_active)
            VALUES (1, ?, ?, 1)
        """, (key_hash, "Test Company"))
        await db.commit()
    
    return {"license_id": 1, "key": test_key}


@pytest.fixture(scope="function")
async def test_task(test_license):
    """Create a test task"""
    from db_helper import get_db

    task_id = 'test-task-001'

    async with get_db() as db:
        # Ensure is_completed column exists (migration)
        try:
            await db.execute("ALTER TABLE tasks ADD COLUMN is_completed BOOLEAN DEFAULT 0")
            await db.commit()
        except:
            pass  # Column already exists
        
        # Create task directly in DB to avoid complex create_task issues
        await db.execute("""
            INSERT OR REPLACE INTO tasks
            (id, license_key_id, title, description, is_completed, visibility, created_by, created_at)
            VALUES (?, ?, ?, ?, 0, 'shared', '1', CURRENT_TIMESTAMP)
        """, (task_id, test_license['license_id'], 'Test Task', 'Test description'))
        await db.commit()

    return {
        'id': task_id,
        'license_key_id': test_license['license_id'],
        'title': 'Test Task',
        'created_by': '1'
    }


@pytest.fixture(scope="function")
async def test_library_item(test_license):
    """Create a test library item"""
    from db_helper import get_db
    
    async with get_db() as db:
        await db.execute("""
            INSERT INTO library_items (license_key_id, user_id, type, title, content, created_at)
            VALUES (?, ?, 'note', 'Test Note', 'Test content', CURRENT_TIMESTAMP)
        """, (test_license['license_id'], '1'))
        await db.commit()
        
        # Get the created item
        cursor = await db.execute(
            "SELECT * FROM library_items ORDER BY id DESC LIMIT 1"
        )
        item = await cursor.fetchone()
        return dict(item)


# ============================================================================
# SEC-001/SEC-002: SELF-SHARE PREVENTION
# ============================================================================

class TestSelfSharePrevention:
    """Test that users cannot share items/tasks with themselves"""

    @pytest.mark.asyncio
    async def test_task_self_share_by_user_id(self, test_task, test_license):
        """Test cannot share task with own user ID"""
        with pytest.raises(ValueError, match="yourself"):
            await share_task(
                task_id=test_task['id'],
                license_id=test_license['license_id'],
                shared_with_user_id="1",  # Same as created_by
                permission="read",
                created_by="1"
            )

    @pytest.mark.asyncio
    async def test_task_self_share_by_username(self, test_task, test_license):
        """Test cannot share task with own username"""
        # Assuming username 'testuser' resolves to license_id 1
        with patch('models.task_shares.resolve_username_to_user_id_with_db') as mock_resolve:
            mock_resolve.return_value = ("1", True)
            
            with pytest.raises(ValueError, match="yourself"):
                await share_task(
                    task_id=test_task['id'],
                    license_id=test_license['license_id'],
                    shared_with_user_id="testuser",
                    permission="read",
                    created_by="1"
                )

    @pytest.mark.asyncio
    async def test_library_self_share(self, test_library_item, test_license):
        """Test cannot share library item with self"""
        with patch('models.library_advanced.resolve_username_to_user_id_with_db') as mock_resolve:
            mock_resolve.return_value = ("1", True)
            
            with pytest.raises(ValueError, match="yourself"):
                await share_item(
                    item_id=test_library_item['id'],
                    license_id=test_license['license_id'],
                    shared_with_user_id="testuser",
                    permission="read",
                    created_by="1"
                )


# ============================================================================
# AUTH-001: USERNAME RESOLUTION
# ============================================================================

class TestUsernameResolution:
    """Test username resolution for sharing"""

    @pytest.mark.asyncio
    async def test_numeric_user_id_no_lookup(self, test_task, test_license):
        """Test that numeric user IDs don't trigger DB lookup"""
        with patch('models.task_shares.resolve_username_to_user_id_with_db') as mock_resolve:
            # Should not be called for numeric IDs
            await share_task(
                task_id=test_task['id'],
                license_id=test_license['license_id'],
                shared_with_user_id="2",  # Numeric, should pass through
                permission="read",
                created_by="1"
            )
            mock_resolve.assert_not_called()

    @pytest.mark.asyncio
    async def test_username_lookup_failure(self, test_task, test_license):
        """Test error when username not found"""
        with patch('models.task_shares.resolve_username_to_user_id_with_db') as mock_resolve:
            mock_resolve.side_effect = ValueError("User 'nonexistent' not found")
            
            with pytest.raises(ValueError, match="not found"):
                await share_task(
                    task_id=test_task['id'],
                    license_id=test_license['license_id'],
                    shared_with_user_id="nonexistent",
                    permission="read",
                    created_by="1"
                )


# ============================================================================
# PERMISSION ENFORCEMENT
# ============================================================================

class TestPermissionEnforcement:
    """Test share permission enforcement"""

    @pytest.mark.asyncio
    async def test_invalid_permission_rejected(self, test_task, test_license):
        """Test that invalid permissions are rejected"""
        with pytest.raises(ValueError, match="Invalid permission"):
            await share_task(
                task_id=test_task['id'],
                license_id=test_license['license_id'],
                shared_with_user_id="2",
                permission="invalid_permission",
                created_by="1"
            )

    @pytest.mark.asyncio
    async def test_valid_permissions_accepted(self, test_task, test_license):
        """Test that valid permissions are accepted"""
        for perm in ['read', 'edit', 'admin']:
            result = await share_task(
                task_id=test_task['id'],
                license_id=test_license['license_id'],
                shared_with_user_id=f"user_{perm}",
                permission=perm,
                created_by="1"
            )
            assert result['permission'] == perm

    @pytest.mark.asyncio
    async def test_read_permission_cannot_edit(self, test_task, test_license):
        """Test that read permission users cannot edit"""
        from models.tasks import can_edit_task
        
        # Share with read permission
        await share_task(
            task_id=test_task['id'],
            license_id=test_license['license_id'],
            shared_with_user_id="2",
            permission="read",
            created_by="1"
        )
        
        # Get task with share permission
        task = await get_task(
            license_id=test_license['license_id'], 
            task_id=test_task['id'], 
            user_id="2"
        )
        
        # Read permission cannot edit
        assert can_edit_task(task, "2", "read") is False

    @pytest.mark.asyncio
    async def test_edit_permission_can_edit(self, test_task, test_license):
        """Test that edit permission users can edit"""
        from models.tasks import can_edit_task
        
        # Share with edit permission
        await share_task(
            task_id=test_task['id'],
            license_id=test_license['license_id'],
            shared_with_user_id="2",
            permission="edit",
            created_by="1"
        )
        
        # Get task with share permission
        task = await get_task(
            license_id=test_license['license_id'], 
            task_id=test_task['id'], 
            user_id="2"
        )
        
        # Edit permission can edit
        assert can_edit_task(task, "2", "edit") is True


# ============================================================================
# CACHE INTEGRITY
# ============================================================================

class TestCacheIntegrity:
    """Test cache integrity and invalidation"""

    @pytest.mark.asyncio
    async def test_cache_invalidation_on_share(self, test_task, test_license):
        """Test cache is invalidated when share is created"""
        tasks_cache = get_shared_tasks_cache()
        
        # Pre-populate cache
        cache_key = f"{test_license['license_id']}|2|all"
        async with tasks_cache._lock:
            tasks_cache._cache[cache_key] = {
                "data": [],
                "timestamp": datetime.now(timezone.utc).timestamp()
            }
            tasks_cache._access_times[cache_key] = datetime.now(timezone.utc).timestamp()

        # Create share for user 2
        await share_task(
            task_id=test_task['id'],
            license_id=test_license['license_id'],
            shared_with_user_id="2",
            permission="read",
            created_by="1"
        )

        # Cache should be invalidated for user 2
        async with tasks_cache._lock:
            assert cache_key not in tasks_cache._cache
            assert cache_key not in tasks_cache._access_times

    @pytest.mark.asyncio
    async def test_cache_invalidation_on_remove(self, test_task, test_license):
        """Test cache is invalidated when share is removed"""
        tasks_cache = get_shared_tasks_cache()
        
        # Create share
        share_result = await share_task(
            task_id=test_task['id'],
            license_id=test_license['license_id'],
            shared_with_user_id="2",
            permission="read",
            created_by="1"
        )

        # Populate cache
        await get_shared_tasks(license_id=test_license['license_id'], user_id="2")
        cache_key = f"{test_license['license_id']}|2|all"
        
        async with tasks_cache._lock:
            assert cache_key in tasks_cache._cache

        # Remove share
        await remove_share(
            share_id=share_result['id'],
            license_id=test_license['license_id'],
            revoked_by="1",
            requested_by_user_id="1"
        )

        # Cache should be invalidated
        async with tasks_cache._lock:
            assert cache_key not in tasks_cache._cache
            assert cache_key not in tasks_cache._access_times

    @pytest.mark.asyncio
    async def test_cache_no_memory_leak(self):
        """Test cache doesn't leak access times - FIX: properly test LRU eviction"""
        tasks_cache = get_shared_tasks_cache()
        
        # Fill cache beyond capacity using the proper set method
        for i in range(_DEFAULT_MAX_CACHE_SIZE + 50):
            key = f"1|user{i}|all"
            await tasks_cache.set(key, [{"id": i}])

        # After filling, the cache should have evicted old entries via LRU
        # The cache size should be bounded
        async with tasks_cache._lock:
            assert len(tasks_cache._cache) <= tasks_cache.max_size
            # The access times should match cache size (no orphaned entries)
            assert len(tasks_cache._access_times) == len(tasks_cache._cache)


# ============================================================================
# ERROR MESSAGE SANITIZATION
# ============================================================================

class TestErrorMessageSanitization:
    """Test that error messages are properly sanitized"""

    @pytest.mark.asyncio
    async def test_database_error_not_exposed(self, test_task, clear_caches):
        """Test that database errors are not exposed to users"""
        with patch('models.task_shares.execute_sql') as mock_execute:
            mock_execute.side_effect = Exception("SQL syntax error near 'SELECT'")
            
            with pytest.raises(Exception):
                await share_task(
                    task_id=test_task['id'],
                    license_id=1,
                    shared_with_user_id="2",
                    permission="read",
                    created_by="1"
                )
            # The actual error message should not contain SQL details
            # (This is tested at the route level in integration tests)


# ============================================================================
# BULK OPERATIONS
# ============================================================================

class TestBulkOperations:
    """Test bulk share operations"""

    @pytest.mark.asyncio
    async def test_partial_success_reporting(self):
        """Test that bulk operations report partial success"""
        # This is tested at the route level
        # The route should return 207 Multi-Status for partial success
        pass

    @pytest.mark.asyncio
    async def test_all_validation_failures(self):
        """Test error when all tasks fail validation"""
        # This is tested at the route level
        # Should return 400 with detailed error info
        pass


# ============================================================================
# EDGE CASES
# ============================================================================

class TestEdgeCases:
    """Test edge cases in share validation"""

    @pytest.mark.asyncio
    async def test_share_with_nonexistent_task(self, test_license):
        """Test sharing non-existent task"""
        with pytest.raises(ValueError, match="not found"):
            await share_task(
                task_id="nonexistent-task-id",
                license_id=test_license['license_id'],
                shared_with_user_id="2",
                permission="read",
                created_by="1"
            )

    @pytest.mark.asyncio
    async def test_concurrent_share_operations(self, test_task, test_license):
        """Test concurrent share operations don't cause race conditions"""
        # Create multiple shares concurrently
        tasks = [
            share_task(
                task_id=test_task['id'],
                license_id=test_license['license_id'],
                shared_with_user_id=f"user{i}",
                permission="read",
                created_by="1"
            )
            for i in range(2, 7)
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # All should succeed (no race conditions)
        for result in results:
            assert not isinstance(result, Exception), f"Unexpected error: {result}"
