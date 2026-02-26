"""
Al-Mudeer - Library Module Unit Tests

Tests for library models, CRUD operations, and business logic.
"""

import pytest
import asyncio
import os
import hashlib
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch, MagicMock

# Test constants
TEST_LICENSE_ID = 999
TEST_USER_ID = "test_user@example.com"


class TestLibraryModels:
    """Test library model functions"""

    @pytest.mark.asyncio
    async def test_get_storage_usage(self):
        """Test storage usage calculation"""
        from models.library import get_storage_usage, _invalidate_storage_cache
        
        # Test with non-existent license (should return 0)
        usage = await get_storage_usage(TEST_LICENSE_ID)
        assert usage >= 0
        
        # Test cache invalidation
        await _invalidate_storage_cache(TEST_LICENSE_ID)

    @pytest.mark.asyncio
    async def test_add_library_item_note(self):
        """Test adding a note to library"""
        from models.library import add_library_item, delete_library_item
        
        # Create a test note
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Test Note",
            content="This is test content"
        )
        
        assert item is not None
        assert item["title"] == "Test Note"
        assert item["type"] == "note"
        assert item["license_key_id"] == TEST_LICENSE_ID
        
        # Cleanup
        if item.get("id"):
            await delete_library_item(TEST_LICENSE_ID, item["id"])

    @pytest.mark.asyncio
    async def test_add_library_item_with_file_hash(self):
        """Test adding item with file hash for deduplication"""
        from models.library import add_library_item, delete_library_item
        
        # Compute test hash
        test_content = b"test file content"
        file_hash = hashlib.sha256(test_content).hexdigest()
        
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="file",
            title="Test File",
            file_path="/test/path.txt",
            file_size=len(test_content),
            mime_type="text/plain",
            file_hash=file_hash
        )
        
        assert item is not None
        assert item["file_hash"] == file_hash
        
        # Cleanup
        if item.get("id"):
            await delete_library_item(TEST_LICENSE_ID, item["id"])

    @pytest.mark.asyncio
    async def test_update_library_item(self):
        """Test updating library item metadata"""
        from models.library import add_library_item, update_library_item, delete_library_item
        
        # Create item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Original Title",
            content="Original content"
        )
        
        # Update title
        success = await update_library_item(
            TEST_LICENSE_ID,
            item["id"],
            title="Updated Title"
        )
        
        assert success is True
        
        # Cleanup
        await delete_library_item(TEST_LICENSE_ID, item["id"])

    @pytest.mark.asyncio
    async def test_update_library_item_invalidates_cache(self):
        """Test that updating file_size invalidates storage cache"""
        from models.library import add_library_item, update_library_item, delete_library_item, _get_cached_storage_usage
        
        # Create item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="file",
            title="Test File",
            file_path="/test/path.txt",
            file_size=1024,
            mime_type="text/plain"
        )
        
        # Set cache
        from models.library import _set_cached_storage_usage
        await _set_cached_storage_usage(TEST_LICENSE_ID, 5000)
        
        # Update file_size
        await update_library_item(
            TEST_LICENSE_ID,
            item["id"],
            file_size=2048
        )
        
        # Cache should be invalidated
        cached = await _get_cached_storage_usage(TEST_LICENSE_ID)
        assert cached is None
        
        # Cleanup
        await delete_library_item(TEST_LICENSE_ID, item["id"])

    @pytest.mark.asyncio
    async def test_delete_library_item_soft_delete(self):
        """Test soft delete functionality"""
        from models.library import add_library_item, delete_library_item, get_library_item
        
        # Create item
        item = await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="To Delete"
        )
        
        # Soft delete
        success = await delete_library_item(TEST_LICENSE_ID, item["id"])
        assert success is True
        
        # Item should not be visible in normal query
        deleted_item = await get_library_item(TEST_LICENSE_ID, item["id"])
        assert deleted_item is None
        
        # Note: For full test, we'd query with include_deleted=True
        # but that requires additional model function

    @pytest.mark.asyncio
    async def test_bulk_delete_items(self):
        """Test bulk delete functionality"""
        from models.library import add_library_item, bulk_delete_items
        
        # Create multiple items
        items = []
        for i in range(3):
            item = await add_library_item(
                license_id=TEST_LICENSE_ID,
                user_id=TEST_USER_ID,
                item_type="note",
                title=f"Test Note {i}"
            )
            items.append(item["id"])
        
        # Bulk delete
        success = await bulk_delete_items(TEST_LICENSE_ID, items)
        assert success is True

    @pytest.mark.asyncio
    async def test_storage_limit_enforcement(self):
        """Test that storage limits are enforced"""
        from models.library import add_library_item, MAX_STORAGE_PER_LICENSE
        import pytest
        
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
    async def test_get_library_items_pagination(self):
        """Test pagination in get_library_items"""
        from models.library import get_library_items
        
        # Create test items
        for i in range(5):
            await add_library_item(
                license_id=TEST_LICENSE_ID,
                user_id=TEST_USER_ID,
                item_type="note",
                title=f"Paginated Note {i}"
            )
        
        # Test pagination
        items_page1 = await get_library_items(
            license_id=TEST_LICENSE_ID,
            limit=2,
            offset=0
        )
        
        items_page2 = await get_library_items(
            license_id=TEST_LICENSE_ID,
            limit=2,
            offset=2
        )
        
        assert len(items_page1) <= 2
        assert len(items_page2) <= 2
        
        # Items should be different
        if items_page1 and items_page2:
            ids1 = {item["id"] for item in items_page1}
            ids2 = {item["id"] for item in items_page2}
            assert ids1.isdisjoint(ids2)

    @pytest.mark.asyncio
    async def test_get_library_items_search(self):
        """Test search functionality"""
        from models.library import get_library_items
        
        # Create test items with specific titles
        await add_library_item(
            license_id=TEST_LICENSE_ID,
            user_id=TEST_USER_ID,
            item_type="note",
            title="Search Test Note",
            content="This contains specific text"
        )
        
        # Search by title
        items = await get_library_items(
            license_id=TEST_LICENSE_ID,
            search_term="Search Test"
        )
        
        assert len(items) > 0
        assert any("Search Test" in item.get("title", "") for item in items)


