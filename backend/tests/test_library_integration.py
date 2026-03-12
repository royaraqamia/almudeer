"""
Al-Mudeer - Library Integration Tests

Comprehensive integration tests for library feature:
1. Concurrent upload race conditions
2. Share permission escalation attempts
3. Cache invalidation under load
4. Bulk operations atomicity
5. Storage quota enforcement

Run with: pytest tests/test_library_integration.py -v
"""

import pytest
import asyncio
import os
import hashlib
import tempfile
import time
from datetime import datetime, timezone, timedelta
from typing import List, Tuple
from unittest.mock import AsyncMock, patch, MagicMock

# Test constants - Use license ID 1 which is seeded in conftest
TEST_LICENSE_ID = 1
TEST_USER_ID = "test_user@example.com"
TEST_USER_2_ID = "test_user2@example.com"


class TestConcurrentUploads:
    """Test concurrent upload race conditions (Issue #2)"""

    @pytest.mark.asyncio
    async def test_concurrent_uploads_atomic_storage_check(self):
        """
        Verify that concurrent uploads don't exceed storage limits
        due to race conditions in storage calculation.
        
        This test simulates multiple uploads happening simultaneously
        and ensures the atomic storage check prevents exceeding limits.
        """
        from models.library import (
            add_library_item, 
            delete_library_item, 
            get_storage_usage,
            MAX_STORAGE_PER_LICENSE,
            _invalidate_storage_cache
        )
        
        # Clean up any existing items
        await _invalidate_storage_cache(TEST_LICENSE_ID)
        
        # Calculate how many 1MB files would approach the limit
        file_size = 1 * 1024 * 1024  # 1MB
        max_files = (MAX_STORAGE_PER_LICENSE // file_size) - 1  # Leave room for test
        
        # Create items up to near limit
        created_items = []
        for i in range(max_files):
            try:
                item = await add_library_item(
                    license_id=TEST_LICENSE_ID,
                    user_id=TEST_USER_ID,
                    item_type="file",
                    title=f"Pre-fill {i}",
                    file_path=f"/test/path_{i}.bin",
                    file_size=file_size,
                    mime_type="application/octet-stream"
                )
                created_items.append(item["id"])
            except ValueError:
                break
        
        # Now try concurrent uploads that would exceed limit if race condition exists
        async def try_upload():
            try:
                item = await add_library_item(
                    license_id=TEST_LICENSE_ID,
                    user_id=TEST_USER_ID,
                    item_type="file",
                    title=f"Concurrent upload {asyncio.current_task().get_name()}",
                    file_path="/test/concurrent.bin",
                    file_size=file_size,
                    mime_type="application/octet-stream"
                )
                return item
            except ValueError as e:
                return None  # Expected - storage limit
        
        # Run 10 concurrent uploads
        tasks = [try_upload() for _ in range(10)]
        results = await asyncio.gather(*tasks)
        
        # Count successful uploads
        successful = [r for r in results if r is not None]
        
        # Verify storage wasn't exceeded
        final_usage = await get_storage_usage(TEST_LICENSE_ID)
        storage_exceeded = final_usage > MAX_STORAGE_PER_LICENSE
        
        # Cleanup
        for item_id in created_items:
            try:
                await delete_library_item(TEST_LICENSE_ID, item_id)
            except:
                pass
        
        for item in successful:
            try:
                await delete_library_item(TEST_LICENSE_ID, item["id"])
            except:
                pass
        
        # Assert: Storage limit should not be exceeded
        assert not storage_exceeded, f"Storage exceeded: {final_usage} > {MAX_STORAGE_PER_LICENSE}"
        
        # At most 1 concurrent upload should succeed (the one that fits)
        assert len(successful) <= 1, f"Race condition detected: {len(successful)} uploads succeeded"

    @pytest.mark.asyncio
    async def test_sqlite_application_lock_prevents_race(self):
        """
        Verify SQLite application-level lock prevents race conditions.
        """
        from models.library import _get_storage_lock, _storage_locks
        
        # Get locks for same license
        lock1 = await _get_storage_lock(TEST_LICENSE_ID)
        lock2 = await _get_storage_lock(TEST_LICENSE_ID)
        
        # Should be the same lock instance
        assert lock1 is lock2, "Application lock not singleton per license"
        
        # Verify lock actually works
        acquired = []
        
        async def acquire_lock(task_id):
            async with lock1:
                acquired.append(task_id)
                await asyncio.sleep(0.1)  # Hold lock
        
        # Run concurrent tasks
        await asyncio.gather(
            acquire_lock(1),
            acquire_lock(2),
            acquire_lock(3)
        )
        
        # All should have acquired (sequentially)
        assert len(acquired) == 3


class TestSharePermissionEscalation:
    """Test share permission security (SEC-002, P3-14)"""

    @pytest.fixture
    async def setup_shared_item(self, db_session):
        """Create a shared item for testing"""
        from models.library import add_library_item
        from models.library_advanced import share_item
        
        # Create item
        item = await add_library_item(
            license_id=1,
            user_id="owner@example.com",
            item_type="note",
            title="Shared Note",
            content="Test content"
        )
        
        # Share with read permission
        share = await share_item(
            item_id=item["id"],
            license_id=1,
            shared_with_user_id="reader@example.com",
            permission="read",
            created_by="owner@example.com"
        )
        
        return {
            "item": item,
            "share": share
        }

    @pytest.mark.asyncio
    async def test_read_user_cannot_edit(self, setup_shared_item):
        """Verify read-only users cannot edit items"""
        from models.library import update_library_item, verify_share_permission
        
        item = setup_shared_item["item"]
        
        async with get_db() as db:
            # Verify permission check
            has_edit = await verify_share_permission(
                db=db,
                item_id=item["id"],
                user_id="reader@example.com",
                license_id=1,
                required_permission="edit"
            )
            
            assert has_edit is False, "Read user should not have edit permission"
        
        # Try to update
        success = await update_library_item(
            license_id=1,
            item_id=item["id"],
            user_id="reader@example.com",
            title="Hacked Title"
        )
        
        assert success is False, "Read user should not be able to update"

    @pytest.mark.asyncio
    async def test_read_user_cannot_delete(self, setup_shared_item):
        """Verify read-only users cannot delete items"""
        from models.library import delete_library_item
        
        item = setup_shared_item["item"]
        
        success = await delete_library_item(
            license_id=1,
            item_id=item["id"],
            user_id="reader@example.com"
        )
        
        assert success is False, "Read user should not be able to delete"

    @pytest.mark.asyncio
    async def test_read_user_cannot_share(self, setup_shared_item):
        """Verify read-only users cannot share items with others"""
        from models.library_advanced import share_item
        
        item = setup_shared_item["item"]
        
        with pytest.raises(Exception):
            await share_item(
                item_id=item["id"],
                license_id=1,
                shared_with_user_id="third_party@example.com",
                permission="read",
                created_by="reader@example.com"
            )

    @pytest.mark.asyncio
    async def test_edit_user_cannot_delete(self, db_session):
        """Verify edit users cannot delete items (only admin can)"""
        from models.library import add_library_item, delete_library_item
        from models.library_advanced import share_item
        
        # Create item
        item = await add_library_item(
            license_id=1,
            user_id="owner@example.com",
            item_type="note",
            title="Test Note"
        )
        
        # Share with edit permission
        await share_item(
            item_id=item["id"],
            license_id=1,
            shared_with_user_id="editor@example.com",
            permission="edit",
            created_by="owner@example.com"
        )
        
        # Try to delete
        success = await delete_library_item(
            license_id=1,
            item_id=item["id"],
            user_id="editor@example.com"
        )
        
        assert success is False, "Edit user should not be able to delete"

    @pytest.mark.asyncio
    async def test_admin_user_can_do_everything(self, db_session):
        """Verify admin users have full access"""
        from models.library import add_library_item, update_library_item, delete_library_item
        from models.library_advanced import share_item, verify_share_permission
        
        # Create item
        item = await add_library_item(
            license_id=1,
            user_id="owner@example.com",
            item_type="note",
            title="Test Note"
        )
        
        # Share with admin permission
        await share_item(
            item_id=item["id"],
            license_id=1,
            shared_with_user_id="admin@example.com",
            permission="admin",
            created_by="owner@example.com"
        )
        
        async with get_db() as db:
            # Verify admin can edit
            can_edit = await verify_share_permission(
                db=db,
                item_id=item["id"],
                user_id="admin@example.com",
                license_id=1,
                required_permission="edit"
            )
            assert can_edit is True
            
            # Verify admin can delete
            can_delete = await verify_share_permission(
                db=db,
                item_id=item["id"],
                user_id="admin@example.com",
                license_id=1,
                required_permission="admin"
            )
            assert can_delete is True
        
        # Admin can update
        success = await update_library_item(
            license_id=1,
            item_id=item["id"],
            user_id="admin@example.com",
            title="Updated by Admin"
        )
        assert success is True
        
        # Admin can delete
        success = await delete_library_item(
            license_id=1,
            item_id=item["id"],
            user_id="admin@example.com"
        )
        assert success is True

    @pytest.mark.asyncio
    async def test_self_share_prevention(self, db_session):
        """SEC-002: Verify users cannot share items with themselves"""
        from models.library import add_library_item
        from models.library_advanced import share_item
        
        # Create item
        item = await add_library_item(
            license_id=1,
            user_id="owner@example.com",
            item_type="note",
            title="Test Note"
        )
        
        # Try to share with self
        with pytest.raises(ValueError, match="Cannot share an item with yourself"):
            await share_item(
                item_id=item["id"],
                license_id=1,
                shared_with_user_id="owner@example.com",
                permission="read",
                created_by="owner@example.com"
            )

    @pytest.mark.asyncio
    async def test_permission_escalation_attempt(self, db_session):
        """Verify users cannot escalate their own permissions"""
        from models.library import add_library_item
        from models.library_advanced import share_item, update_share_permission
        
        # Create item
        item = await add_library_item(
            license_id=1,
            user_id="owner@example.com",
            item_type="note",
            title="Test Note"
        )
        
        # Share with read permission
        share = await share_item(
            item_id=item["id"],
            license_id=1,
            shared_with_user_id="reader@example.com",
            permission="read",
            created_by="owner@example.com"
        )
        
        # Reader tries to escalate to admin
        with pytest.raises(Exception):
            await update_share_permission(
                share_id=share["id"],
                license_id=1,
                permission="admin",
                requested_by_user_id="reader@example.com"
            )


class TestCacheInvalidation:
    """Test cache invalidation under load"""

    @pytest.mark.asyncio
    async def test_storage_cache_invalid_on_add(self):
        """Verify storage cache is invalidated when items are added"""
        from models.library import (
            add_library_item,
            delete_library_item,
            _get_cached_storage_usage,
            _set_cached_storage_usage,
            _invalidate_storage_cache
        )
        
        await _invalidate_storage_cache(TEST_LICENSE_ID)
        
        # Set cache
        await _set_cached_storage_usage(TEST_LICENSE_ID, 1000)
        
        # Verify cache exists
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached == 1000
        
        # Add item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Cache Test"
        )
        
        # Cache should be invalidated
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached is None, "Cache should be invalidated after add"
        
        # Cleanup
        await delete_library_item(TEST_LICENSE_ID, item["id"])

    @pytest.mark.asyncio
    async def test_storage_cache_invalid_on_delete(self):
        """Verify storage cache is invalidated when items are deleted"""
        from models.library import (
            add_library_item,
            delete_library_item,
            _get_cached_storage_usage,
            _set_cached_storage_usage,
            _invalidate_storage_cache
        )
        
        await _invalidate_storage_cache(TEST_LICENSE_ID)
        
        # Create item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="file",
            title="Delete Test",
            file_size=5000
        )
        
        # Set cache
        await _set_cached_storage_usage(TEST_LICENSE_ID, 5000)
        
        # Delete item
        await delete_library_item(TEST_LICENSE_ID, item["id"])
        
        # Cache should be invalidated
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached is None, "Cache should be invalidated after delete"

    @pytest.mark.asyncio
    async def test_storage_cache_invalid_on_update(self):
        """Verify storage cache is invalidated when file_size is updated"""
        from models.library import (
            add_library_item,
            delete_library_item,
            update_library_item,
            _get_cached_storage_usage,
            _set_cached_storage_usage,
            _invalidate_storage_cache
        )
        
        await _invalidate_storage_cache(TEST_LICENSE_ID)
        
        # Create item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="file",
            title="Update Test",
            file_size=1000
        )
        
        # Set cache
        await _set_cached_storage_usage(TEST_LICENSE_ID, 1000)
        
        # Update file_size
        await update_library_item(
            license_id=TEST_LICENSE_ID,
            item_id=item["id"],
            file_size=2000
        )
        
        # Cache should be invalidated
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached is None, "Cache should be invalidated after file_size update"
        
        # Cleanup
        await delete_library_item(TEST_LICENSE_ID, item["id"])

    @pytest.mark.asyncio
    async def test_shared_items_cache_invalid_on_remove_share(self):
        """Verify shared items cache is invalidated when shares are removed"""
        from models.library import add_library_item
        from models.library_advanced import (
            share_item,
            remove_share,
            get_shared_items,
            get_shared_items_cache
        )
        
        # Create item
        item = await add_library_item(
            license_id=1,
            user_id="owner@example.com",
            item_type="note",
            title="Share Test"
        )
        
        # Share item
        share = await share_item(
            item_id=item["id"],
            license_id=1,
            shared_with_user_id="shared@example.com",
            permission="read",
            created_by="owner@example.com"
        )
        
        # Get shared items (populate cache)
        cache = get_shared_items_cache()
        await get_shared_items(license_id=1, user_id="shared@example.com")
        
        # Verify cache is populated
        cache_key = "1|shared@example.com|all"
        cached = await cache.get(cache_key)
        assert cached is not None, "Cache should be populated"
        
        # Remove share
        await remove_share(share_id=share["id"], license_id=1)
        
        # Cache should be invalidated
        cached = await cache.get(cache_key)
        assert cached is None, "Cache should be invalidated after share removal"
        
        # Cleanup
        from models.library import delete_library_item
        await delete_library_item(1, item["id"])

    @pytest.mark.asyncio
    async def test_cache_ttl_expires(self):
        """Verify cache TTL expires correctly"""
        from models.library import (
            _get_cached_storage_usage,
            _set_cached_storage_usage,
            _STORAGE_CACHE_TTL
        )
        import time
        
        # Set cache
        await _set_cached_storage_usage(TEST_LICENSE_ID, 5000)
        
        # Verify cache exists
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached == 5000
        
        # Wait for TTL
        await asyncio.sleep(_STORAGE_CACHE_TTL + 1)
        
        # Cache should be expired
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached is None, "Cache should expire after TTL"


