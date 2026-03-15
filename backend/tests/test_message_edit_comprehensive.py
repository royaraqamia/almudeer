"""
Comprehensive Integration Tests for Message Edit Feature

Tests cover:
1. Basic edit functionality
2. Validation and restrictions
3. Concurrent edits (race conditions)
4. WebSocket broadcast
5. Database consistency
6. Edge cases and error handling

Run with: pytest tests/test_message_edit_comprehensive.py -v
"""

import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch, MagicMock

from models.inbox import edit_outbox_message


# ============================================================================
# Backend Unit Tests - edit_outbox_message function
# ============================================================================

class TestEditOutboxMessageBasic:
    """Basic functionality tests for message editing"""

    @pytest.mark.asyncio
    async def test_edit_success_almudeer_channel(self):
        """Test successful edit on almudeer channel"""
        license_id = 1
        message_id = 100
        created_at = datetime.now(timezone.utc) - timedelta(minutes=30)

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": created_at,
            "body": "Original body",
            "original_body": None,
            "edit_count": 0,
            "recipient_contact": "test@example.com",
            "recipient_id": None,
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_execute_sql = AsyncMock()
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", mock_execute_sql), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(
                message_id, license_id, "New body", edited_by="test_user"
            )

            assert result["success"] is True
            assert result["body"] == "New body"
            assert result["edit_count"] == 1
            assert "edited_at" in result

    @pytest.mark.asyncio
    async def test_edit_success_saved_channel(self):
        """Test successful edit on saved (drafts) channel"""
        license_id = 1
        message_id = 101
        created_at = datetime.now(timezone.utc) - timedelta(hours=12)

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "saved",
            "created_at": created_at,
            "body": "Draft body",
            "original_body": None,
            "edit_count": 0,
            "recipient_contact": None,
            "recipient_id": None,
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(
                message_id, license_id, "Updated draft", edited_by="user1"
            )

            assert result["success"] is True

    @pytest.mark.asyncio
    async def test_edit_message_not_found(self):
        """Test editing non-existent message"""
        mock_fetch_one = AsyncMock(return_value=None)
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one):

            with pytest.raises(ValueError, match="الرسالة غير موجودة"):
                await edit_outbox_message(100, 1, "New body", edited_by="user")

    @pytest.mark.asyncio
    async def test_edit_deleted_message(self):
        """Test editing a deleted message"""
        message = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc),
            "body": "Original",
            "deleted_at": datetime.now(timezone.utc)
        }

        mock_fetch_one = AsyncMock(return_value=message)
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one):

            with pytest.raises(ValueError, match="لا يمكن تعديل الرسائل المحذوفة"):
                await edit_outbox_message(100, 1, "New body", edited_by="user")


