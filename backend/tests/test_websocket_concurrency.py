import asyncio
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from services.websocket_manager import RedisPubSubManager, WebSocketMessage

@pytest.mark.asyncio
async def test_redis_pubsub_concurrency():
    manager = RedisPubSubManager()
    
    # Mock redis
    mock_redis = AsyncMock()
    mock_pubsub = AsyncMock()
    
    with patch("redis.asyncio.from_url", return_value=mock_redis), \
         patch("os.getenv", return_value="redis://mock"):
        
        await manager.initialize()
        manager._pubsub = mock_pubsub
        
        # Stress test subscribe/unsubscribe while _listen might be running
        async def mock_handler(msg):
            pass
            
        async def stress_subscriptions():
            for i in range(50):
                await manager.subscribe(i, mock_handler)
                await asyncio.sleep(0.01)
                await manager.unsubscribe(i)
        
        # Start listener (it will be started by first subscribe)
        # We need to make sure _listen actually tries to get messages
        async def mock_get_message(*args, **kwargs):
            await asyncio.sleep(0.05)
            return None
        
        mock_pubsub.get_message = mock_get_message
        
        # Run concurrent subscriptions and listener
        # The lock should prevent "readuntil" issues (simulated by non-atomic access if we were testing real streams)
        # Here we just verify it doesn't crash and lock works
        await asyncio.gather(
            stress_subscriptions(),
            stress_subscriptions(),
            stress_subscriptions()
        )
        
        await manager.close()

if __name__ == "__main__":
    asyncio.run(test_redis_pubsub_concurrency())