class TestBulkOperationsAtomicity:
    """Test bulk operations maintain atomicity"""

    @pytest.mark.asyncio
    async def test_bulk_delete_partial_failure(self):
        """Verify bulk delete handles partial failures correctly"""
        from models.library import add_library_item, bulk_delete_items
        
        # Create items
        item1 = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Item 1"
        )
        
        item2 = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Item 2"
        )
        
        # Bulk delete with mix of valid and invalid IDs
        result = await bulk_delete_items(
            license_id=TEST_LICENSE_ID,
            item_ids=[item1["id"], item2["id"], 999999],  # 999999 doesn't exist
            user_id=TEST_USER_ID
        )
        
        # Verify detailed result
        assert "deleted_count" in result
        assert "deleted_ids" in result
        assert "failed_ids" in result
        
        # Should delete 2, fail 1
        assert result["deleted_count"] == 2
        assert item1["id"] in result["deleted_ids"]
        assert item2["id"] in result["deleted_ids"]
        assert 999999 in result["failed_ids"]
        
        # Cleanup
        from models.library import delete_library_item
        await delete_library_item(TEST_LICENSE_ID, item1["id"])
        await delete_library_item(TEST_LICENSE_ID, item2["id"])

    @pytest.mark.asyncio
    async def test_bulk_delete_ownership_validation(self):
        """Verify bulk delete validates ownership for each item"""
        from models.library import add_library_item, bulk_delete_items
        from models.library_advanced import share_item
        
        # Create items with different owners
        item1 = await add_library_item(
            license_id=1,
            user_id="user1@example.com",
            item_type="note",
            title="User1 Item"
        )
        
        item2 = await add_library_item(
            license_id=1,
            user_id="user2@example.com",
            item_type="note",
            title="User2 Item"
        )
        
        # Share item2 with user1 (read only)
        await share_item(
            item_id=item2["id"],
            license_id=1,
            shared_with_user_id="user1@example.com",
            permission="read",
            created_by="user2@example.com"
        )
        
        # User1 tries to bulk delete both
        result = await bulk_delete_items(
            license_id=1,
            item_ids=[item1["id"], item2["id"]],
            user_id="user1@example.com"
        )
        
        # Should only delete own item
        assert result["deleted_count"] == 1
        assert item1["id"] in result["deleted_ids"]
        assert item2["id"] in result["failed_ids"]
        
        # Cleanup
        from models.library import delete_library_item
        await delete_library_item(1, item1["id"])
        await delete_library_item(1, item2["id"])


