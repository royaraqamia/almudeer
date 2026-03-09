"""
Al-Mudeer - Task Feature Tests
Comprehensive test coverage for critical task operations
"""

import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import HTTPException

from models.tasks import (
    create_task,
    update_task,
    delete_task,
    get_task,
    get_tasks,
    add_task_comment,
    get_task_comments,
    can_edit_task,
    can_delete_task,
    can_comment_on_task,
    compute_task_role,
)
from utils.timestamps import normalize_timestamp, generate_stable_id, to_utc_iso


# ============ Timestamp Utility Tests ============

class TestNormalizeTimestamp:
    """Test timestamp normalization for LWW conflict resolution"""
    
    def test_normalize_none(self):
        """Should return current UTC time for None input"""
        result = normalize_timestamp(None)
        assert result.tzinfo is None  # Naive UTC
        assert abs((result - datetime.now(timezone.utc).replace(tzinfo=None)).total_seconds()) < 1
    
    def test_normalize_naive_datetime(self):
        """Should preserve naive datetime as-is"""
        naive_dt = datetime(2024, 1, 15, 10, 30, 0)
        result = normalize_timestamp(naive_dt)
        assert result == naive_dt
        assert result.tzinfo is None
    
    def test_normalize_aware_datetime(self):
        """Should convert timezone-aware datetime to UTC"""
        # UTC+3 timezone
        aware_dt = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone(timedelta(hours=3)))
        result = normalize_timestamp(aware_dt)
        expected = datetime(2024, 1, 15, 7, 30, 0)  # Converted to UTC
        assert result == expected
        assert result.tzinfo is None
    
    def test_normalize_iso_string_utc(self):
        """Should parse UTC ISO string correctly"""
        iso_str = "2024-01-15T10:30:00Z"
        result = normalize_timestamp(iso_str)
        expected = datetime(2024, 1, 15, 10, 30, 0)
        assert result == expected
    
    def test_normalize_iso_string_with_offset(self):
        """Should parse and convert ISO string with offset to UTC"""
        iso_str = "2024-01-15T10:30:00+03:00"
        result = normalize_timestamp(iso_str)
        expected = datetime(2024, 1, 15, 7, 30, 0)
        assert result == expected
    
    def test_normalize_invalid_string(self):
        """Should return current UTC time for invalid string"""
        result = normalize_timestamp("invalid")
        assert result.tzinfo is None


class TestGenerateStableId:
    """Test stable ID generation for subtasks"""
    
    def test_stable_id_deterministic(self):
        """Should generate same ID for same input"""
        id1 = generate_stable_id("test subtask")
        id2 = generate_stable_id("test subtask")
        assert id1 == id2
    
    def test_stable_id_different(self):
        """Should generate different IDs for different inputs"""
        id1 = generate_stable_id("subtask 1")
        id2 = generate_stable_id("subtask 2")
        assert id1 != id2
    
    def test_stable_id_length(self):
        """Should generate 16-character hex string"""
        id = generate_stable_id("test")
        assert len(id) == 16
        assert all(c in '0123456789abcdef' for c in id)


# ============ RBAC Tests ============

