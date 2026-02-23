"""
Al-Mudeer - WebSocket Service
Real-time updates for inbox, notifications, and analytics
Replaces polling with efficient push notifications

Enhanced with Redis pub/sub for horizontal scaling across multiple workers.
"""

import asyncio
import json
import os
from typing import Dict, Set, Optional, Any
from datetime import datetime
from dataclasses import dataclass, asdict
from utils.json_utils import json_dumps

from fastapi import WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState
from logging_config import get_logger

logger = get_logger(__name__)


@dataclass
class WebSocketMessage:
    """Structure for WebSocket messages"""
    event: str  # "new_message", "notification", "analytics_update", etc.
    data: Dict[str, Any]
    timestamp: str = ""
    
    def __post_init__(self):
        if not self.timestamp:
            self.timestamp = datetime.utcnow().isoformat()
    
    def to_json(self) -> str:
        return json_dumps(asdict(self))
    
    @classmethod
    def from_json(cls, json_str: str) -> "WebSocketMessage":
        """Parse from JSON string"""
        data = json.loads(json_str)
        return cls(
            event=data.get("event", ""),
            data=data.get("data", {}),
            timestamp=data.get("timestamp", "")
        )


class RedisPubSubManager:
    """
    Manages Redis pub/sub for cross-process WebSocket message delivery.
    Enables horizontal scaling by broadcasting messages through Redis.
    """
    
    CHANNEL_PREFIX = "almudeer:ws:"
    OUTBOX_TRIGGER_CHANNEL = "almudeer:outbox_trigger"
    
    def __init__(self):
        self._redis_client = None
        self._pubsub = None
        self._lock = asyncio.Lock()  # Synchronize access to self._pubsub
        self._listener_task: Optional[asyncio.Task] = None
        self._message_handlers: Dict[int, Any] = {}  # license_id -> callback
        self._initialized = False
    
    async def initialize(self) -> bool:
        """Initialize Redis connection for pub/sub"""
        if self._initialized:
            return True
            
        redis_url = os.getenv("REDIS_URL")
        if not redis_url:
            logger.info("Redis URL not configured, pub/sub disabled")
            return False
        
        try:
            import redis.asyncio as aioredis
            self._redis_client = await aioredis.from_url(
                redis_url,
                decode_responses=True
            )
            # Test connection
            await self._redis_client.ping()
            self._pubsub = self._redis_client.pubsub()
            self._initialized = True
            logger.info("Redis pub/sub initialized successfully")
            return True
        except ImportError:
            logger.warning("redis.asyncio not available, pub/sub disabled")
            return False
        except Exception as e:
            logger.warning(f"Failed to initialize Redis pub/sub: {e}")
            return False
    
    async def subscribe(self, license_id: int, handler):
        """Subscribe to messages for a specific license"""
        if not self._initialized:
            return
        
        channel = f"{self.CHANNEL_PREFIX}{license_id}"
        self._message_handlers[license_id] = handler
        
        async with self._lock:
            try:
                await self._pubsub.subscribe(channel)
                logger.debug(f"Subscribed to Redis channel: {channel}")
                
                # Start listener if not already running
                if self._listener_task is None or self._listener_task.done():
                    self._listener_task = asyncio.create_task(self._listen())
            except Exception as e:
                logger.error(f"Failed to subscribe to Redis channel: {e}")
    
    async def unsubscribe(self, license_id: int):
        """Unsubscribe from messages for a specific license"""
        if not self._initialized:
            return
        
        channel = f"{self.CHANNEL_PREFIX}{license_id}"
        self._message_handlers.pop(license_id, None)
        
        async with self._lock:
            try:
                await self._pubsub.unsubscribe(channel)
                logger.debug(f"Unsubscribed from Redis channel: {channel}")
                
                # Stop listener if no more subscriptions
                if not self._message_handlers and self._listener_task:
                    self._listener_task.cancel()
                    self._listener_task = None
                    logger.debug("Redis listener stopped (no subscriptions)")
                    
            except Exception as e:
                logger.error(f"Failed to unsubscribe from Redis channel: {e}")
    
            return False

    async def publish_outbox_trigger(self, license_id: int):
        """Trigger immediate outbox processing for a license"""
        if not self._initialized:
            return False
        try:
            await self._redis_client.publish(self.OUTBOX_TRIGGER_CHANNEL, str(license_id))
            logger.debug(f"Published outbox trigger for license: {license_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to publish outbox trigger: {e}")
            return False

    async def subscribe_system(self, handler):
        """Subscribe to system-wide triggers"""
        if not self._initialized:
            return
        
        async with self._lock:
            try:
                await self._pubsub.subscribe(self.OUTBOX_TRIGGER_CHANNEL)
                logger.info(f"Subscribed to system channel: {self.OUTBOX_TRIGGER_CHANNEL}")
                
                # Register a special handler key for system
                self._message_handlers[-1] = handler 
                
                if self._listener_task is None or self._listener_task.done():
                    self._listener_task = asyncio.create_task(self._listen())
            except Exception as e:
                logger.error(f"Failed to subscribe to system channel: {e}")

    async def _listen(self):
        """Background task to listen for Redis messages"""
        try:
            while True:
                # Use lock for reading message to prevent concurrent read errors
                message = None
                async with self._lock:
                    if self._pubsub:
                        message = await self._pubsub.get_message(
                            ignore_subscribe_messages=True,
                            timeout=0.1 # Shorter timeout when holding lock
                        )
                
                if message and message.get("type") == "message":
                    channel = message.get("channel", "")
                    data = message.get("data", "")
                    
                    # Extract license_id from channel
                    if channel.startswith(self.CHANNEL_PREFIX):
                        try:
                            license_id = int(channel[len(self.CHANNEL_PREFIX):])
                            handler = self._message_handlers.get(license_id)
                            if handler:
                                ws_message = WebSocketMessage.from_json(data)
                                await handler(ws_message)
                        except (ValueError, json.JSONDecodeError) as e:
                            logger.debug(f"Failed to parse Redis message: {e}")
                    elif channel == self.OUTBOX_TRIGGER_CHANNEL:
                        try:
                            handler = self._message_handlers.get(-1) # System handler
                            if handler:
                                await handler(data) # data is the license_id string
                        except Exception as e:
                            logger.error(f"Error in system message handler: {e}")
                
                if not message:
                    await asyncio.sleep(0.1)  # Sleep longer if no message
                else:
                    await asyncio.sleep(0.01) # Rapid check after message
        except asyncio.CancelledError:
            pass
        except Exception as e:
            # Ignore "pubsub connection not set" error which can happen during shutdown/unsubscribe
            if "pubsub connection not set" in str(e):
                logger.debug(f"Redis listener stopped (connection closed): {e}")
                return
            logger.error(f"Redis listener error: {e}")
            # Wait a bit before restarting loop if it was a transient error
            await asyncio.sleep(1.0)
    
    async def close(self):
        """Close Redis connections"""
        if self._listener_task:
            self._listener_task.cancel()
            try:
                await self._listener_task
            except asyncio.CancelledError:
                pass
        
        if self._pubsub:
            await self._pubsub.close()
        
        if self._redis_client:
            await self._redis_client.close()
        
        self._initialized = False
    
    @property
    def is_available(self) -> bool:
        """Check if Redis pub/sub is available"""
        return self._initialized

    @property
    def redis_client(self):
        """Get the underlying Redis client"""
        return self._redis_client


