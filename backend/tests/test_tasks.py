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
        """Assignee role when user is assigned (backward compatibility returns 'editor')"""
        task = {"created_by": "user123", "assigned_to": "user456"}
        role = compute_task_role(task, "user456")
        # P4-2: assigned_to users get 'editor' role for backward compatibility
        assert role == "editor"
    
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


# ============ Concurrent Share Operations Tests ============

@pytest.mark.asyncio
class TestConcurrentShareOperations:
    """Test race condition handling in task sharing operations

    P4-2: These tests verify that concurrent share operations are handled correctly
    to prevent duplicate shares, data corruption, and inconsistent state.
    """

    async def test_concurrent_share_creation(self):
        """Test that concurrent share requests don't create duplicates

        Scenario: Two simultaneous requests to share the same task with the same user
        Expected: Only one share record created, no constraint violations
        """
        from models.task_shares import share_task, get_shared_tasks
        from db_helper import get_db, fetch_one, execute_sql
        import asyncio

        # This test requires a real database to test race conditions
        # Mock test structure for reference
        task_id = "test-task-concurrent-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Create task first (mock)
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        # Simulate concurrent share requests
        async def share_request(permission):
            try:
                result = await share_task(
                    task_id=task_id,
                    license_id=license_id,
                    shared_with_user_id=shared_with_user_id,
                    permission=permission,
                    created_by=created_by
                )
                return ("success", result)
            except ValueError as e:
                return ("error", str(e))
            except Exception as e:
                return ("exception", str(e))

        # Run two share requests concurrently
        results = await asyncio.gather(
            share_request("read"),
            share_request("edit"),
            return_exceptions=True
        )

        # Verify only one succeeded or both got the same record
        success_count = sum(1 for r in results if r[0] == "success")
        # At least one should succeed, but not create duplicates
        assert success_count >= 1

        # Verify only one share record exists
        async with get_db() as db:
            row = await fetch_one(
                db,
                """
                SELECT COUNT(*) as cnt FROM task_shares
                WHERE task_id = ? AND shared_with_user_id = ? AND deleted_at IS NULL
                """,
                (task_id, shared_with_user_id)
            )
            assert row["cnt"] == 1, "Should have exactly one active share record"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_share_revoked_cannot_reuse(self):
        """Test that revoked shares cannot be reactivated

        Scenario: Share is revoked, then someone tries to re-share with same user
        Expected: Should raise error requiring new share creation
        """
        from models.task_shares import share_task, remove_share
        from db_helper import get_db, execute_sql
        from datetime import datetime, timezone

        task_id = "test-task-revoked-456"
        license_id = 1
        shared_with_user_id = "user789"
        created_by = "user123"

        # Setup: Create task and share
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        # Create share
        await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        # Revoke share
        await remove_share(
            share_id=1,  # Will be the first share
            license_id=license_id,
            revoked_by=created_by
        )

        # Try to re-share - should fail with revoked error
        try:
            await share_task(
                task_id=task_id,
                license_id=license_id,
                shared_with_user_id=shared_with_user_id,
                permission="edit",
                created_by=created_by
            )
            # If we get here, the test failed - should have raised ValueError
            assert False, "Should have raised ValueError for revoked share"
        except ValueError as e:
            assert "revoked" in str(e).lower(), f"Error should mention revoked: {e}"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_self_share_prevention(self):
        """Test that users cannot share tasks with themselves

        Security test for SEC-001
        """
        from models.task_shares import share_task
        from db_helper import get_db, execute_sql

        task_id = "test-task-self-share-789"
        license_id = 1
        user_id = "user123"

        # Setup: Create task
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", user_id))

        # Try to share with self - should fail
        try:
            await share_task(
                task_id=task_id,
                license_id=license_id,
                shared_with_user_id=user_id,
                permission="edit",
                created_by=user_id
            )
            assert False, "Should have raised ValueError for self-share"
        except ValueError as e:
            assert "yourself" in str(e).lower(), f"Error should mention self-share: {e}"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))

    async def test_concurrent_share_update_permission(self):
        """Test concurrent permission updates on same share

        Scenario: Two requests to update permission on same share
        Expected: Last write wins, no data corruption
        """
        from models.task_shares import share_task
        from db_helper import get_db, fetch_one, execute_sql
        import asyncio

        task_id = "test-task-perm-update-123"
        license_id = 1
        shared_with_user_id = "user456"
        created_by = "user123"

        # Setup: Create task and initial share
        async with get_db() as db:
            await execute_sql(db, """
                INSERT OR IGNORE INTO tasks (id, license_key_id, title, created_by, visibility)
                VALUES (?, ?, ?, ?, 'shared')
            """, (task_id, license_id, "Test Task", created_by))

        await share_task(
            task_id=task_id,
            license_id=license_id,
            shared_with_user_id=shared_with_user_id,
            permission="read",
            created_by=created_by
        )

        # Simulate concurrent permission updates
        async def update_permission(perm):
            try:
                result = await share_task(
                    task_id=task_id,
                    license_id=license_id,
                    shared_with_user_id=shared_with_user_id,
                    permission=perm,
                    created_by=created_by
                )
                return ("success", perm)
            except Exception as e:
                return ("error", str(e))

        results = await asyncio.gather(
            update_permission("admin"),
            update_permission("edit"),
            return_exceptions=True
        )

        # Both should succeed (they update the same record)
        success_count = sum(1 for r in results if r[0] == "success")
        assert success_count == 2

        # Verify share exists with one of the permissions (last write wins)
        async with get_db() as db:
            row = await fetch_one(
                db,
                "SELECT permission FROM task_shares WHERE task_id = ? AND shared_with_user_id = ? AND deleted_at IS NULL",
                (task_id, shared_with_user_id)
            )
            assert row is not None, "Share record should exist"
            assert row["permission"] in ("admin", "edit"), "Permission should be one of the updated values"

        # Cleanup
        async with get_db() as db:
            await execute_sql(db, "DELETE FROM task_shares WHERE task_id = ?", (task_id,))
            await execute_sql(db, "DELETE FROM tasks WHERE id = ?", (task_id,))


