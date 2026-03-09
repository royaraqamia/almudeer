"""
Al-Mudeer - Historical Backfill Service
Orchestrates fetching historical messages and gradual reveal in inbox
"""

import asyncio
import os
import json
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any

from logging_config import get_logger
from models.backfill_queue import (
    add_to_backfill_queue,
    get_next_pending_reveal,
    mark_as_revealed,
    mark_as_failed,
    get_backfill_queue_count,
    has_pending_backfill,
    BACKFILL_REVEAL_INTERVAL_SECONDS,
    BACKFILL_DAYS,
)
from models.inbox import save_inbox_message

logger = get_logger(__name__)


class HistoricalBackfillService:
    """
    Manages historical chat backfill with rate-limit awareness.
    
    Key Features:
    1. Fetches up to 30 days of messages when a channel is first linked
    2. Queues messages for gradual reveal (10-minute intervals by default)
    3. Respects existing rate limits - does NOT bypass them
    4. Skips channels that already have backfill in progress
    
    IMPORTANT: This service does NOT call AI directly. It only moves messages
    to the inbox. The existing workers.py handles AI processing with its
    built-in rate limiting.
    """
    
    def __init__(self):
        self.reveal_interval = BACKFILL_REVEAL_INTERVAL_SECONDS
        self.backfill_days = BACKFILL_DAYS
    
    async def should_trigger_backfill(self, license_id: int, channel: str) -> bool:
        """
        Check if backfill should be triggered for a license/channel.
        
        Returns True only if:
        1. No existing backfill entries exist for this channel
        2. This is effectively a "first time" connection
        """
        count = await get_backfill_queue_count(license_id, channel)
        return count == 0
    
    async def schedule_historical_messages(
        self,
        license_id: int,
        channel: str,
        messages: List[Dict[str, Any]]
    ) -> int:
        """
        Schedule a list of historical messages for gradual reveal.
        """
        if not messages:
            return 0
        
        # Sort by received_at (oldest first) so they appear in chronological order
        sorted_messages = sorted(
            messages,
            key=lambda m: m.get("received_at") or datetime.min
        )
        
        queued_count = 0
        base_time = datetime.utcnow()
        
        for i, msg in enumerate(sorted_messages):
            scheduled_at = base_time + timedelta(seconds=self.reveal_interval * (i + 1))
            
            queue_id = await add_to_backfill_queue(
                license_id=license_id,
                channel=channel,
                body=msg.get("body", ""),
                scheduled_reveal_at=scheduled_at,
                channel_message_id=msg.get("channel_message_id"),
                sender_contact=msg.get("sender_contact"),
                sender_name=msg.get("sender_name"),
                sender_id=msg.get("sender_id"),
                subject=msg.get("subject"),
                received_at=msg.get("received_at"),
                attachments=msg.get("attachments"),
                is_forwarded=msg.get("is_forwarded", False)
            )
            
            if queue_id:
                queued_count += 1
        
        if queued_count > 0:
            total_hours = (queued_count * self.reveal_interval) / 3600
            logger.info(
                f"Scheduled {queued_count} historical messages for license {license_id} "
                f"channel {channel}. Estimated completion: {total_hours:.1f} hours"
            )
        
        return queued_count
    
    async def process_pending_reveals(self, license_id: Optional[int] = None) -> int:
        """
        Process any pending reveals that are due (scheduled_reveal_at <= now).
        """
        # Get next pending reveal
        pending = await get_next_pending_reveal(license_id)
        
        if not pending:
            return 0
        
        queue_id = pending.get("id")
        
        try:
            # Parse attachments from JSON string if present
            attachments = []
            if pending.get("attachments"):
                try:
                    attachments_str = pending.get("attachments")
                    if isinstance(attachments_str, str):
                        attachments = json.loads(attachments_str)
                except Exception as e:
                    logger.warning(f"Failed to parse attachments for backfill {queue_id}: {e}")
            
            # Move to inbox
            inbox_id = await save_inbox_message(
                license_id=pending["license_key_id"],
                channel=pending["channel"],
                body=pending["body"],
                sender_name=pending.get("sender_name"),
                sender_contact=pending.get("sender_contact"),
                sender_id=pending.get("sender_id"),
                subject=pending.get("subject"),
                channel_message_id=pending.get("channel_message_id"),
                received_at=pending.get("received_at"),
                attachments=attachments if attachments else None,
                is_forwarded=pending.get("is_forwarded", False)
            )
            
            if inbox_id:
                await mark_as_revealed(queue_id, inbox_id)
                logger.info(
                    f"Revealed backfill message {queue_id} -> inbox {inbox_id} "
                    f"for license {pending['license_key_id']}"
                )
                return 1
            else:
                # save_inbox_message might return None if duplicate
                await mark_as_revealed(queue_id)
                logger.debug(f"Backfill message {queue_id} was duplicate, marked as revealed")
                return 0
                
        except Exception as e:
            logger.error(f"Error revealing backfill message {queue_id}: {e}")
            await mark_as_failed(queue_id, str(e))
            return 0


# Global service instance
_backfill_service: Optional[HistoricalBackfillService] = None


def get_backfill_service() -> HistoricalBackfillService:
    """Get or create the global backfill service instance."""
    global _backfill_service
    if _backfill_service is None:
        _backfill_service = HistoricalBackfillService()
    return _backfill_service