class TestStorageQuotaEnforcement:
    """Test storage quota enforcement"""

    @pytest.mark.asyncio
    async def test_storage_quota_prevents_upload(self):
        """Verify storage quota prevents uploads when exceeded"""
        from models.library import (
            add_library_item,
            delete_library_item,
            MAX_STORAGE_PER_LICENSE
        )
        
        # Try to create item exceeding limit
        with pytest.raises(ValueError, match="تجاوزت حد التخزين"):
            await add_library_item(
                license_id=TEST_LICENSE_ID,
                user_id=TEST_USER_ID,
                item_type="file",
                title="Huge File",
                file_path="/test/huge.bin",
                file_size=MAX_STORAGE_PER_LICENSE + 1
            )

    @pytest.mark.asyncio
    async def test_storage_quota_includes_attachments(self):
        """Verify storage quota includes attachment sizes"""
        from models.library import add_library_item, delete_library_item, get_storage_usage
        from models.library_attachments import add_attachment, delete_attachment
        
        # Create parent item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Parent"
        )
        
        # Add attachment
        attachment = await add_attachment(
            license_id=TEST_LICENSE_ID,
            item_id=item["id"],
            file_path="/test/attachment.bin",
            filename="test.bin",
            file_size=50000,
            mime_type="application/octet-stream"
        )
        
        # Verify storage includes attachment
        usage = await get_storage_usage(TEST_LICENSE_ID)
        assert usage >= 50000, "Storage should include attachment size"
        
        # Cleanup
        await delete_attachment(attachment["id"], TEST_LICENSE_ID)
        await delete_library_item(TEST_LICENSE_ID, item["id"])


# Helper for tests needing db
async def get_db():
    from db_helper import get_db as db_helper_get_db
    return db_helper_get_db()


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