class ConnectionManager:
    """
    Manages WebSocket connections for real-time updates.
    Organizes connections by license_id for targeted messaging.
    
    With Redis pub/sub enabled, messages are broadcast across all workers.
    """
    
    def __init__(self):
        # Active connections organized by license_id
        self._connections: Dict[int, Set[WebSocket]] = {}
        self._lock = asyncio.Lock()
        self._pubsub = RedisPubSubManager()
        self._pubsub_initialized = False

    @property
    def redis_client(self):
        """Get the underlying Redis client from pubsub manager"""
        return self._pubsub.redis_client

    @property
    def redis_enabled(self) -> bool:
        """Check if Redis is enabled and available"""
        return self._pubsub.is_available
    
    async def _ensure_pubsub(self):
        """Initialize pub/sub lazily"""
        if not self._pubsub_initialized:
            await self._pubsub.initialize()
            self._pubsub_initialized = True
    
    async def cleanup_stale_presence(self):
        """Clear all stale presence counters on server startup.
        
        When the server restarts, all WebSocket connections are lost,
        but Redis INCR counters may still be > 0 from the previous run.
        This resets them all to 0 so nobody shows as falsely online.
        """
        if not self._pubsub.is_available:
            return
        try:
            redis = self._pubsub._redis_client
            cursor = 0
            total_cleaned = 0
            while True:
                cursor, keys = await redis.scan(cursor, match="almudeer:presence:count:*", count=100)
                if keys:
                    await redis.delete(*keys)
                    total_cleaned += len(keys)
                if cursor == 0:
                    break
            if total_cleaned > 0:
                logger.info(f"Cleaned {total_cleaned} stale presence keys on startup")
        except Exception as e:
            logger.warning(f"Failed to cleanup stale presence keys: {e}")
    
    async def connect(self, websocket: WebSocket, license_id: int):
        """Accept and register a new WebSocket connection"""
        await websocket.accept()
        await self._ensure_pubsub()
        
        # Global presence tracking via Redis
        if self._pubsub.is_available:
            try:
                # Increment global connection count for this license
                global_count_key = f"almudeer:presence:count:{license_id}"
                new_count = await self._pubsub._redis_client.incr(global_count_key)
                # Set TTL so stale keys auto-expire if server crashes (2 min)
                await self._pubsub._redis_client.expire(global_count_key, 120)
                
                # Update last_seen_at and ensure username is populated (safety net for old users)
                from db_helper import get_db, execute_sql, commit_db, fetch_one
                now = datetime.utcnow()
                async with get_db() as db:
                    # Check if username is missing
                    license_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
                    if license_row and not license_row.get("username"):
                        user_row = await fetch_one(db, "SELECT email FROM users WHERE license_key_id = ? ORDER BY id ASC LIMIT 1", [license_id])
                        if user_row and user_row.get("email"):
                            await execute_sql(db, "UPDATE license_keys SET username = ? WHERE id = ?", (user_row["email"], license_id))
                    
                    await execute_sql(db, "UPDATE license_keys SET last_seen_at = ? WHERE id = ?", (now, license_id))
                    await commit_db(db)
                
                # Only broadcast online if this is the first connection globally
                if new_count == 1:
                    await broadcast_presence_update(license_id, is_online=True)
            except Exception as e:
                logger.error(f"Error updating global presence on connect: {e}")
        else:
            # Fallback for single-worker / no redis
            from db_helper import get_db, execute_sql, commit_db
            async with get_db() as db:
                await execute_sql(db, "UPDATE license_keys SET last_seen_at = ? WHERE id = ?", (datetime.utcnow(), license_id))
                await commit_db(db)
            await broadcast_presence_update(license_id, is_online=True)

        async with self._lock:
            if license_id not in self._connections:
                self._connections[license_id] = set()
                # Subscribe to Redis channel for this license
                if self._pubsub.is_available:
                    await self._pubsub.subscribe(
                        license_id,
                        lambda msg: self._handle_redis_message(license_id, msg)
                    )
            self._connections[license_id].add(websocket)
        
        logger.info(f"WebSocket connected: license {license_id} (total: {self.connection_count})")
    
    async def refresh_last_seen(self, license_id: int):
        if self._pubsub.is_available:
            try:
                from db_helper import get_db, execute_sql, commit_db
                from datetime import datetime
                now = datetime.utcnow()
                async with get_db() as db:
                    await execute_sql(db, "UPDATE license_keys SET last_seen_at = ? WHERE id = ?", (now, license_id))
                    await commit_db(db)
            except Exception as e:
                logger.error(f"Error in refresh_last_seen: {e}")

    async def refresh_last_seen_by_key(self, license_key: str):
        """Update last_seen_at using the raw license key (for multi-presence heartbeats)"""
        if self._pubsub.is_available:
            try:
                from database import hash_license_key
                from db_helper import get_db, execute_sql, fetch_one, commit_db
                from datetime import datetime
                key_hash = hash_license_key(license_key)
                async with get_db() as db:
                    # First find the ID
                    row = await fetch_one(db, "SELECT id FROM license_keys WHERE key_hash = ?", [key_hash])
                    if row:
                        await execute_sql(db, "UPDATE license_keys SET last_seen_at = ? WHERE id = ?", (datetime.utcnow(), row["id"]))
                        await commit_db(db)
            except Exception as e:
                logger.error(f"Error in refresh_last_seen_by_key: {e}")

    async def disconnect(self, websocket: WebSocket, license_id: int):
        """Remove a WebSocket connection"""
        async with self._lock:
            if license_id in self._connections:
                self._connections[license_id].discard(websocket)
                if not self._connections[license_id]:
                    del self._connections[license_id]
                    
                    # Global presence tracking via Redis
                    if self._pubsub.is_available:
                        try:
                            # Unsubscribe from Redis channel locally
                            await self._pubsub.unsubscribe(license_id)
                            
                            # Decrement global connection count
                            global_count_key = f"almudeer:presence:count:{license_id}"
                            new_count = await self._pubsub._redis_client.decr(global_count_key)
                            if new_count < 0:
                                await self._pubsub._redis_client.set(global_count_key, 0)
                                new_count = 0
                                
                            # Update last_seen_at
                            from db_helper import get_db, execute_sql, commit_db
                            now = datetime.utcnow()
                            async with get_db() as db:
                                await execute_sql(db, "UPDATE license_keys SET last_seen_at = ? WHERE id = ?", (now, license_id))
                                await commit_db(db)
                            
                            # Only broadcast offline if no more global connections
                            if new_count == 0:
                                await broadcast_presence_update(license_id, is_online=False, last_seen=now.isoformat())
                        except Exception as e:
                            logger.error(f"Error updating global presence on disconnect: {e}")
                    else:
                        # Fallback for single-worker / no redis
                        from db_helper import get_db, execute_sql, commit_db
                        now = datetime.utcnow()
                        async with get_db() as db:
                            await execute_sql(db, "UPDATE license_keys SET last_seen_at = ? WHERE id = ?", (now, license_id))
                            await commit_db(db)
                        
                        await broadcast_presence_update(license_id, is_online=False, last_seen=now.isoformat())
                    
        logger.info(f"WebSocket disconnected: license {license_id}")
    
    async def _handle_redis_message(self, license_id: int, message: WebSocketMessage):
        """Handle incoming message from Redis pub/sub"""
        # Send to local connections only (Redis already broadcast to other workers)
        await self._send_to_local_connections(license_id, message)
    
    async def _send_to_local_connections(self, license_id: int, message: WebSocketMessage):
        """Send message to local WebSocket connections only"""
        if license_id not in self._connections:
            return
        
        dead_connections = []
        json_message = message.to_json()
        
        for connection in list(self._connections.get(license_id, [])):
            if connection.client_state != WebSocketState.CONNECTED:
                logger.debug(f"Skipping send: WebSocket state is {connection.client_state}")
                continue
            
            try:
                await connection.send_text(json_message)
            except RuntimeError as e:
                # Catch "WebSocket is not connected" which can happen if state changes between check and send
                logger.debug(f"Runtime error sending to WebSocket: {e}")
                dead_connections.append(connection)
            except Exception as e:
                logger.debug(f"Failed to send to WebSocket: {e}")
                dead_connections.append(connection)
        
        # Clean up dead connections
        for conn in dead_connections:
            await self.disconnect(conn, license_id)
    
    async def send_to_license(self, license_id: int, message: WebSocketMessage):
        """
        Send a message to all connections for a specific license.
        If Redis is available, publishes to Redis for cross-worker delivery.
        Otherwise, sends directly to local connections.
        """
        if self._pubsub.is_available:
            # Publish to Redis - all workers will receive and forward to their local connections
            published = await self._pubsub.publish(license_id, message)
            if published:
                return
        
        # Fallback: Direct send to local connections
        await self._send_to_local_connections(license_id, message)
    
    async def broadcast(self, message: WebSocketMessage):
        """Send a message to all connected clients"""
        # For broadcast, we send to all local connections
        # Each worker handles its own local connections
        json_message = message.to_json()
        
        for license_id in list(self._connections.keys()):
            for connection in list(self._connections.get(license_id, [])):
                try:
                    await connection.send_text(json_message)
                except Exception:
                    pass
    
    @property
    def connection_count(self) -> int:
        """Get total number of active connections"""
        return sum(len(conns) for conns in self._connections.values())
    
    def get_connected_licenses(self) -> Set[int]:
        """Get set of license IDs with active connections"""
        return set(self._connections.keys())
    
    @property
    def redis_enabled(self) -> bool:
        """Check if Redis pub/sub is enabled"""
        return self._pubsub.is_available


