import pytest
import asyncio
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime
from services.websocket_manager import ConnectionManager
from contextlib import asynccontextmanager

@pytest.mark.asyncio
async def test_refresh_last_seen():
    """Test that refresh_last_seen sends the correct UPDATE query"""
    manager = ConnectionManager()
    # Mock Redis availability by setting the internal flag
    manager._pubsub._initialized = True
    license_id = 999
    
    # Mock database
    mock_conn = MagicMock()
    @asynccontextmanager
    async def mock_get_db_ctx():
        yield mock_conn
        
    with patch('db_helper.get_db', side_effect=mock_get_db_ctx), \
         patch('db_helper.execute_sql', new_callable=AsyncMock) as mock_execute, \
         patch('db_helper.commit_db', new_callable=AsyncMock) as mock_commit:
        
        await manager.refresh_last_seen(license_id)
        
        if not mock_execute.called:
            print("ERROR: execute_sql was NOT called")
            return False
            
        args, kwargs = mock_execute.call_args
        sql = args[1]
        params = args[2]
        
        print(f"SQL: {sql}")
        print(f"Params: {params}")
        
        assert "UPDATE license_keys SET last_seen_at =" in sql
        assert "WHERE id = ?" in sql
        assert params[1] == license_id
        assert isinstance(params[0], datetime)
        
        assert mock_commit.called
        print("SUCCESS: test_refresh_last_seen passed")
        return True

if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    success = loop.run_until_complete(test_refresh_last_seen())
    if not success:
        exit(1)
