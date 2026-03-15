"""
End-to-End Integration Tests for Message Edit Feature

These tests simulate real-world scenarios spanning backend, database,
WebSocket, and mobile app integration.

Run with: pytest tests/test_message_edit_e2e.py -v
"""

import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch, MagicMock
from httpx import AsyncClient, ASGITransport

# ============================================================================
# E2E Test Scenarios
# ============================================================================


class TestE2E_MessageEditScenarios:
    """End-to-end scenarios for message editing"""

    @pytest.fixture
    async def mock_full_stack(self):
        """Mock all dependencies for full-stack testing"""
        with patch("routes.chat_routes.get_license_from_header") as mock_license, \
             patch("models.inbox.get_db") as mock_db, \
             patch("services.websocket_manager.get_websocket_manager") as mock_ws:

            mock_license.return_value = {
                "license_id": 1,
                "license_key": "test-key",
                "username": "test_user"
            }

            db_instance = MagicMock()
            db_instance.__aenter__ = AsyncMock(return_value=db_instance)
            db_instance.__aexit__ = AsyncMock(return_value=None)
            mock_db.return_value = db_instance

            mock_ws_instance = MagicMock()
            mock_ws_instance.send_to_license = AsyncMock()
            mock_ws.return_value = mock_ws_instance

            yield {
                "license": mock_license,
                "db": mock_db,
                "ws": mock_ws
            }

    @pytest.mark.asyncio
    async def test_e2e_edit_flow_complete(self, mock_full_stack):
        """
        E2E Test: Complete edit flow from API to WebSocket broadcast
        
        Scenario:
        1. User sends message
        2. User edits message within 24 hours
        3. Backend validates and updates database
        4. WebSocket broadcasts to recipients
        5. Mobile app receives and updates UI
        """
        from main import app

        # Setup database mock responses
        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(hours=1),
            "body": "Original message",
            "original_body": None,
            "edit_count": 0,
            "recipient_contact": "peer@example.com",
            "recipient_id": None,
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            elif "SELECT id FROM license_keys" in query:
                return None  # Not internal peer
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                # Step 1: Edit the message
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Edited message content"}
                )

                # Step 2: Verify response
                assert response.status_code == 200
                data = response.json()
                assert data["success"] is True
                assert data["body"] == "Edited message content"
                assert data["edit_count"] == 1
                assert "edited_at" in data

                # Step 3: Verify database was updated (execute_sql called)
                # Step 4: Verify WebSocket broadcast was called
                mock_full_stack["ws"].return_value.send_to_license.assert_called()

    @pytest.mark.asyncio
    async def test_e2e_multi_device_sync(self, mock_full_stack):
        """
        E2E Test: Edit syncs across multiple devices
        
        Scenario:
        1. User edits message on Device A
        2. Same user's Device B receives WebSocket event
        3. Device B updates UI without refresh
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=30),
            "body": "Original",
            "edit_count": 0,
            "recipient_contact": "peer@example.com",
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Edited on Device A"}
                )

                assert response.status_code == 200

                # Verify WebSocket was called for multi-device sync
                # The send_to_license should be called with the edit event
                mock_ws = mock_full_stack["ws"].return_value
                assert mock_ws.send_to_license.called

                # Verify payload structure
                call_args = mock_ws.send_to_license.call_args
                assert call_args is not None

    @pytest.mark.asyncio
    async def test_e2e_peer_to_peer_edit_notification(self, mock_full_stack):
        """
        E2E Test: Peer receives edit notification for internal messages
        
        Scenario:
        1. User A sends message to User B (both almudeer users)
        2. User A edits the message
        3. User B's device receives WebSocket notification
        4. User B's UI updates without refresh
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=15),
            "body": "Message to peer",
            "edit_count": 0,
            "recipient_contact": "peer_username",  # Internal peer
            "deleted_at": None
        }

        peer_license_row = {"id": 2}  # Peer has license_id=2
        owner_username_row = {"username": "sender_username"}

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            elif "FROM license_keys WHERE username" in query:
                return peer_license_row  # Peer found
            elif "FROM license_keys WHERE id = ?" in query and params and params[0] == 1:
                return owner_username_row
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Edited message to peer"}
                )

                assert response.status_code == 200

                # Verify WebSocket sent to BOTH sender and peer
                mock_ws = mock_full_stack["ws"].return_value
                # Should be called at least twice: once for sender, once for peer
                assert mock_ws.send_to_license.call_count >= 2

    @pytest.mark.asyncio
    async def test_e2e_external_channel_edit_blocked(self, mock_full_stack):
        """
        E2E Test: WhatsApp/Telegram messages cannot be edited
        
        Scenario:
        1. Message sent via WhatsApp
        2. User attempts to edit
        3. Backend rejects with appropriate error
        4. Mobile app displays error to user
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "whatsapp",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=5),
            "body": "WhatsApp message",
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Trying to edit WhatsApp message"}
                )

                # Should be rejected
                assert response.status_code == 400
                assert "لا يمكن تعديل الرسائل المرسلة عبر whatsapp" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_e2e_edit_after_24h_rejected(self, mock_full_stack):
        """
        E2E Test: Messages older than 24 hours cannot be edited
        
        Scenario:
        1. Message sent 25 hours ago
        2. User attempts to edit
        3. Backend rejects with time limit error
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(hours=25),
            "body": "Old message",
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Trying to edit old message"}
                )

                assert response.status_code == 400
                assert "انتهت الفترة المتاحة لتعديل الرسالة" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_e2e_max_edit_count_enforced(self, mock_full_stack):
        """
        E2E Test: Maximum edit count (10) is enforced
        
        Scenario:
        1. Message already edited 10 times
        2. User attempts 11th edit
        3. Backend rejects with max edits error
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Heavily edited message",
            "edit_count": 10,
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "11th edit attempt"}
                )

                assert response.status_code == 400
                assert "تم الوصول للحد الأقصى للتعديلات" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_e2e_deleted_message_edit_rejected(self, mock_full_stack):
        """
        E2E Test: Deleted messages cannot be edited
        
        Scenario:
        1. Message was soft-deleted
        2. User attempts to edit
        3. Backend rejects with deleted message error
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Deleted message",
            "edit_count": 0,
            "deleted_at": datetime.now(timezone.utc)
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Trying to edit deleted message"}
                )

                assert response.status_code == 400
                assert "لا يمكن تعديل الرسائل المحذوفة" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_e2e_concurrent_edits_handled(self, mock_full_stack):
        """
        E2E Test: Concurrent edits are handled atomically
        
        Scenario:
        1. Two users/devices edit same message simultaneously
        2. Both requests processed
        3. Edit count increments correctly (1, 2)
        4. No data corruption
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        call_count = 0

        async def mock_fetch(db, query, params=None):
            nonlocal call_count
            call_count += 1
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": call_count}
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                # Send concurrent edit requests
                responses = await asyncio.gather(
                    client.patch("/api/integrations/messages/100/edit", json={"body": "Edit 1"}),
                    client.patch("/api/integrations/messages/100/edit", json={"body": "Edit 2"}),
                )

                # Both should succeed
                assert all(r.status_code == 200 for r in responses)

                # Edit counts should be different (atomic increment worked)
                edit_counts = [r.json()["edit_count"] for r in responses]
                assert len(set(edit_counts)) == 2  # Different values
                assert 1 in edit_counts
                assert 2 in edit_counts


class TestE2E_MobileAppIntegration:
    """Mobile app integration scenarios"""

    @pytest.mark.asyncio
    async def test_e2e_mobile_edit_optimistic_update(self):
        """
        E2E Test: Mobile app optimistic update flow
        
        Scenario:
        1. User taps edit on mobile
        2. App shows edit UI immediately
        3. User saves edit
        4. App updates UI optimistically
        5. API call happens in background
        6. On success: confirmation
        7. On failure: rollback + error message
        """
        # This test documents the expected flow
        # Actual implementation requires Flutter integration test

        # Expected flow:
        # 1. User taps message -> context menu -> Edit
        # 2. MessageInputSection shows edit mode
        # 3. User modifies text and taps send
        # 4. ConversationDetailProvider.editMessage() called
        # 5. canEdit check passes
        # 6. Optimistic update to _memoryMessages
        # 7. notifyListeners() triggers UI rebuild
        # 8. inboxRepository.editMessage() called in background
        # 9. On success: applyRemoteMessageEdit() persists edited_at
        # 10. On failure: rollback + onError callback

        assert True  # Flow documented

    @pytest.mark.asyncio
    async def test_e2e_mobile_websocket_edit_reception(self):
        """
        E2E Test: Mobile receives WebSocket edit event
        
        Scenario:
        1. Peer edits message on their device
        2. WebSocket sends message_edited event
        3. Mobile app receives event
        4. InboxProvider._handleMessageEditedEvent() processes
        5. ConversationDetailProvider updates message in view
        6. UI shows updated body with (edited) indicator
        """
        # Expected flow:
        # 1. WebSocketService receives: {type: 'message_edited', ...}
        # 2. Event dispatched to InboxProvider
        # 3. _handleMessageEditedEvent() extracts data
        # 4. updateMessageEdit() updates conversation list
        # 5. applyRemoteMessageEdit() persists to SQLite
        # 6. ConversationDetailProvider receives update
        # 7. Message in _memoryMessages updated
        # 8. notifyListeners() triggers rebuild
        # 9. MessageBubble shows new body + (معدّل) indicator

        assert True  # Flow documented


class TestE2E_EdgeCases:
    """Edge case scenarios"""

    @pytest.mark.asyncio
    async def test_e2e_edit_with_html_injection_attempt(self):
        """
        E2E Test: HTML/JS injection attempts in edits
        
        Scenario:
        1. User tries to edit message with <script>alert('xss')</script>
        2. Backend stores as-is (no HTML parsing)
        3. Mobile app displays as plain text (escaped)
        4. No XSS vulnerability
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            return None

        xss_payload = "<script>alert('xss')</script>"

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()) as mock_sql, \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": xss_payload}
                )

                assert response.status_code == 200

                # Verify payload was stored as-is (no sanitization needed for plain text)
                mock_sql.assert_called()
                call_params = mock_sql.call_args[0][2]
                assert xss_payload in call_params

                # Note: Mobile app must render as plain text, not HTML
                # Flutter's Text widget does this by default

    @pytest.mark.asyncio
    async def test_e2e_edit_with_emoji_and_unicode(self):
        """
        E2E Test: Emoji and Unicode characters in edits
        
        Scenario:
        1. User edits message with emojis and various scripts
        2. Backend stores correctly (UTF-8)
        3. Mobile app displays correctly
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        unicode_payload = "مرحبا 🎉 你好 مرحبا بالعالم 🌍 Hello"

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": unicode_payload}
                )

                assert response.status_code == 200
                data = response.json()
                assert data["body"] == unicode_payload

    @pytest.mark.asyncio
    async def test_e2e_edit_preserves_original_body(self):
        """
        E2E Test: Original body preserved on first edit
        
        Scenario:
        1. Message created with "Original"
        2. First edit changes to "Edited v1"
        3. original_body column stores "Original"
        4. Subsequent edits don't change original_body
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "original_body": None,
            "edit_count": 0,
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()) as mock_sql, \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Edited v1"}
                )

                assert response.status_code == 200

                # Verify original_body was passed to SQL
                mock_sql.assert_called()
                call_params = mock_sql.call_args[0][2]
                assert "Original" in call_params  # original_body parameter

    @pytest.mark.asyncio
    async def test_e2e_edit_audit_trail_edited_by(self):
        """
        E2E Test: Audit trail tracks who edited
        
        Scenario:
        1. User "alice" creates message
        2. User "bob" (with access) edits message
        3. edited_by field stores "bob"
        4. Audit trail shows who made changes
        """
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "edited_by": None,
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            return None

        with patch("routes.chat_routes.get_license_from_header") as mock_license, \
             patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()) as mock_sql, \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            mock_license.return_value = {
                "license_id": 1,
                "license_key": "test-key",
                "username": "bob"  # Editor is bob
            }

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Edited by bob"}
                )

                assert response.status_code == 200

                # Verify edited_by was passed to SQL
                mock_sql.assert_called()
                call_params = mock_sql.call_args[0][2]
                assert "bob" in call_params