# Global connection manager
_manager: Optional[ConnectionManager] = None


def get_websocket_manager() -> ConnectionManager:
    """Get or create the global WebSocket manager"""
    global _manager
    if _manager is None:
        _manager = ConnectionManager()
    return _manager


# ============ Event Broadcasting Helpers ============

async def broadcast_new_message(license_id: int, message_data: Dict[str, Any]):
    """Broadcast when a new inbox message arrives"""
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="new_message",
        data=message_data
    ))


async def broadcast_notification(license_id: int, notification: Dict[str, Any]):
    """Broadcast a new notification"""
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="notification",
        data=notification
    ))


async def broadcast_analytics_update(license_id: int, analytics: Dict[str, Any]):
    """Broadcast analytics data update"""
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="analytics_update",
        data=analytics
    ))


async def broadcast_task_complete(license_id: int, task_id: str, result: Dict[str, Any]):
    """Broadcast when an async task completes"""
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="task_complete",
        data={"task_id": task_id, "result": result}
    ))


async def broadcast_subscription_updated(license_id: int, update_data: Dict[str, Any]):
    """
    Broadcast when a user's subscription or profile data is updated.
    Notifies the user themselves (multi-device) and all managers who have 
    this user in their customer list.
    """
    manager = get_websocket_manager()
    
    # 1. Broadcast to self (multi-device sync)
    await manager.send_to_license(license_id, WebSocketMessage(
        event="subscription_updated",
        data={**update_data, "is_self": True}
    ))

    # 2. Broadcast to all managers who have this user as a customer
    from db_helper import get_db, fetch_all, fetch_one
    try:
        async with get_db() as db:
            # Find the username of the updated user (to use as sender_contact in peers' apps)
            user_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
            if not user_row or not user_row.get("username"):
                return
            
            username = user_row["username"]
            
            # Find all licenses who have this user in their 'customers' table
            # We check by license_key_id link
            managers = await fetch_all(db, "SELECT DISTINCT license_key_id FROM customers WHERE contact = ?", [username])
            
            for manager_row in managers:
                manager_license_id = manager_row["license_key_id"]
                # For the manager, this is a CUSTOMER update
                await manager.send_to_license(manager_license_id, WebSocketMessage(
                    event="customer_updated",
                    data={
                        "sender_contact": username,
                        "updated_fields": update_data,
                        "is_self": False
                    }
                ))
    except Exception as e:
        logger.warning(f"Failed to notify managers of subscription update: {e}")


