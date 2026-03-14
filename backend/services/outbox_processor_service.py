"""
Al-Mudeer - Outbox Processor Service

Persistent background service that listens to Redis outbox_trigger channel
and processes approved outbox messages for all channels:
- WhatsApp
- Telegram (Bot & Phone)
- Almudeer (internal)
"""

import asyncio
import logging
from typing import Optional

from logging_config import get_logger

logger = get_logger(__name__)


class OutboxProcessorService:
    """
    Persistent service that processes outbox messages.
    
    Listens to Redis pub/sub channel for outbox triggers and processes
    approved messages for all supported channels.
    """
    
    OUTBOX_TRIGGER_CHANNEL = "almudeer:outbox_trigger"
    
    def __init__(self):
        self._running = False
        self._listener_task: Optional[asyncio.Task] = None
        self._redis_mgr = None
        self._processing_lock = asyncio.Lock()
        
    async def start(self):
        """Start the outbox processor service."""
        if self._running:
            logger.warning("OutboxProcessorService already running")
            return
            
        logger.info("Starting OutboxProcessorService...")
        self._running = True
        
        # Initialize Redis manager
        from services.websocket_manager import RedisPubSubManager
        self._redis_mgr = RedisPubSubManager()
        
        if not await self._redis_mgr.initialize():
            logger.error("Failed to initialize Redis for OutboxProcessorService")
            self._running = False
            return
        
        # Subscribe to outbox trigger channel
        await self._redis_mgr.subscribe_system(self._handle_outbox_trigger)
        logger.info("OutboxProcessorService started and listening for triggers")
        
    async def stop(self):
        """Stop the outbox processor service."""
        if not self._running:
            return
            
        logger.info("Stopping OutboxProcessorService...")
        self._running = False
        
        if self._listener_task:
            self._listener_task.cancel()
            try:
                await self._listener_task
            except asyncio.CancelledError:
                pass
        
        if self._redis_mgr:
            await self._redis_mgr.close()
            
        logger.info("OutboxProcessorService stopped")
        
    async def _handle_outbox_trigger(self, data):
        """
        Handle outbox trigger from Redis.

        Args:
            data: License ID as string from Redis message
        """
        if not self._running:
            logger.warning(f"OutboxProcessorService not running, ignoring trigger for {data}")
            return

        try:
            license_id = int(data)
            logger.info(f"Received outbox trigger for license {license_id}")

            # Process outbox messages for this license
            await self._process_outbox_messages(license_id)

        except (ValueError, TypeError) as e:
            logger.error(f"Invalid outbox trigger data: {data} - {e}")
        except Exception as e:
            logger.error(f"Error processing outbox trigger: {e}", exc_info=True)
    
    async def _process_outbox_messages(self, license_id: int, skip_lock: bool = False):
        """
        Process all approved outbox messages for a license.

        Args:
            license_id: The license ID to process messages for
            skip_lock: If True, don't acquire the lock (caller already holds it)
        """
        logger.info(f"[_process_outbox_messages] Starting for license {license_id}")
        
        # Use a context manager that can be skipped
        if skip_lock:
            logger.info(f"[_process_outbox_messages] Skipping lock (caller holds it) for license {license_id}")
            await self._do_process_outbox_messages(license_id)
        else:
            async with self._processing_lock:
                logger.info(f"[_process_outbox_messages] Acquired lock for license {license_id}")
                await self._do_process_outbox_messages(license_id)

    async def _do_process_outbox_messages(self, license_id: int):
        """Internal method that actually processes messages (no lock acquisition)."""
        try:
            from models.inbox import get_pending_outbox
            from services.message_sender import send_outbox_message

            # Get all pending/approved messages
            logger.info(f"[_process_outbox_messages] Calling get_pending_outbox for license {license_id}")
            messages = await get_pending_outbox(license_id)
            logger.info(f"[_process_outbox_messages] Got {len(messages)} messages for license {license_id}")

            if not messages:
                logger.info(f"No pending outbox messages for license {license_id}")
                return

            logger.info(f"Processing {len(messages)} outbox message(s) for license {license_id}")

            # Process each message
            for message in messages:
                if not self._running:
                    logger.warning("OutboxProcessorService stopped while processing")
                    break

                outbox_id = message["id"]
                status = message.get("status", "pending")

                # Only process approved messages
                # (pending messages will be approved by chat_routes before trigger is published)
                if status != "approved":
                    logger.info(f"Skipping outbox {outbox_id} with status {status} (not approved yet)")
                    continue

                try:
                    logger.info(f"Sending outbox message {outbox_id} via {message.get('channel')}")
                    await send_outbox_message(outbox_id, license_id)
                except Exception as e:
                    logger.error(f"Failed to send outbox message {outbox_id}: {e}", exc_info=True)
                    # send_outbox_message already marks as failed internally

        except Exception as e:
            logger.error(f"Error in _process_outbox_messages for license {license_id}: {e}", exc_info=True)
            raise  # Re-raise to see the error in process_all_pending
    
    async def process_all_pending(self):
        """
        Process all pending outbox messages across all licenses.

        Useful for:
        - Initial startup processing (catch up on messages while service was down)
        - Manual trigger for debugging
        """
        try:
            from db_helper import fetch_all, get_db

            async with self._processing_lock:
                # Get all licenses with pending/approved outbox messages
                async with get_db() as db:
                    licenses = await fetch_all(
                        db,
                        """
                        SELECT DISTINCT license_key_id
                        FROM outbox_messages
                        WHERE status IN ('pending', 'approved')
                        AND deleted_at IS NULL
                        """
                    )

                if not licenses:
                    logger.debug("No pending outbox messages to process")
                    return

                logger.info(f"Found {len(licenses)} license(s) with pending outbox messages")

                for lic in licenses:
                    if not self._running:
                        break
                    # Pass skip_lock=True because we already hold the lock
                    await self._process_outbox_messages(lic["license_key_id"], skip_lock=True)

        except Exception as e:
            logger.error(f"Error in process_all_pending: {e}", exc_info=True)
    
    @property
    def is_running(self) -> bool:
        """Check if the service is running."""
        return self._running


# Global instance for use in main.py
_outbox_processor: Optional[OutboxProcessorService] = None


def get_outbox_processor() -> Optional[OutboxProcessorService]:
    """Get the global outbox processor instance."""
    return _outbox_processor


async def start_outbox_processor():
    """Start the global outbox processor service."""
    global _outbox_processor
    
    if _outbox_processor and _outbox_processor.is_running:
        logger.warning("Outbox processor already running")
        return _outbox_processor
    
    _outbox_processor = OutboxProcessorService()
    await _outbox_processor.start()
    return _outbox_processor


async def stop_outbox_processor():
    """Stop the global outbox processor service."""
    global _outbox_processor
    
    if _outbox_processor:
        await _outbox_processor.stop()
        _outbox_processor = None
