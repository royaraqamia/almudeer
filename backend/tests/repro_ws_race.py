import asyncio
import pytest
from unittest.mock import AsyncMock, patch
from starlette.websockets import WebSocketState
from services.websocket_manager import ConnectionManager, WebSocketMessage

@pytest.mark.asyncio
async def test_websocket_race_condition_hardening():
    """
    Verify that a connection is NOT included in broadcasts until it has fully 
    completed its registration in the 'connect' method.
    """
    manager = ConnectionManager()
    license_id = 123
    
    # Mock WebSocket
    mock_ws = AsyncMock()
    mock_ws.client_state = WebSocketState.CONNECTING
    
    # Mock manager behavior to simulate slow initialization
    orig_ensure_pubsub = manager._ensure_pubsub
    manager._ensure_pubsub = AsyncMock()
    
    # Task 1: Connect with a simulated delay during initialization
    async def slow_connect():
        # Trigger acceptance
        await manager.connect(mock_ws, license_id)
        mock_ws.client_state = WebSocketState.CONNECTED

    # Task 2: Attempt a broadcast while the connection is still in 'slow_connect'
    # but potentially AFTER accept() has been called.
    
    async def try_broadcast():
        # Wait a bit for slow_connect to call accept() and ensure_pubsub()
        await asyncio.sleep(0.02)
        
        # Verify socket is NOT in connections yet
        assert license_id not in manager._connections, "Socket should not be in connections yet"
        
        msg = WebSocketMessage(event="test", data={})
        # This will not find the connection locally
        await manager.send_to_license(license_id, msg)

    # Run both
    with patch("services.websocket_manager.broadcast_presence_update", new_callable=AsyncMock), \
         patch("db_helper.get_db", return_value=AsyncMock()), \
         patch("db_helper.execute_sql", new_callable=AsyncMock), \
         patch("db_helper.fetch_one", new_callable=AsyncMock(return_value={"username": "test_user"})), \
         patch("db_helper.commit_db", new_callable=AsyncMock):
        await asyncio.gather(slow_connect(), try_broadcast())

    # Verify finally registered
    assert license_id in manager._connections
    assert mock_ws in manager._connections[license_id]
    assert mock_ws.send_text.call_count == 0, "Broadcast should not have reached uninitialized socket"

@pytest.mark.asyncio
async def test_websocket_state_check_hardening():
    """
    Verify that _send_to_local_connections respects WebSocketState.CONNECTED
    """
    manager = ConnectionManager()
    license_id = 456
    
    # Mock WebSocket in CONNECTING state
    mock_ws = AsyncMock()
    mock_ws.client_state = WebSocketState.CONNECTING
    
    # Manually add to connections (simulating a race where it got added but state changed)
    manager._connections[license_id] = {mock_ws}
    
    msg = WebSocketMessage(event="test", data={})
    await manager._send_to_local_connections(license_id, msg)
    
    assert mock_ws.send_text.call_count == 0, "Should skip sending to non-CONNECTED sockets"
    
    # Now set to CONNECTED and try again
    mock_ws.client_state = WebSocketState.CONNECTED
    await manager._send_to_local_connections(license_id, msg)
    assert mock_ws.send_text.call_count == 1

if __name__ == "__main__":
    pytest.main([__file__])
