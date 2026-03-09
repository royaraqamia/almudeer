"""
Tests for Historical Chat Backfill System
"""

import pytest
import asyncio
from datetime import datetime, timedelta
from typing import List, Dict, Any
from unittest.mock import MagicMock, patch

from services.backfill_service import HistoricalBackfillService
from models.backfill_queue import (
    add_to_backfill_queue,
    get_next_pending_reveal,
    mark_as_revealed,
    get_backfill_queue_count,
    BACKFILL_REVEAL_INTERVAL_SECONDS
)

# Mock DB helper to avoid actual DB calls during unit testing
# In a real environment, we would use a test database fixture
@pytest.mark.asyncio
async def test_schedule_reveals_spacing():
    """Test that messages are scheduled with correct time spacing"""
    service = HistoricalBackfillService()
    
    # Mock add_to_backfill_queue to just return an ID
    with patch("services.backfill_service.add_to_backfill_queue") as mock_add:
        mock_add.side_effect = [1, 2, 3]  # Return dummy IDs
        
        messages = [
            {"body": "msg1", "received_at": datetime.utcnow() - timedelta(days=1)},
            {"body": "msg2", "received_at": datetime.utcnow() - timedelta(days=2)}, # Older
            {"body": "msg3", "received_at": datetime.utcnow()},
        ]
        
        count = await service.schedule_historical_messages(
            license_id=123,
            channel="email",
            messages=messages
        )
        
        assert count == 3
        assert mock_add.call_count == 3
        
        # Check call arguments to verify timing
        # Messages should be sorted by received_at (oldest first)
        # msg2 -> msg1 -> msg3
        
        # Verify call args
        calls = mock_add.call_args_list
        
        # 1st call (msg2 - oldest)
        args1, kwargs1 = calls[0]
        assert kwargs1["body"] == "msg2"
        scheduled1 = kwargs1["scheduled_reveal_at"]
        
        # 2nd call (msg1)
        args2, kwargs2 = calls[1]
        assert kwargs2["body"] == "msg1"
        scheduled2 = kwargs2["scheduled_reveal_at"]
        
        # 3rd call (msg3 - newest)
        args3, kwargs3 = calls[2]
        assert kwargs3["body"] == "msg3"
        scheduled3 = kwargs3["scheduled_reveal_at"]
        
        # Check intervals
        # scheduled2 should be 1 interval after scheduled1
        diff1 = (scheduled2 - scheduled1).total_seconds()
        assert abs(diff1 - BACKFILL_REVEAL_INTERVAL_SECONDS) < 1.0
        
        # scheduled3 should be 1 interval after scheduled2
        diff2 = (scheduled3 - scheduled2).total_seconds()
        assert abs(diff2 - BACKFILL_REVEAL_INTERVAL_SECONDS) < 1.0


@pytest.mark.asyncio
async def test_should_trigger_backfill():
    """Test backfill trigger logic"""
    service = HistoricalBackfillService()
    
    with patch("services.backfill_service.get_backfill_queue_count") as mock_count:
        # Case 1: No existing items -> Should trigger
        mock_count.return_value = 0
        should = await service.should_trigger_backfill(123, "email")
        assert should is True
        
        # Case 2: Existing items -> Should NOT trigger
        mock_count.return_value = 5
        should = await service.should_trigger_backfill(123, "email")
        assert should is False

@pytest.mark.asyncio
async def test_process_pending_reveals():
    """Test processing of pending reveals"""
    service = HistoricalBackfillService()
    
    # Mock dependencies
    with patch("services.backfill_service.get_next_pending_reveal") as mock_get, \
         patch("services.backfill_service.save_inbox_message") as mock_save, \
         patch("services.backfill_service.mark_as_revealed") as mock_mark:
        
        # Case 1: No pending message
        mock_get.return_value = None
        count = await service.process_pending_reveals(123)
        assert count == 0
        mock_save.assert_not_called()
        
        # Case 2: Pending message found
        mock_get.return_value = {
            "id": 10,
            "license_key_id": 123,
            "channel": "email",
            "body": "test body",
            "sender_name": "Test User",
            "attachments": None
        }
        mock_save.return_value = 1001 # inbox ID
        
        count = await service.process_pending_reveals(123)
        
        assert count == 1
        mock_save.assert_called_once()
        mock_mark.assert_called_with(10, 1001)

@pytest.mark.asyncio
async def test_process_pending_reveals_with_attachments():
    """Test processing of pending reveals with attachments"""
    service = HistoricalBackfillService()
    
    # Mock dependencies
    with patch("services.backfill_service.get_next_pending_reveal") as mock_get, \
         patch("services.backfill_service.save_inbox_message") as mock_save, \
         patch("services.backfill_service.mark_as_revealed") as mock_mark:
        
        # Pending message with JSON string attachments
        import json
        atts = [{"name": "test.pdf", "type": "application/pdf"}]
        mock_get.return_value = {
            "id": 11,
            "license_key_id": 123,
            "channel": "email",
            "body": "test body",
            "attachments": json.dumps(atts)
        }
        mock_save.return_value = 1002
        
        count = await service.process_pending_reveals(123)
        
        assert count == 1
        # Verify attachments were parsed back to list
        call_kwargs = mock_save.call_args[1]
        assert call_kwargs["attachments"] == atts