async def broadcast_customer_updated(license_id: int, customer_data: Dict[str, Any]):
    """Broadcast when a customer's information is updated"""
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="customer_updated",
        data=customer_data
    ))







# ============ Message Edit/Delete Broadcasting ============

async def broadcast_message_edited(license_id: int, message_id: int, new_body: str, edited_at: str, sender_contact: str = None):
    """
    Broadcast when a message is edited.
    Notifies both the sender (multi-device) and the recipient (if internal).
    """
    manager = get_websocket_manager()
    
    # payload for sync
    payload = {
        "message_id": message_id,
        "new_body": new_body,
        "edited_at": edited_at,
        "sender_contact": sender_contact
    }

    # 1. Send to self (multi-device sync)
    await manager.send_to_license(license_id, WebSocketMessage(
        event="message_edited",
        data=payload
    ))
    
    # 2. Check if peer is an internal almudeer user and notify them
    from db_helper import get_db, fetch_one
    try:
        async with get_db() as db:
            # If sender_contact wasn't provided, try to find it
            if not sender_contact:
                msg = await fetch_one(db, "SELECT channel, recipient_email, recipient_id FROM outbox_messages WHERE id = ?", [message_id])
                if msg:
                   sender_contact = msg.get("recipient_email") or msg.get("recipient_id")
                   payload["sender_contact"] = sender_contact
            else:
                msg = await fetch_one(db, "SELECT channel FROM outbox_messages WHERE id = ?", [message_id])

            if msg and msg.get("channel") in ["almudeer", "saved"] and sender_contact:
                # Check if recipient is a license username (internal peer)
                peer_row = await fetch_one(db, "SELECT id FROM license_keys WHERE username = ?", [sender_contact])
                if peer_row:
                    peer_license_id = peer_row["id"]
                    # For the peer, we also need to include sender_contact? 
                    # Actually for the peer, the "sender" of the edit is US (license_id)
                    # So the peer sees 'sender_contact' as US.
                    # We need to get OUR username.
                    owner_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
                    if owner_row:
                        peer_payload = payload.copy()
                        peer_payload["sender_contact"] = owner_row["username"]
                        await manager.send_to_license(peer_license_id, WebSocketMessage(
                            event="message_edited",
                            data=peer_payload
                        ))
    except Exception as e:
        from logging_config import get_logger
        get_logger(__name__).warning(f"Failed to notify peer of message edit: {e}")


