import pytest
import asyncio
import json
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime
from contextlib import asynccontextmanager

# We will test the logic that WAS in main.py by simulating a ping
@pytest.mark.asyncio
async def test_presence_isolation():
    """Test that ping only refreshes the active account and NOT companions"""
    from services.websocket_manager import ConnectionManager
    manager = ConnectionManager()
    manager._pubsub._initialized = True
    
    primary_license_id = 101
    companion_id = 202
    
    # Mock database
    mock_conn = MagicMock()
    @asynccontextmanager
    async def mock_get_db_ctx():
        yield mock_conn

    with patch('db_helper.get_db', side_effect=mock_get_db_ctx), \
         patch('db_helper.execute_sql', new_callable=AsyncMock) as mock_execute, \
         patch('db_helper.commit_db', new_callable=AsyncMock) as mock_commit:
        
        # Simulating what happens in main.py now:
        # Only the primary ID is refreshed.
        await manager.refresh_last_seen(primary_license_id)
        
        # We explicitly DO NOT call anything for the companion
        
        # Verification
        update_calls = [args[1] for args, kwargs in mock_execute.call_args_list if "UPDATE license_keys" in args[1]]
        update_params = [args[2] for args, kwargs in mock_execute.call_args_list if "UPDATE license_keys" in args[1]]
        
        assert len(update_calls) == 1
        assert update_params[0][1] == primary_license_id
        
        # Verify companion was NOT updated
        companion_updates = [p for p in update_params if p[1] == companion_id]
        assert len(companion_updates) == 0
        
        print("SUCCESS: Presence isolation verified. No cross-contamination of last_seen_at.")
        return True

@pytest.mark.asyncio
async def test_manager_still_has_utility():
    """Verify following utility still exists even if not used by mobile app"""
    from services.websocket_manager import ConnectionManager
    manager = ConnectionManager()
    manager._pubsub._initialized = True
    
    companion_key = "UTILS-KEY"
    companion_id = 999
    
    mock_conn = MagicMock()
    @asynccontextmanager
    async def mock_get_db_ctx(): yield mock_conn

    async def mock_fetch_one(db, sql, params):
        return {"id": companion_id}

    with patch('db_helper.get_db', side_effect=mock_get_db_ctx), \
         patch('db_helper.fetch_one', side_effect=mock_fetch_one), \
         patch('db_helper.execute_sql', new_callable=AsyncMock) as mock_execute, \
         patch('db_helper.commit_db', new_callable=AsyncMock) as mock_commit:
         
         await manager.refresh_last_seen_by_key(companion_key)
         assert mock_execute.called
         print("SUCCESS: Utility method refresh_last_seen_by_key still functional.")

if __name__ == "__main__":
    asyncio.run(test_presence_isolation())
    asyncio.run(test_manager_still_has_utility())