class TestLibraryValidators:
    """Test library validation logic"""

    def test_mime_type_validation(self):
        """Test MIME type allowlist"""
        from routes.library import ALLOWED_MIME_TYPES
        
        # Valid types
        assert "image/jpeg" in ALLOWED_MIME_TYPES
        assert "application/pdf" in ALLOWED_MIME_TYPES
        assert "video/mp4" in ALLOWED_MIME_TYPES
        
        # Invalid types should not be in allowlist
        assert "application/x-executable" not in ALLOWED_MIME_TYPES

    def test_file_extension_validation(self):
        """Test file extension allowlist"""
        from routes.library import ALLOWED_EXTENSIONS
        
        # Valid extensions
        assert ".jpg" in ALLOWED_EXTENSIONS
        assert ".pdf" in ALLOWED_EXTENSIONS
        assert ".mp4" in ALLOWED_EXTENSIONS

    def test_constants_standardization(self):
        """Test that MAX_FILE_SIZE is consistent across modules"""
        from models.library import MAX_FILE_SIZE as MODEL_MAX
        from services.file_storage_service import MAX_FILE_SIZE as SERVICE_MAX
        from constants.tasks import MAX_FILE_SIZE as TASKS_MAX
        
        assert MODEL_MAX == SERVICE_MAX == TASKS_MAX
        assert MODEL_MAX == 20 * 1024 * 1024  # 20MB


class TestLibraryBackgroundJobs:
    """Test library background job functions"""

    @pytest.mark.asyncio
    async def test_cleanup_library_trash(self):
        """Test trash cleanup function"""
        from workers import cleanup_library_trash
        
        # Run cleanup (should complete without errors)
        deleted_count = await cleanup_library_trash()
        assert isinstance(deleted_count, int)
        assert deleted_count >= 0


@pytest.mark.asyncio
async def test_library_item_type_filtering():
    """Test filtering by item type"""
    from models.library import get_library_items, add_library_item, delete_library_item
    
    # Create different types of items
    note = await add_library_item(
        license_id=TEST_LICENSE_ID,
        user_id=TEST_USER_ID,
        item_type="note",
        title="Test Note"
    )
    
    file_item = await add_library_item(
        license_id=TEST_LICENSE_ID,
        user_id=TEST_USER_ID,
        item_type="file",
        title="Test File",
        file_path="/test.txt",
        file_size=100,
        mime_type="text/plain"
    )
    
    # Filter by note type
    notes = await get_library_items(
        license_id=TEST_LICENSE_ID,
        item_type="note"
    )
    
    # Filter by file type
    files = await get_library_items(
        license_id=TEST_LICENSE_ID,
        item_type="file"
    )
    
    assert all(item["type"] == "note" for item in notes)
    assert all(item["type"] == "file" for item in files)
    
    # Cleanup
    await delete_library_item(TEST_LICENSE_ID, note["id"])
    await delete_library_item(TEST_LICENSE_ID, file_item["id"])


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