async def broadcast_message_deleted(license_id: int, message_id: int, sender_contact: str = None):
    """
    Broadcast when a message is deleted.
    Notifies both the sender (multi-device) and the recipient (if internal).
    """
    manager = get_websocket_manager()
    
    payload = {
        "message_id": message_id,
        "sender_contact": sender_contact
    }

    # 1. Send to self (multi-device sync)
    await manager.send_to_license(license_id, WebSocketMessage(
        event="message_deleted",
        data=payload
    ))
    
    # 2. Check if peer is an internal almudeer user and notify them
    from db_helper import get_db, fetch_one
    try:
        async with get_db() as db:
            # If sender_contact wasn't provided, try to find it
            if not sender_contact:
                msg = await fetch_one(db, "SELECT channel, recipient_email, recipient_id FROM outbox_messages WHERE id = ?", [message_id])
                if msg:
                   sender_contact = msg.get("recipient_email") or msg.get("recipient_id")
                   payload["sender_contact"] = sender_contact
                else:
                    # Try inbox_messages
                    msg = await fetch_one(db, "SELECT channel, sender_contact FROM inbox_messages WHERE id = ?", [message_id])
                    if msg:
                        sender_contact = msg.get("sender_contact")
                        payload["sender_contact"] = sender_contact
            else:
                # Still need channel info for peer notification check
                msg = await fetch_one(db, "SELECT channel FROM outbox_messages WHERE id = ?", [message_id])
                if not msg:
                    msg = await fetch_one(db, "SELECT channel FROM inbox_messages WHERE id = ?", [message_id])

            if msg and msg.get("channel") in ["almudeer", "saved"] and sender_contact:
                # Check if recipient is a license username (internal peer)
                peer_row = await fetch_one(db, "SELECT id FROM license_keys WHERE username = ?", [sender_contact])
                if peer_row:
                    peer_license_id = peer_row["id"]
                    # For the peer, the "sender" of the deletion is US (license_id)
                    owner_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
                    if owner_row:
                        peer_payload = payload.copy()
                        peer_payload["sender_contact"] = owner_row["username"]
                        await manager.send_to_license(peer_license_id, WebSocketMessage(
                            event="message_deleted",
                            data=peer_payload
                        ))
    except Exception as e:
        from logging_config import get_logger
        get_logger(__name__).warning(f"Failed to notify peer of message deletion: {e}")