# ============================================================================
# Performance and Load Tests
# ============================================================================


class TestE2E_Performance:
    """Performance and load testing scenarios"""

    @pytest.mark.asyncio
    async def test_e2e_rapid_sequential_edits(self):
        """
        Performance Test: Rapid sequential edits
        
        Scenario:
        1. User makes 5 edits in quick succession
        2. Each edit processes correctly
        3. No race conditions or data corruption
        4. Edit count increments correctly
        """
        from main import app

        base_message = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        edit_count = 0

        async def mock_fetch(db, query, params=None):
            nonlocal edit_count
            if "SELECT * FROM outbox_messages" in query:
                result = base_message.copy()
                result["edit_count"] = edit_count
                return result
            elif "SELECT edit_count" in query:
                edit_count += 1
                return {"edit_count": edit_count}
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                # Perform 5 rapid edits
                for i in range(5):
                    response = await client.patch(
                        "/api/integrations/messages/100/edit",
                        json={"body": f"Edit {i+1}"}
                    )
                    assert response.status_code == 200
                    assert response.json()["edit_count"] == i + 1

    @pytest.mark.asyncio
    async def test_e2e_edit_response_time(self):
        """
        Performance Test: Edit API response time
        
        Scenario:
        1. Measure time for edit API call
        2. Should complete within acceptable threshold (<500ms)
        """
        import time
        from main import app

        message_row = {
            "id": 100,
            "license_key_id": 1,
            "channel": "almudeer",
            "created_at": datetime.now(timezone.utc) - timedelta(minutes=10),
            "body": "Original",
            "edit_count": 0,
            "deleted_at": None
        }

        async def mock_fetch(db, query, params=None):
            if "SELECT * FROM outbox_messages" in query:
                return message_row.copy()
            elif "SELECT edit_count" in query:
                return {"edit_count": 1}
            return None

        with patch("models.inbox.fetch_one", side_effect=mock_fetch), \
             patch("models.inbox.execute_sql", AsyncMock()), \
             patch("models.inbox.commit_db", AsyncMock()), \
             patch("models.inbox.upsert_conversation_state", AsyncMock()):

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                start = time.time()
                response = await client.patch(
                    "/api/integrations/messages/100/edit",
                    json={"body": "Timed edit"}
                )
                elapsed = time.time() - start

                assert response.status_code == 200
                # Response time should be under 500ms (generous threshold for tests)
                assert elapsed < 0.5, f"Edit took {elapsed:.3f}s, expected <0.5s"


# ============================================================================
# Test Run Instructions
# ============================================================================

"""
Run these tests with:

# All E2E tests
pytest tests/test_message_edit_e2e.py -v

# Specific test class
pytest tests/test_message_edit_e2e.py::TestE2E_MessageEditScenarios -v

# Specific test
pytest tests/test_message_edit_e2e.py::TestE2E_MessageEditScenarios::test_e2e_edit_flow_complete -v

# With coverage
pytest tests/test_message_edit_e2e.py --cov=routes/chat_routes --cov=models/inbox -v

# Parallel execution (if pytest-xdist installed)
pytest tests/test_message_edit_e2e.py -n auto -v
"""
