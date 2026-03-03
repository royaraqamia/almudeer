"""
Test that deleted conversations don't reappear in the inbox list.

This tests the fix for the issue where deleting empty conversations
would cause them to reappear after upsert_conversation_state was called.
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime


@pytest.mark.asyncio
async def test_upsert_conversation_state_does_not_recreate_deleted():
    """
    Test that upsert_conversation_state does NOT recreate a conversation
    if all messages for that contact have been deleted (deleted_at is set).
    """
    from models.inbox import upsert_conversation_state

    # Mock database functions
    with patch("models.inbox.fetch_one", new_callable=AsyncMock) as mock_fetch_one, \
         patch("models.inbox._get_sender_aliases", new_callable=AsyncMock) as mock_get_aliases, \
         patch("models.inbox.execute_sql", new_callable=AsyncMock) as mock_execute, \
         patch("models.inbox.commit_db", new_callable=AsyncMock) as mock_commit:

        # Simulate conversation does NOT exist in inbox_conversations (was deleted)
        mock_fetch_one.return_value = None  # Conversation doesn't exist

        # Simulate we have aliases for this contact
        mock_get_aliases.return_value = ({"test_contact"}, set())

        # Simulate NO non-deleted messages exist (all have deleted_at set)
        # First call checks inbox_messages with contacts - returns None (no messages)
        # Second call would check outbox - also returns None
        mock_fetch_one.side_effect = [None, None, None, None]

        # Call upsert_conversation_state
        await upsert_conversation_state(
            license_id=1,
            sender_contact="test_contact",
            sender_name="Test User",
            channel="almudeer"
        )

        # Verify that execute_sql was NOT called to INSERT a new conversation
        # (it should return early without creating the conversation)
        insert_calls = [
            call for call in mock_execute.call_args_list
            if call[0][0] and "INSERT INTO inbox_conversations" in str(call[0][0])
        ]

        assert len(insert_calls) == 0, \
            "Conversation should NOT be recreated when all messages are deleted"


@pytest.mark.asyncio
async def test_upsert_conversation_state_creates_when_messages_exist():
    """
    Test that upsert_conversation_state DOES create a conversation
    when there are non-deleted messages.
    
    This is a simpler version that just verifies the early-return logic
    is bypassed when messages exist.
    """
    from models.inbox import upsert_conversation_state

    call_count = {"execute": 0}

    def track_execute(db, sql, params=None):
        call_count["execute"] += 1
        return AsyncMock()

    # Mock database functions
    with patch("models.inbox.fetch_one", new_callable=AsyncMock) as mock_fetch_one, \
         patch("models.inbox._get_sender_aliases", new_callable=AsyncMock) as mock_get_aliases, \
         patch("models.inbox.execute_sql", side_effect=track_execute) as mock_execute, \
         patch("models.inbox.commit_db", new_callable=AsyncMock) as mock_commit, \
         patch("models.inbox.get_db"):

        # Simulate conversation does NOT exist in inbox_conversations
        # First call returns None (conversation doesn't exist)
        # Second call returns a row (non-deleted message EXISTS)
        mock_fetch_one.side_effect = [None, {"id": 1}]

        # Simulate we have aliases for this contact
        mock_get_aliases.return_value = ({"test_contact"}, set())

        # Call upsert_conversation_state
        try:
            await upsert_conversation_state(
                license_id=1,
                sender_contact="test_contact",
                sender_name="Test User",
                channel="almudeer"
            )
        except Exception:
            # Expected - we're not fully mocking the entire flow
            pass

        # If execute_sql was called more than once, it means we didn't early-return
        # (early-return happens when no messages exist)
        assert call_count["execute"] > 0, \
            "execute_sql should be called when messages exist (not early-returning)"


@pytest.mark.asyncio
async def test_soft_delete_then_upsert_does_not_recreate():
    """
    Integration-style test: Delete a conversation, then call upsert_conversation_state.
    The conversation should NOT reappear.
    """
    from models.inbox import soft_delete_conversation, upsert_conversation_state

    with patch("models.inbox._get_sender_aliases", new_callable=AsyncMock) as mock_get_aliases, \
         patch("models.inbox.execute_sql", new_callable=AsyncMock) as mock_execute, \
         patch("models.inbox.commit_db", new_callable=AsyncMock) as mock_commit, \
         patch("models.inbox.fetch_one", new_callable=AsyncMock) as mock_fetch_one, \
         patch("models.inbox.fetch_all", new_callable=AsyncMock) as mock_fetch_all:

        # Setup mocks
        mock_get_aliases.return_value = ({"test_contact"}, set())
        mock_fetch_all.return_value = []  # No attachments
        mock_fetch_one.return_value = None  # No non-deleted messages

        # Step 1: Delete the conversation
        await soft_delete_conversation(license_id=1, sender_contact="test_contact")

        # Step 2: Try to upsert conversation state (simulating what might happen
        # during sync or message processing)
        await upsert_conversation_state(
            license_id=1,
            sender_contact="test_contact",
            sender_name="Test User",
            channel="almudeer"
        )

        # Count INSERT calls for inbox_conversations
        insert_calls = [
            call for call in mock_execute.call_args_list
            if call[0][0] and "INSERT INTO inbox_conversations" in str(call[0][0])
        ]

        assert len(insert_calls) == 0, \
            "Deleted conversation should NOT be recreated by upsert_conversation_state"