async def broadcast_conversation_deleted(license_id: int, sender_contact: str):
    """Broadcast when a full conversation is deleted"""
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="conversation_deleted",
        data={
            "sender_contact": sender_contact
        }
    ))


async def broadcast_chat_cleared(license_id: int, sender_contact: str):
    """
    Broadcast when a conversation history is cleared.
    This informs clients to empty the chat view and update the inbox list tile.
    """
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="chat_cleared",
        data={
            "sender_contact": sender_contact
        }
    ))


async def broadcast_typing_indicator(license_id: int, sender_contact: str, is_typing: bool):
    """Broadcast typing indicator for a specific conversation to self and internal peers"""
    manager = get_websocket_manager()
    
    # 1. Broadcast to self (multi-device sync)
    await manager.send_to_license(license_id, WebSocketMessage(
        event="typing_indicator",
        data={
            "sender_contact": sender_contact,
            "is_typing": is_typing,
            "is_self": True
        }
    ))

    # 2. Check if peer is an internal almudeer user and notify them
    from db_helper import get_db, fetch_one
    async with get_db() as db:
        # Get this user's username (to show who is typing to the peer)
        user_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
        if not user_row or not user_row.get("username"):
            return

        username = user_row["username"]
        
        # Check if the sender_contact (the person being typed to) is an internal user
        peer_row = await fetch_one(db, "SELECT id FROM license_keys WHERE username = ?", [sender_contact])
        if peer_row:
            peer_license_id = peer_row["id"]
            await manager.send_to_license(peer_license_id, WebSocketMessage(
                event="typing_indicator",
                data={
                    "sender_contact": username, # From peer's perspective, 'username' is the sender
                    "is_typing": is_typing,
                    "is_self": False
                }
            ))