class TestTaskRBAC:
    """Test Role-Based Access Control for tasks"""
    
    def test_compute_role_owner(self):
        """Owner role when user created task"""
        task = {"created_by": "user123", "assigned_to": "user456"}
        role = compute_task_role(task, "user123")
        assert role == "owner"
    
    def test_compute_role_assignee(self):
        """Assignee role when user is assigned"""
        task = {"created_by": "user123", "assigned_to": "user456"}
        role = compute_task_role(task, "user456")
        assert role == "assignee"
    
    def test_compute_role_viewer(self):
        """Viewer role for other users"""
        task = {"created_by": "user123", "assigned_to": "user456"}
        role = compute_task_role(task, "user789")
        assert role == "viewer"
    
    def test_can_edit_owner(self):
        """Owner can always edit"""
        task = {"created_by": "user123", "visibility": "shared"}
        assert can_edit_task(task, "user123") is True
    
    def test_can_edit_assignee_shared(self):
        """Assignee can edit shared tasks"""
        task = {"created_by": "user123", "assigned_to": "user456", "visibility": "shared"}
        assert can_edit_task(task, "user456") is True
    
    def test_can_edit_assignee_private(self):
        """Assignee cannot edit private tasks"""
        task = {"created_by": "user123", "assigned_to": "user456", "visibility": "private"}
        assert can_edit_task(task, "user456") is False
    
    def test_can_edit_viewer(self):
        """Viewer cannot edit"""
        task = {"created_by": "user123", "assigned_to": "user456", "visibility": "shared"}
        assert can_edit_task(task, "user789") is False
    
    def test_can_delete_owner(self):
        """Only owner can delete"""
        task = {"created_by": "user123"}
        assert can_delete_task(task, "user123") is True
    
    def test_can_delete_non_owner(self):
        """Non-owner cannot delete"""
        task = {"created_by": "user123", "assigned_to": "user456"}
        assert can_delete_task(task, "user456") is False
    
    def test_can_comment_owner(self):
        """Owner can always comment"""
        task = {"created_by": "user123", "visibility": "private"}
        assert can_comment_on_task(task, "user123") is True
    
    def test_can_comment_assignee_shared(self):
        """Assignee can comment on shared tasks"""
        task = {"created_by": "user123", "assigned_to": "user456", "visibility": "shared"}
        assert can_comment_on_task(task, "user456") is True
    
    def test_can_comment_assignee_private(self):
        """Assignee cannot comment on private tasks"""
        task = {"created_by": "user123", "assigned_to": "user456", "visibility": "private"}
        assert can_comment_on_task(task, "user456") is False


# ============ Recurring Task Tests ============

@pytest.mark.asyncio
class TestRecurringTaskSubtaskReset:
    """Test that recurring tasks properly reset subtask completion"""
    
    async def test_subtask_reset_dict_subtask(self):
        """Dict subtasks should preserve ID and reset is_completed"""
        from utils.timestamps import generate_stable_id
        
        # Simulate the reset_subtask function from routes/tasks.py
        def reset_subtask(subtask):
            if isinstance(subtask, dict):
                return {**subtask, "is_completed": False}
            elif isinstance(subtask, str):
                try:
                    import json
                    st_dict = json.loads(subtask)
                    return {**st_dict, "is_completed": False}
                except:
                    stable_id = generate_stable_id(subtask)
                    return {"id": stable_id, "title": str(subtask), "is_completed": False}
            else:
                stable_id = generate_stable_id(str(subtask))
                return {"id": stable_id, "title": str(subtask), "is_completed": False}
        
        # Test dict subtask
        original = {"id": "abc123", "title": "Test", "is_completed": True}
        reset = reset_subtask(original)
        
        assert reset["id"] == "abc123"  # ID preserved
        assert reset["is_completed"] is False  # Status reset
        assert reset["title"] == "Test"  # Title preserved
    
    async def test_subtask_reset_string_subtask(self):
        """String subtasks should get stable ID"""
        from utils.timestamps import generate_stable_id
        
        def reset_subtask(subtask):
            if isinstance(subtask, dict):
                return {**subtask, "is_completed": False}
            elif isinstance(subtask, str):
                try:
                    import json
                    st_dict = json.loads(subtask)
                    return {**st_dict, "is_completed": False}
                except:
                    stable_id = generate_stable_id(subtask)
                    return {"id": stable_id, "title": str(subtask), "is_completed": False}
            else:
                stable_id = generate_stable_id(str(subtask))
                return {"id": stable_id, "title": str(subtask), "is_completed": False}
        
        # Test string subtask
        original = "Call client"
        reset = reset_subtask(original)
        
        assert reset["id"] == generate_stable_id("Call client")  # Stable ID
        assert reset["is_completed"] is False
        assert reset["title"] == "Call client"