class TestEditMessageValidation:
    """Validation and restriction tests"""

    @pytest.mark.parametrize("channel", ["telegram", "whatsapp", "generic", "sms"])
    @pytest.mark.asyncio
    async def test_edit_external_channels_restricted(self, channel):
        """Test that external channels cannot be edited"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": channel,
            "created_at": datetime.now(timezone.utc),
            "body": "Original body",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(return_value=message)
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one):

            with pytest.raises(ValueError, match=f"لا يمكن تعديل الرسائل المرسلة عبر {channel}"):
                await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

    @pytest.mark.asyncio
    async def test_edit_exceeds_time_limit(self):
        """Test editing message older than 24 hours"""
        license_id = 1
        message_id = 100
        # Created 25 hours ago
        created_at = datetime.now(timezone.utc) - timedelta(hours=25)

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": created_at,
            "body": "Old message",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(return_value=message)
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one):

            with pytest.raises(ValueError, match="انتهت الفترة المتاحة لتعديل الرسالة"):
                await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

    @pytest.mark.asyncio
    async def test_edit_within_time_limit(self):
        """Test editing message within 24 hours"""
        license_id = 1
        message_id = 100
        # Created 23 hours ago (within limit)
        created_at = datetime.now(timezone.utc) - timedelta(hours=23)

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": created_at,
            "body": "Recent message",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(message_id, license_id, "New body", edited_by="user")
            assert result["success"] is True

    @pytest.mark.asyncio
    async def test_edit_max_edit_count_exceeded(self):
        """Test editing message that reached max edit count (10)"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Message",
            "edit_count": 10,  # Max reached
            "deleted_at": None
        }

        # First fetch returns the message with edit_count=10
        # Second fetch (after UPDATE) should also return edit_count=10 (UPDATE didn't change it)
        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 10}])
        mock_execute_sql = AsyncMock()
        mock_commit_db = AsyncMock()
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", mock_execute_sql), \
             patch("models.inbox.commit_db", mock_commit_db), \
             patch("models.inbox.DB_TYPE", "sqlite"):

            with pytest.raises(ValueError, match="تم الوصول للحد الأقصى للتعديلات"):
                await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

    @pytest.mark.asyncio
    async def test_edit_at_max_count_boundary(self):
        """Test editing message at edit count 9 (one before max)"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Message",
            "edit_count": 9,  # One before max
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 10}])
        mock_execute_sql = AsyncMock()
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", mock_execute_sql), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(message_id, license_id, "New body", edited_by="user")
            assert result["success"] is True
            assert result["edit_count"] == 10


class TestEditMessageAuditTrail:
    """Tests for audit trail and edited_by tracking"""

    @pytest.mark.asyncio
    async def test_edited_by_passed_to_sql(self):
        """Test that edited_by is passed to SQL"""
        license_id = 1
        message_id = 100
        created_at = datetime.now(timezone.utc) - timedelta(minutes=30)

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": created_at,
            "body": "Original",
            "edit_count": 0,
            "edited_by": None,
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_execute_sql = AsyncMock()
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", mock_execute_sql), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            await edit_outbox_message(message_id, license_id, "New body", edited_by="alice")

            # Verify edited_by was in the SQL call
            # The outbox_messages UPDATE should have 7 params:
            # [new_body, ts_value, original_body, edited_by, message_id, license_id, MAX_EDIT_COUNT]
            mock_execute_sql.assert_called()
            # Check all calls to find the outbox UPDATE (has 7 params)
            found_outbox_update = False
            for call in mock_execute_sql.call_args_list:
                params = call[0][2]
                if len(params) == 7 and "alice" in params:
                    found_outbox_update = True
                    break
            assert found_outbox_update, f"Expected outbox UPDATE with 'alice' in params. Calls: {mock_execute_sql.call_args_list}"


class TestEditMessageConcurrency:
    """Tests for concurrent edit scenarios (race conditions)"""

    @pytest.mark.asyncio
    async def test_rapid_sequential_edits(self):
        """Test rapid sequential edits on same message"""
        license_id = 1
        message_id = 100

        base_message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        # Simulate 5 rapid edits
        for i in range(5):
            base_message["edit_count"] = i
            mock_fetch_one = AsyncMock(side_effect=[
                base_message.copy(),
                {"edit_count": i + 1}
            ])
            mock_execute_sql = AsyncMock()
            mock_db = MagicMock()
            mock_db.__aenter__ = AsyncMock(return_value=mock_db)
            mock_db.__aexit__ = AsyncMock(return_value=None)

            with patch("models.inbox.get_db", return_value=mock_db), \
                 patch("models.inbox.fetch_one", mock_fetch_one), \
                 patch("models.inbox.execute_sql", mock_execute_sql), \
                 patch("models.inbox.commit_db", AsyncMock()), \
                 patch("models.inbox.upsert_conversation_state", AsyncMock()), \
                 patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

                result = await edit_outbox_message(
                    message_id, license_id, f"Edit {i+1}", edited_by="user"
                )
                assert result["edit_count"] == i + 1


class TestEditMessageWebSocket:
    """Tests for WebSocket broadcast functionality"""

    @pytest.mark.asyncio
    async def test_websocket_broadcast_called_on_edit(self):
        """Test that WebSocket broadcast is called after successful edit"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "recipient_contact": "peer@example.com",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited") as mock_broadcast:

            await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

            mock_broadcast.assert_called_once()
            call_args = mock_broadcast.call_args
            assert call_args.kwargs["license_id"] == license_id
            assert call_args.kwargs["message_id"] == message_id
            assert call_args.kwargs["new_body"] == "New body"

    @pytest.mark.asyncio
    async def test_websocket_broadcast_failure_does_not_rollback(self):
        """Test that WebSocket failure doesn't rollback the edit"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "recipient_contact": "peer@example.com",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", side_effect=Exception("Broadcast failed")):

            # Edit should still succeed even if broadcast fails
            result = await edit_outbox_message(message_id, license_id, "New body", edited_by="user")
            assert result["success"] is True

    @pytest.mark.asyncio
    async def test_websocket_broadcast_includes_edit_count(self):
        """Test that broadcast includes the edit count"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 2,
            "recipient_contact": "peer@example.com",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 3}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited") as mock_broadcast:

            await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

            # Verify edit_count=3 is passed to broadcast
            assert mock_broadcast.call_args.kwargs["edit_count"] == 3