async def broadcast_presence_update(license_id: int, is_online: bool, last_seen: Optional[str] = None):
    """Broadcast user presence update to self and peers"""
    manager = get_websocket_manager()
    
    from db_helper import get_db, fetch_one, fetch_all
    async with get_db() as db:
        # 1. Get this user's username
        user_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
        if not user_row or not user_row.get("username"):
            # If no username, we can only notify self (multi-device)
            await manager.send_to_license(license_id, WebSocketMessage(
                event="presence_update",
                data={
                    "is_online": is_online,
                    "last_seen": last_seen,
                    "is_self": True
                }
            ))
            return

        username = user_row["username"]
        
        # 2. Find all licenses who are chatting with this user in 'almudeer' channel
        peers = await fetch_all(db, "SELECT DISTINCT license_key_id FROM inbox_conversations WHERE sender_contact = ? AND channel = 'almudeer'", [username])
    
    # 3. Broadcast to self (multi-device sync)
    await manager.send_to_license(license_id, WebSocketMessage(
        event="presence_update",
        data={
            "is_online": is_online,
            "last_seen": last_seen,
            "is_self": True
        }
    ))

    # 4. Broadcast to peers so they see the status update in their chat view
    for peer in peers:
        peer_license_id = peer["license_key_id"]
        await manager.send_to_license(peer_license_id, WebSocketMessage(
            event="presence_update",
            data={
                "sender_contact": username,
                "is_online": is_online,
                "last_seen": last_seen,
                "is_self": False
            }
        ))


async def broadcast_recording_indicator(license_id: int, sender_contact: str, is_recording: bool):
    """Broadcast recording indicator for a specific conversation to self and internal peers"""
    manager = get_websocket_manager()
    
    # 1. Broadcast to self (multi-device sync)
    await manager.send_to_license(license_id, WebSocketMessage(
        event="recording_indicator",
        data={
            "sender_contact": sender_contact,
            "is_recording": is_recording,
            "is_self": True
        }
    ))

    # 2. Check if peer is an internal almudeer user and notify them
    from db_helper import get_db, fetch_one
    async with get_db() as db:
        # Get this user's username
        user_row = await fetch_one(db, "SELECT username FROM license_keys WHERE id = ?", [license_id])
        if not user_row or not user_row.get("username"):
            return

        username = user_row["username"]
        
        # Check if the sender_contact is an internal user
        peer_row = await fetch_one(db, "SELECT id FROM license_keys WHERE username = ?", [sender_contact])
        if peer_row:
            peer_license_id = peer_row["id"]
            await manager.send_to_license(peer_license_id, WebSocketMessage(
                event="recording_indicator",
                data={
                    "sender_contact": username,
                    "is_recording": is_recording,
                    "is_self": False
                }
            ))


async def broadcast_message_status_update(license_id: int, status_data: Dict[str, Any]):
    """
    Broadcast message delivery status update.
    Expected data: {outbox_id, inbox_message_id, platform_message_id, status, timestamp}
    """
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="delivery_status",
        data=status_data
    ))


async def broadcast_task_typing_indicator(license_id: int, task_id: str, user_id: str, user_name: str, is_typing: bool):
    """
    Broadcast task typing indicator to all users in the license.
    """
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="task_typing",
        data={
            "task_id": task_id,
            "user_id": user_id,
            "user_name": user_name,
            "is_typing": is_typing,
            "timestamp": datetime.utcnow().isoformat()
        }
    ))


async def broadcast_task_sync(license_id: int, task_id: Optional[str] = None, change_type: str = "update"):
    """
    Broadcast a signal to all devices to trigger a task synchronization.
    Optionally includes a task_id for targeted sync.
    """
    manager = get_websocket_manager()
    await manager.send_to_license(license_id, WebSocketMessage(
        event="task_sync",
        data={
            "timestamp": datetime.utcnow().isoformat(),
            "task_id": task_id,
            "change_type": change_type
        }
    ))


async def broadcast_global_sync(event_name: str):
    """
    Broadcast a signal to all connected clients across all licenses.
    Used for global assets like global tasks and global library items.
    """
    manager = get_websocket_manager()
    
    # We want to send this to all active connections
    # The manager has a broadcast method for this
    await manager.broadcast(WebSocketMessage(
        event=event_name,
        data={"timestamp": datetime.utcnow().isoformat(), "global": True}
    ))