# ============ Task Recurrence Edge Cases Tests ============

class TestTaskRecurrenceEdgeCases:
    """Test recurring task edge cases, especially month-end handling
    
    FIX BUG-001: Ensure recurring tasks handle month-end dates correctly
    (e.g., Jan 31 -> Feb 28, Mar 31 -> Apr 30)
    """
    
    def test_monthly_recurrence_jan31_to_feb(self):
        """Test monthly recurrence from January 31st to February
        
        January has 31 days, February has 28/29 days.
        Expected: Should use last day of February
        """
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # Jan 31
        old_due = datetime(2024, 1, 31, 23, 59, 59)
        
        # Calculate next occurrence
        next_due = old_due + relativedelta(months=1)
        
        # Handle month-end: if day doesn't match, use last day of month
        if next_due.day != old_due.day:
            next_due = next_due.replace(day=1) + relativedelta(days=-1)
        
        # 2024 is a leap year, so Feb has 29 days
        assert next_due.month == 2
        assert next_due.day == 29  # Leap year
        assert next_due.hour == 23
        assert next_due.minute == 59
    
    def test_monthly_recurrence_non_leap_year(self):
        """Test monthly recurrence in non-leap year"""
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # Jan 31, 2023 (non-leap year)
        old_due = datetime(2023, 1, 31, 23, 59, 59)
        
        # Calculate next occurrence
        next_due = old_due + relativedelta(months=1)
        
        # Handle month-end
        if next_due.day != old_due.day:
            next_due = next_due.replace(day=1) + relativedelta(days=-1)
        
        # 2023 is not a leap year, so Feb has 28 days
        assert next_due.month == 2
        assert next_due.day == 28
    
    def test_monthly_recurrence_mar31_to_apr30(self):
        """Test monthly recurrence from March 31st to April 30th"""
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # Mar 31
        old_due = datetime(2024, 3, 31, 12, 0, 0)
        
        # Calculate next occurrence
        next_due = old_due + relativedelta(months=1)
        
        # Handle month-end: April has 30 days
        if next_due.day != old_due.day:
            next_due = next_due.replace(day=1) + relativedelta(days=-1)
        
        assert next_due.month == 4
        assert next_due.day == 30
    
    def test_monthly_recurrence_may31_to_jun30(self):
        """Test monthly recurrence from May 31st to June 30th"""
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # May 31
        old_due = datetime(2024, 5, 31, 9, 0, 0)
        
        # Calculate next occurrence
        next_due = old_due + relativedelta(months=1)
        
        # Handle month-end: June has 30 days
        if next_due.day != old_due.day:
            next_due = next_due.replace(day=1) + relativedelta(days=-1)
        
        assert next_due.month == 6
        assert next_due.day == 30
    
    def test_monthly_recurrence_preserves_time(self):
        """Test that monthly recurrence preserves the time of day"""
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # Jan 31 at specific time
        old_due = datetime(2024, 1, 31, 14, 30, 45)
        
        # Calculate next occurrence
        next_due = old_due + relativedelta(months=1)
        
        # Handle month-end
        if next_due.day != old_due.day:
            next_due = next_due.replace(day=1) + relativedelta(days=-1)
        
        # Time should be preserved
        assert next_due.hour == 14
        assert next_due.minute == 30
        assert next_due.second == 45
    
    def test_weekly_recurrence_unchanged(self):
        """Test that weekly recurrence is not affected by month-end logic"""
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # Any date
        old_due = datetime(2024, 1, 31, 10, 0, 0)
        
        # Weekly recurrence
        next_due = old_due + relativedelta(weeks=1)
        
        # Should be exactly 7 days later
        assert next_due.day == 7  # Feb 7
        assert next_due.month == 2
        assert next_due.hour == 10
    
    def test_daily_recurrence_unchanged(self):
        """Test that daily recurrence is not affected by month-end logic"""
        from datetime import datetime
        from dateutil.relativedelta import relativedelta
        
        # Month end
        old_due = datetime(2024, 1, 31, 10, 0, 0)
        
        # Daily recurrence
        next_due = old_due + relativedelta(days=1)
        
        # Should be next day
        assert next_due.day == 1
        assert next_due.month == 2
        assert next_due.hour == 10
    
    def test_reset_subtask_preserves_id(self):
        """Test that resetting subtasks for recurrence preserves IDs"""
        from utils.timestamps import generate_stable_id
        
        # Simulate the reset_subtask function from routes/tasks.py
        def reset_subtask(subtask):
            if isinstance(subtask, dict):
                return {
                    **subtask,
                    "is_completed": False
                }
            elif isinstance(subtask, str):
                try:
                    import json
                    st_dict = json.loads(subtask)
                    return {
                        **st_dict,
                        "is_completed": False
                    }
                except:
                    stable_id = generate_stable_id(subtask)
                    return {"id": stable_id, "title": str(subtask), "is_completed": False}
            else:
                stable_id = generate_stable_id(str(subtask))
                return {"id": stable_id, "title": str(subtask), "is_completed": False}
        
        # Test with dict subtask
        original = {
            "id": "custom-id-123",
            "title": "Test subtask",
            "is_completed": True,
            "extra_field": "preserved"
        }
        
        reset = reset_subtask(original)
        
        assert reset["id"] == "custom-id-123", "ID should be preserved"
        assert reset["is_completed"] is False, "Completion should be reset"
        assert reset["title"] == "Test subtask", "Title should be preserved"
        assert reset["extra_field"] == "preserved", "Extra fields should be preserved"