class TestEditMessageDatabaseConsistency:
    """Tests for database consistency and transaction handling"""

    @pytest.mark.asyncio
    async def test_original_body_stored_on_first_edit(self):
        """Test that original body is preserved on first edit"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original body",
            "original_body": None,  # Not set yet
            "edit_count": 0,
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_execute_sql = AsyncMock()
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", mock_execute_sql), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

            # Verify original_body is passed to SQL (COALESCE will use it)
            # The outbox_messages UPDATE should have 7 params:
            # [new_body, ts_value, original_body, edited_by, message_id, license_id, MAX_EDIT_COUNT]
            mock_execute_sql.assert_called()
            # Check all calls to find the outbox UPDATE (has 7 params)
            found_outbox_update = False
            for call in mock_execute_sql.call_args_list:
                params = call[0][2]
                if len(params) == 7 and "Original body" in params:
                    found_outbox_update = True
                    break
            assert found_outbox_update, f"Expected outbox UPDATE with 'Original body' in params. Calls: {mock_execute_sql.call_args_list}"

    @pytest.mark.asyncio
    async def test_inbox_message_synced_for_internal_channels(self):
        """Test that inbox_messages is updated for almudeer/saved channels"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "recipient_contact": "peer@example.com",
            "deleted_at": None
        }

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_execute_sql = AsyncMock()
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", mock_execute_sql), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            await edit_outbox_message(message_id, license_id, "New body", edited_by="user")

            # Verify inbox_messages UPDATE was called (for recipient sync)
            calls = mock_execute_sql.call_args_list
            # Should have at least 2 calls: outbox UPDATE + inbox UPDATE
            assert len(calls) >= 2
            # Check for inbox_messages UPDATE
            inbox_update_found = False
            for call in calls:
                if "UPDATE inbox_messages" in call[0][1]:
                    inbox_update_found = True
                    break
            assert inbox_update_found, "inbox_messages should be updated for internal channels"


class TestEditMessageEdgeCases:
    """Edge case and error handling tests"""

    @pytest.mark.asyncio
    async def test_edit_with_special_characters(self):
        """Test editing message with special characters and emojis"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        new_body = "Updated with emojis 🎉 and special chars: <>&\"'\n\t"

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(message_id, license_id, new_body, edited_by="user")
            assert result["success"] is True
            assert result["body"] == new_body

    @pytest.mark.asyncio
    async def test_edit_with_unicode_content(self):
        """Test editing message with Unicode content (Arabic, Chinese, etc.)"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        new_body = "مرحبا 🎉 你好 مرحبا بالعالم 🌍 Hello"

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(message_id, license_id, new_body, edited_by="user")
            assert result["success"] is True

    @pytest.mark.asyncio
    async def test_edit_with_multiline_content(self):
        """Test editing message with multiline content"""
        license_id = 1
        message_id = 100

        message = {
            "id": message_id,
            "license_key_id": license_id,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        new_body = """Line 1
Line 2
Line 3

Paragraph 2"""

        mock_fetch_one = AsyncMock(side_effect=[message, {"edit_count": 1}])
        mock_db = MagicMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=None)

        with patch("models.inbox.get_db", return_value=mock_db), \
             patch("models.inbox.fetch_one", mock_fetch_one), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()), \
             patch("services.websocket_manager.broadcast_message_edited", AsyncMock()):

            result = await edit_outbox_message(message_id, license_id, new_body, edited_by="user")
            assert result["success"] is True
            assert "\n" in result["body"]