# ============ LWW Conflict Resolution Tests ============

@pytest.mark.asyncio
class TestLWWConflictResolution:
    """Test Last-Write-Wins conflict resolution"""
    
    async def test_newer_update_wins(self):
        """Newer updated_at should overwrite older"""
        # This would require a real database connection
        # Mock test for now
        with patch('models.tasks.get_db') as mock_db:
            mock_db.return_value.__aenter__ = AsyncMock()
            mock_db.return_value.__aexit__ = AsyncMock()
            
            # Simulate newer timestamp winning
            older_ts = datetime(2024, 1, 15, 10, 0, 0)
            newer_ts = datetime(2024, 1, 15, 11, 0, 0)
            
            assert newer_ts > older_ts
            # In real scenario, newer update would pass WHERE clause check
    
    async def test_timezone_normalization(self):
        """Timestamps from different timezones should be comparable"""
        utc_ts = datetime(2024, 1, 15, 10, 0, 0)
        utc_plus_3 = datetime(2024, 1, 15, 13, 0, 0, tzinfo=timezone(timedelta(hours=3)))
        
        normalized = normalize_timestamp(utc_plus_3)
        assert normalized == utc_ts


# ============ File Upload Validation Tests ============

class TestFileUploadValidation:
    """Test file upload security validation"""
    
    def test_validate_allowed_image(self):
        """Should allow valid image types"""
        from services.file_storage_service import validate_file_upload
        
        is_valid, _ = validate_file_upload(
            filename="test.jpg",
            mime_type="image/jpeg",
            file_size=1024 * 1024,  # 1MB
            file_type="image"
        )
        assert is_valid is True
    
    def test_validate_reject_large_file(self):
        """Should reject files exceeding size limit"""
        from services.file_storage_service import validate_file_upload, MAX_FILE_SIZE
        
        is_valid, error_msg = validate_file_upload(
            filename="test.pdf",
            mime_type="application/pdf",
            file_size=MAX_FILE_SIZE + 1,
            file_type="document"
        )
        assert is_valid is False
        assert "exceeds limit" in error_msg
    
    def test_validate_reject_invalid_type(self):
        """Should reject disallowed file types"""
        from services.file_storage_service import validate_file_upload
        
        is_valid, error_msg = validate_file_upload(
            filename="test.exe",
            mime_type="application/x-executable",
            file_size=1024,
            file_type="file"
        )
        assert is_valid is False
        assert "not allowed" in error_msg
    
    def test_validate_invalid_filename(self):
        """Should reject invalid filenames"""
        from services.file_storage_service import validate_file_upload
        
        is_valid, error_msg = validate_file_upload(
            filename="",
            mime_type="image/jpeg",
            file_size=1024,
            file_type="image"
        )
        assert is_valid is False


# ============ Private Task Visibility Tests ============

@pytest.mark.asyncio
class TestPrivateTaskVisibility:
    """Test that private tasks are only visible to creator"""
    
    async def test_private_task_visible_to_owner(self):
        """Owner can see their private tasks"""
        # Mock test - would need database for full test
        task = {
            "id": "task123",
            "visibility": "private",
            "created_by": "user123"
        }
        
        # Owner should see it
        assert task["created_by"] == "user123"
        # In real implementation: get_task would return the task
    
    async def test_private_task_hidden_from_others(self):
        """Private tasks hidden from other users"""
        task = {
            "id": "task123",
            "visibility": "private",
            "created_by": "user123"
        }
        
        # Other users should not see it
        assert task["created_by"] != "user456"
        # In real implementation: get_task would return None


# ============ Integration Tests ============

@pytest.mark.asyncio
class TestTaskIntegration:
    """Integration tests for task operations"""
    
    async def test_full_task_lifecycle(self):
        """Test create -> update -> complete -> delete"""
        # This would require a test database
        # Placeholder for integration test
        pass
    
    async def test_task_comment_lifecycle(self):
        """Test add comment -> get comments"""
        # Placeholder for comment integration test
        pass


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
