"""
Reliable Broadcast Service
Ensures message delivery with sequence numbers, retries, and gap detection.
"""

import os
import json
import asyncio
from typing import Dict, Any, Optional, Set
from datetime import datetime
from logging_config import get_logger

logger = get_logger(__name__)


class ReliableBroadcastService:
    """
    Provides reliable message broadcasting with:
    - Sequence numbers for gap detection
    - Redis-based message queue for retry
    - Client-side acknowledgment tracking
    """
    
    MESSAGE_QUEUE_KEY = "almudeer:broadcast:pending"
    SEQUENCE_KEY_PREFIX = "almudeer:sequence:"
    ACK_TIMEOUT = 30  # seconds
    
    def __init__(self):
        self._redis_client = None
        self._initialized = False
        self._sequence_counters: Dict[int, int] = {}  # license_id -> sequence
    
    async def initialize(self) -> bool:
        """Initialize Redis connection"""
        redis_url = os.getenv("REDIS_URL")
        if not redis_url:
            logger.info("Redis URL not configured, reliable broadcast disabled")
            return False
        
        try:
            import redis.asyncio as aioredis
            self._redis_client = await aioredis.from_url(redis_url, decode_responses=True)
            await self._redis_client.ping()
            self._initialized = True
            logger.info("Reliable broadcast service initialized")
            return True
        except Exception as e:
            logger.warning(f"Failed to initialize reliable broadcast: {e}")
            return False
    
    def _get_sequence_key(self, license_id: int) -> str:
        """Get Redis key for sequence counter"""
        return f"{self.SEQUENCE_KEY_PREFIX}{license_id}"
    
    async def _get_next_sequence(self, license_id: int) -> int:
        """Get next sequence number for a license"""
        if not self._initialized:
            return 0
        
        try:
            key = self._get_sequence_key(license_id)
            seq = await self._redis_client.incr(key)
            # Set expiry to prevent unbounded growth (7 days)
            await self._redis_client.expire(key, 604800)
            return seq
        except Exception as e:
            logger.error(f"Failed to get sequence: {e}")
            return 0
    
    async def broadcast_with_retry(
        self,
        license_id: int,
        event: str,
        data: Dict[str, Any],
        max_retries: int = 3
    ) -> bool:
        """
        Broadcast message with retry mechanism.
        Stores message in Redis queue for potential retry.
        """
        if not self._initialized:
            return False
        
        sequence = await self._get_next_sequence(license_id)
        
        message = {
            "event": event,
            "data": data,
            "sequence": sequence,
            "timestamp": datetime.utcnow().isoformat(),
            "license_id": license_id
        }
        
        # Store in pending queue for retry
        try:
            await self._redis_client.lpush(
                self.MESSAGE_QUEUE_KEY,
                json.dumps(message)
            )
            # Keep queue bounded - remove old messages
            await self._redis_client.ltrim(self.MESSAGE_QUEUE_KEY, 0, 999)
        except Exception as e:
            logger.error(f"Failed to queue message for retry: {e}")
        
        # Send via WebSocket manager
        from .websocket_manager import get_websocket_manager
        manager = get_websocket_manager()
        
        for attempt in range(max_retries):
            try:
                await manager.send_to_license(license_id, WebSocketMessage(**message))
                # Success - remove from queue
                await self._remove_from_queue(message)
                return True
            except Exception as e:
                logger.warning(f"Broadcast attempt {attempt + 1} failed: {e}")
                if attempt < max_retries - 1:
                    await asyncio.sleep(0.1 * (2 ** attempt))  # Exponential backoff
        
        return False
    
    async def _remove_from_queue(self, message: Dict[str, Any]) -> bool:
        """Remove message from pending queue after successful delivery"""
        if not self._initialized:
            return False
        
        try:
            # Remove by sequence number
            message_json = json.dumps(message)
            await self._redis_client.lrem(self.MESSAGE_QUEUE_KEY, 1, message_json)
            return True
        except Exception as e:
            logger.error(f"Failed to remove message from queue: {e}")
            return False
    
    async def get_pending_messages(self, license_id: int) -> list:
        """Get pending messages for a license (for gap recovery)"""
        if not self._initialized:
            return []
        
        try:
            messages = await self._redis_client.lrange(self.MESSAGE_QUEUE_KEY, 0, -1)
            result = []
            for msg_json in messages:
                msg = json.loads(msg_json)
                if msg.get("license_id") == license_id:
                    result.append(msg)
            return result
        except Exception as e:
            logger.error(f"Failed to get pending messages: {e}")
            return []
    
    async def acknowledge_sequence(
        self,
        license_id: int,
        sequence: int
    ) -> bool:
        """
        Acknowledge receipt of a sequence number.
        Client sends this after receiving messages.
        """
        if not self._initialized:
            return False
        
        try:
            key = f"almudeer:acks:{license_id}"
            await self._redis_client.setex(
                f"{key}:{sequence}",
                self.ACK_TIMEOUT,
                "1"
            )
            return True
        except Exception as e:
            logger.error(f"Failed to acknowledge sequence: {e}")
            return False
    
    async def get_last_acknowledged_sequence(
        self,
        license_id: int
    ) -> Optional[int]:
        """Get last acknowledged sequence number for gap detection"""
        if not self._initialized:
            return None
        
        try:
            # Scan for ack keys
            cursor = 0
            max_seq = 0
            while True:
                cursor, keys = await self._redis_client.scan(
                    cursor,
                    match=f"almudeer:acks:{license_id}:*",
                    count=100
                )
                for key in keys:
                    seq = int(key.split(":")[-1])
                    max_seq = max(max_seq, seq)
                if cursor == 0:
                    break
            return max_seq if max_seq > 0 else None
        except Exception as e:
            logger.error(f"Failed to get acknowledged sequence: {e}")
            return None


# Import WebSocketMessage for compatibility
from .websocket_manager import WebSocketMessage

# Global service instance
_service: Optional[ReliableBroadcastService] = None


def get_reliable_broadcast_service() -> ReliableBroadcastService:
    """Get or create the global reliable broadcast service"""
    global _service
    if _service is None:
        _service = ReliableBroadcastService()
    return _service


# ============ Enhanced Broadcasting Helpers ============

async def broadcast_new_message_reliable(
    license_id: int,
    message_data: Dict[str, Any]
) -> bool:
    """Broadcast new message with reliability guarantees"""
    service = get_reliable_broadcast_service()
    if not await service.initialize():
        # Fallback to regular broadcast
        from .websocket_manager import broadcast_new_message
        await broadcast_new_message(license_id, message_data)
        return True
    
    return await service.broadcast_with_retry(
        license_id,
        "new_message",
        message_data
    )


async def broadcast_message_status_update_reliable(
    license_id: int,
    status_data: Dict[str, Any]
) -> bool:
    """Broadcast message status update with reliability"""
    service = get_reliable_broadcast_service()
    if not await service.initialize():
        from .websocket_manager import broadcast_message_status_update
        await broadcast_message_status_update(license_id, status_data)
        return True
    
    return await service.broadcast_with_retry(
        license_id,
        "message_status_update",
        status_data
    )
