"""Al-Mudeer - Inbox/Outbox Models
Unified message inbox and outbox management
"""

import asyncio
import hashlib
import json
import os
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Any
from collections import OrderedDict

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE

# P1-5 FIX: In-memory LRU cache as fallback for Redis deduplication
# This prevents duplicate messages during Redis outages
class LocalDeduplicationCache:
    """Thread-safe LRU cache for message deduplication (fallback when Redis unavailable)"""
    
    def __init__(self, maxsize: int = 10000, ttl_seconds: int = 300):
        self._cache: OrderedDict[str, datetime] = OrderedDict()
        self._maxsize = maxsize
        self._ttl = timedelta(seconds=ttl_seconds)
        self._lock = asyncio.Lock()
    
    async def get(self, key: str) -> bool:
        """Check if key exists and is not expired"""
        async with self._lock:
            if key not in self._cache:
                return False
            
            # Check if expired
            if datetime.utcnow() - self._cache[key] > self._ttl:
                del self._cache[key]
                return False
            
            # Move to end (most recently used)
            self._cache.move_to_end(key)
            return True
    
    async def set(self, key: str):
        """Add key to cache with TTL"""
        async with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
            else:
                if len(self._cache) >= self._maxsize:
                    # Remove oldest (first) item
                    self._cache.popitem(last=False)
                self._cache[key] = datetime.utcnow()

# Global local deduplication cache (P1-5 FIX)
_local_dedup_cache = LocalDeduplicationCache(maxsize=10000, ttl_seconds=300)


async def _check_message_deduplication(license_id: int, channel: str, sender_id: str, body: str, received_at: datetime) -> bool:
    """
    Check if message was already processed using Redis-based deduplication.
    Returns True if message is duplicate (should be skipped), False if new.
    
    P1-5 FIX: Added local in-memory fallback when Redis is unavailable.
    """
    redis_url = os.getenv("REDIS_URL")
    
    # Generate unique message hash
    timestamp_str = received_at.isoformat() if isinstance(received_at, datetime) else str(received_at)
    msg_hash = hashlib.sha256(
        f"{license_id}:{channel}:{sender_id}:{body}:{timestamp_str}".encode()
    ).hexdigest()
    
    # Try Redis first if available
    if redis_url:
        try:
            import redis.asyncio as aioredis
            redis_client = await aioredis.from_url(redis_url, decode_responses=True)

            # Check if hash exists
            key = f"msg_dedup:{msg_hash}"
            exists = await redis_client.exists(key)

            if exists:
                # Duplicate detected
                await redis_client.close()
                return True

            # Set with 5-minute TTL to allow for processing window
            await redis_client.setex(key, 300, "1")
            await redis_client.close()
            return False

        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Redis deduplication failed, using local fallback: {e}")
            # Fall through to local cache
    
    # P1-5 FIX: Use local in-memory cache as fallback
    key = f"msg_dedup:{msg_hash}"
    is_duplicate = await _local_dedup_cache.get(key)
    
    if is_duplicate:
        return True
    
    await _local_dedup_cache.set(key)
    return False


async def save_inbox_message(
    license_id: int,
    channel: str,
    body: str,
    sender_name: str = None,
    sender_contact: str = None,
    sender_id: str = None,
    subject: str = None,
    channel_message_id: str = None,
    received_at: datetime = None,
    attachments: Optional[List[dict]] = None,
    reply_to_platform_id: str = None,
    reply_to_body_preview: str = None,
    reply_to_sender_name: str = None,
    reply_to_id: int = None,
    platform_message_id: str = None,
    platform_status: str = 'received',
    original_sender: str = None,
    status: str = None,
    is_forwarded: bool = False
) -> int:
    """Save incoming message to inbox (SQLite & PostgreSQL compatible)."""

    # Centralized Bot & Spam Protection
    # Prevent saving messages from known bots and promotional senders
    # Added: Calendly, Submagic, IconScout per user request
    blocked_keywords = [
        "bot", "api",
        "no-reply", "noreply", "donotreply",
        "newsletter", "bulletin",
        "calendly", "submagic", "iconscout"
    ]

    def is_blocked(text: str) -> bool:
        if not text: return False
        text_lower = text.lower()
        return any(keyword in text_lower for keyword in blocked_keywords)

    if is_blocked(sender_name) or is_blocked(sender_contact):
        # Return 0 to indicate no message was saved
        return 0
    
    # P0-1: Redis-based deduplication check
    if sender_id and received_at:
        is_duplicate = await _check_message_deduplication(
            license_id, channel, sender_id, body, received_at
        )
        if is_duplicate:
            from logging_config import get_logger
            get_logger(__name__).debug(f"Duplicate message detected: {channel}:{sender_id}:{body[:50]}")
            return 0  # Already processed

    # Normalize received_at to a UTC datetime; asyncpg prefers naive UTC
    if isinstance(received_at, str):
        try:
            received = datetime.fromisoformat(received_at)
        except ValueError:
            received = datetime.utcnow()
    elif isinstance(received_at, datetime):
        received = received_at
    else:
        received = datetime.utcnow()

    if received.tzinfo is not None:
        received = received.astimezone(timezone.utc).replace(tzinfo=None)

    # For PostgreSQL (asyncpg), pass a naive UTC datetime.
    # For SQLite, use ISO string.
    ts_value: Any
    if DB_TYPE == "postgresql":
        ts_value = received
    else:
        ts_value = received.isoformat()

    # Serialize attachments
    import json
    attachments_json = json.dumps(attachments) if attachments else None

    async with get_db() as db:

        # ---------------------------------------------------------
        # Canonical Identity Lookup (Prevent Duplicates)
        # ---------------------------------------------------------
        # If we already know this sender_id (Telegram ID, etc.), use the 
        # EXISTING sender_contact to ensure conversation threading works 
        # even if the new message has a different format (e.g. username vs phone).
        if sender_id and license_id:
            # Check for existing contact for this sender_id
            existing_row = await fetch_one(
                db,
                """
                SELECT sender_contact 
                FROM inbox_messages 
                WHERE license_key_id = ? AND sender_id = ? 
                AND sender_contact IS NOT NULL AND sender_contact != ''
                LIMIT 1
                """,
                [license_id, sender_id]
            )
            
            if existing_row and existing_row['sender_contact']:
                canonical_contact = existing_row['sender_contact']
                # If incoming contact differs (e.g. is 'username' but we have '+phone'), use canonical
                if sender_contact != canonical_contact:
                    sender_contact = canonical_contact

        # Stringify received_at for SQLite to avoid type mismatches
        reg_received_at = received_at or datetime.utcnow()
        if DB_TYPE != "postgresql" and isinstance(reg_received_at, datetime):
            reg_received_at = reg_received_at.isoformat()

        # ---------------------------------------------------------
        # Reply Context Resolution (Internal Resolution)
        # ---------------------------------------------------------
        if reply_to_platform_id and (not reply_to_body_preview or not reply_to_sender_name):
            # 1. Look for the parent in inbox_messages (replied to a user message)
            parent_inbox = await fetch_one(
                db,
                "SELECT id, body, sender_name FROM inbox_messages WHERE license_key_id = ? AND channel_message_id = ?",
                [license_id, reply_to_platform_id]
            )
            if parent_inbox:
                reply_to_id = reply_to_id or parent_inbox["id"]
                reply_to_body_preview = reply_to_body_preview or parent_inbox["body"][:100]
                reply_to_sender_name = reply_to_sender_name or parent_inbox["sender_name"]
            else:
                # 2. Look for the parent in outbox_messages (replied to an Al-Mudeer message)
                parent_outbox = await fetch_one(
                    db,
                    "SELECT body FROM outbox_messages WHERE license_key_id = ? AND platform_message_id = ?",
                    [license_id, reply_to_platform_id]
                )
                if parent_outbox:
                    reply_to_body_preview = reply_to_body_preview or parent_outbox["body"][:100]
                    reply_to_sender_name = reply_to_sender_name or "أنا" # "Me" in Arabic, or Al-Mudeer

        await execute_sql(
            db,
            """
            INSERT INTO inbox_messages 
                (license_key_id, channel, channel_message_id, sender_id, sender_name,
                 sender_contact, subject, body, received_at, attachments,
                 reply_to_platform_id, reply_to_body_preview, reply_to_sender_name,
                 reply_to_id, platform_message_id, platform_status, original_sender, status, is_forwarded)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                license_id,
                channel,
                channel_message_id,
                sender_id,
                sender_name,
                sender_contact,
                subject,
                body,
                reg_received_at,
                attachments_json,
                reply_to_platform_id,
                reply_to_body_preview,
                reply_to_sender_name,
                reply_to_id,
                platform_message_id,
                platform_status,
                original_sender,
                status or 'analyzed',
                is_forwarded
            ],
        )

        # Fetch the last inserted id in a DB-agnostic way
        row = await fetch_one(
            db,
            """
            SELECT id FROM inbox_messages
            WHERE license_key_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            [license_id],
        )
        await commit_db(db)
        
        message_id = row["id"] if row else 0
        
        
        if message_id:
            # ---------------------------------------------------------
            # Real-time Broadcast (WebSocket) - P0-2: Reliable Broadcast
            # ---------------------------------------------------------
            # This enables WhatsApp/Telegram-like instant message appearance in the mobile app.
            # Moved from update_inbox_analysis to ensure direct flow works.
            try:
                # 1. Update conversation state (recalculates unread count)
                await upsert_conversation_state(license_id, sender_contact, sender_name, channel)

                # 2. Fetch updated authoritative unread count
                conv_row = await fetch_one(
                    db,
                    "SELECT unread_count FROM inbox_conversations WHERE license_key_id = ? AND sender_contact = ?",
                    [license_id, sender_contact]
                )
                unread_count = conv_row["unread_count"] if conv_row else 0

                # 3. P0-2: Use reliable broadcast with retry mechanism
                from services.reliable_broadcast import broadcast_new_message_reliable
                # Fire-and-forget - don't block on broadcast
                asyncio.create_task(broadcast_new_message_reliable(
                    license_id,
                    {
                        "id": message_id,
                        "sender_contact": sender_contact,
                        "sender_name": sender_name,
                        "body": body,
                        "channel": channel,
                        "timestamp": datetime.utcnow().isoformat(),
                        "status": status or 'analyzed',
                        "direction": "incoming",
                        "unread_count": unread_count,
                        "is_forwarded": bool(is_forwarded),
                        "attachments": attachments,
                        "sequence": None,  # Will be set by reliable broadcast service
                    }
                ))
            except Exception as e:
                from logging_config import get_logger
                get_logger(__name__).warning(f"WebSocket broadcast or state update failed in save_inbox_message: {e}")

        return message_id


async def get_inbox_messages(
    license_id: int,
    status: str = None,
    channel: str = None,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """
    Get inbox messages for a license with pagination (SQLite & PostgreSQL compatible).
    Show all messages immediately (AI analysis discarded).
    """
    # Also exclude soft-deleted messages
    query = "SELECT * FROM inbox_messages WHERE license_key_id = ? AND deleted_at IS NULL"
    params = [license_id]

    if channel:
        query += " AND channel = ?"
        params.append(channel)

    query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params.append(limit)
    params.append(offset)

    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        return [_parse_message_row(row) for row in rows]


async def get_inbox_message_by_id(message_id: int, license_id: int) -> Optional[dict]:
    """Get a single inbox message by ID (efficient direct lookup)."""
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT * FROM inbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        return _parse_message_row(row)



async def get_inbox_messages_count(
    license_id: int,
    status: str = None,
    channel: str = None
) -> int:
    """
    Get total count of inbox messages for pagination.
    
    NOTE: Excludes 'pending' status messages from count.
    """
    
    # Exclude 'pending' status - only count messages after AI responds
    # Also exclude soft-deleted messages
    query = "SELECT COUNT(*) as count FROM inbox_messages WHERE license_key_id = ? AND deleted_at IS NULL"
    params = [license_id]

    if status:
        query += " AND status = ?"
        params.append(status)

    if channel:
        query += " AND channel = ?"
        params.append(channel)

    async with get_db() as db:
        row = await fetch_one(db, query, params)
        return row["count"] if row else 0


async def update_inbox_status(message_id: int, status: str):
    """Update inbox message status (DB agnostic)."""
    async with get_db() as db:
        await execute_sql(
            db,
            "UPDATE inbox_messages SET status = ? WHERE id = ?",
            [status, message_id],
        )
        await commit_db(db)


# ============ Outbox Functions ============

async def create_outbox_message(
    inbox_message_id: int,
    license_id: int,
    channel: str,
    body: str,
    recipient_id: str = None,
    recipient_email: str = None,
    subject: str = None,
    attachments: Optional[List[dict]] = None,
    reply_to_platform_id: Optional[str] = None,
    reply_to_body_preview: Optional[str] = None,
    reply_to_id: Optional[int] = None,
    reply_to_sender_name: Optional[str] = None,
    is_forwarded: bool = False
) -> int:
    """Create outbox message for approval (DB agnostic)."""
    
    # Serialize attachments
    import json
    attachments_json = json.dumps(attachments) if attachments else None
    
    async with get_db() as db:

        await execute_sql(
            db,
            """
            INSERT INTO outbox_messages 
                (inbox_message_id, license_key_id, channel, recipient_id,
                 recipient_email, subject, body, attachments,
                 reply_to_platform_id, reply_to_body_preview, reply_to_id, 
                 reply_to_sender_name, is_forwarded)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                inbox_message_id, license_id, channel, recipient_id, 
                recipient_email, subject, body, attachments_json,
                reply_to_platform_id, reply_to_body_preview, reply_to_id,
                reply_to_sender_name, is_forwarded
            ],
        )

        row = await fetch_one(
            db,
            """
            SELECT id FROM outbox_messages
            WHERE license_key_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            [license_id],
        )
        await commit_db(db)
        return row["id"] if row else 0


async def approve_outbox_message(message_id: int, edited_body: str = None):
    """Approve an outbox message for sending (DB agnostic)."""

    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        # Get message details before update for upsert_conversation_state
        message_row = await fetch_one(db, "SELECT license_key_id, inbox_message_id FROM outbox_messages WHERE id = ?", [message_id])
        
        if edited_body:
            await execute_sql(
                db,
                """
                UPDATE outbox_messages SET
                    body = ?, status = 'approved', approved_at = ?
                WHERE id = ?
                """,
                [edited_body, ts_value, message_id],
            )
        else:
            await execute_sql(
                db,
                """
                UPDATE outbox_messages SET
                    status = 'approved', approved_at = ?
                WHERE id = ?
                """,
                [ts_value, message_id],
            )
        await commit_db(db)

        if message_row:
            sender_contact = None
            if message_row["inbox_message_id"]:
                # Fetch sender_contact from the original inbox message
                inbox_msg = await fetch_one(db, "SELECT sender_contact FROM inbox_messages WHERE id = ?", [message_row["inbox_message_id"]])
                if inbox_msg:
                    sender_contact = inbox_msg["sender_contact"]
            else:
                # Fresh outgoing message, use recipient info as the conversation key
                outbox_msg = await fetch_one(db, "SELECT recipient_email, recipient_id FROM outbox_messages WHERE id = ?", [message_id])
                if outbox_msg:
                    sender_contact = outbox_msg["recipient_email"] or outbox_msg["recipient_id"]

            if sender_contact:
                await upsert_conversation_state(message_row["license_key_id"], sender_contact)

        # FIX P0-2: Broadcast initial "pending" status for optimistic UI
        # Final "sent" or "failed" status will be broadcast by mark_outbox_sent/mark_outbox_failed
        try:
            from services.websocket_manager import broadcast_message_status_update

            if message_row:
                lic_id = message_row["license_key_id"]
                msg_data = await fetch_one(db, "SELECT * FROM outbox_messages WHERE id = ?", [message_id])
                if msg_data:
                    import json
                    attachments = []
                    if msg_data.get("attachments") and isinstance(msg_data["attachments"], str):
                        try:
                            attachments = json.loads(msg_data["attachments"])
                        except: pass

                    evt_data = {
                        "id": msg_data["id"],
                        "outbox_id": msg_data["id"],
                        "channel": msg_data["channel"],
                        "sender_contact": msg_data.get("recipient_email") or msg_data.get("recipient_id"),
                        "sender_name": None,
                        "body": msg_data["body"],
                        "status": "pending",  # Use "pending" instead of "sending"
                        "direction": "outgoing",
                        "timestamp": ts_value.isoformat() if hasattr(ts_value, 'isoformat') else str(ts_value),
                        "attachments": attachments,
                        "is_forwarded": bool(msg_data.get("is_forwarded", False))
                    }
                    await broadcast_message_status_update(lic_id, evt_data)
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in approve_outbox: {e}")


async def mark_outbox_failed(message_id: int, error_message: str = None):
    """Mark outbox message as failed (DB agnostic)."""

    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        # Get message details before update for upsert_conversation_state
        message_row = await fetch_one(db, "SELECT license_key_id, inbox_message_id FROM outbox_messages WHERE id = ?", [message_id])

        await execute_sql(
            db,
            """
            UPDATE outbox_messages SET
                status = 'failed', failed_at = ?, error_message = ?
            WHERE id = ?
            """,
            [ts_value, error_message, message_id],
        )
        await commit_db(db)

        if message_row:
            sender_contact = None
            if message_row["inbox_message_id"]:
                # Fetch sender_contact from the original inbox message
                inbox_msg = await fetch_one(db, "SELECT sender_contact FROM inbox_messages WHERE id = ?", [message_row["inbox_message_id"]])
                if inbox_msg:
                    sender_contact = inbox_msg["sender_contact"]
            else:
                # Fresh outgoing message, use recipient info as the conversation key
                outbox_msg = await fetch_one(db, "SELECT recipient_email, recipient_id FROM outbox_messages WHERE id = ?", [message_id])
                if outbox_msg:
                    sender_contact = outbox_msg["recipient_email"] or outbox_msg["recipient_id"]
            
            if sender_contact:
                await upsert_conversation_state(message_row["license_key_id"], sender_contact)

        # Broadcast status update
        try:
            from services.websocket_manager import broadcast_message_status_update
            if message_row:
                lic_id = message_row["license_key_id"]
                await broadcast_message_status_update(lic_id, {
                    "outbox_id": message_id,
                    "status": "failed",
                    "error": error_message,
                    "timestamp": ts_value.isoformat() if hasattr(ts_value, 'isoformat') else str(ts_value)
                })
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in mark_failed: {e}")


async def mark_outbox_sent(message_id: int):
    """Mark outbox message as sent (DB agnostic)."""

    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    async with get_db() as db:
        # Get message details before update for upsert_conversation_state
        message_row = await fetch_one(db, "SELECT license_key_id, inbox_message_id FROM outbox_messages WHERE id = ?", [message_id])

        await execute_sql(
            db,
            """
            UPDATE outbox_messages SET
                status = 'sent', sent_at = ?
            WHERE id = ?
            """,
            [ts_value, message_id],
        )
        await commit_db(db)

        if message_row:
            sender_contact = None
            if message_row["inbox_message_id"]:
                # Fetch sender_contact from the original inbox message
                inbox_msg = await fetch_one(db, "SELECT sender_contact FROM inbox_messages WHERE id = ?", [message_row["inbox_message_id"]])
                if inbox_msg:
                    sender_contact = inbox_msg["sender_contact"]
            else:
                # Fresh outgoing message, use recipient info as the conversation key
                outbox_msg = await fetch_one(db, "SELECT recipient_email, recipient_id FROM outbox_messages WHERE id = ?", [message_id])
                if outbox_msg:
                    sender_contact = outbox_msg["recipient_email"] or outbox_msg["recipient_id"]
            
            if sender_contact:
                await upsert_conversation_state(message_row["license_key_id"], sender_contact)

        # Broadcast status update
        try:
            from services.websocket_manager import broadcast_message_status_update
            if message_row:
                lic_id = message_row["license_key_id"]
                # Get sender_contact for the broadcast (needed by mobile app to match message)
                sender_contact = None
                if message_row.get("inbox_message_id"):
                    inbox_msg = await fetch_one(db, "SELECT sender_contact FROM inbox_messages WHERE id = ?", [message_row["inbox_message_id"]])
                    if inbox_msg:
                        sender_contact = inbox_msg["sender_contact"]
                else:
                    outbox_msg = await fetch_one(db, "SELECT recipient_email, recipient_id FROM outbox_messages WHERE id = ?", [message_id])
                    if outbox_msg:
                        sender_contact = outbox_msg["recipient_email"] or outbox_msg["recipient_id"]
                
                await broadcast_message_status_update(lic_id, {
                    "outbox_id": message_id,
                    "status": "sent",
                    "timestamp": ts_value.isoformat() if hasattr(ts_value, 'isoformat') else str(ts_value),
                    "sender_contact": sender_contact
                })
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in mark_sent: {e}")


async def get_pending_outbox(license_id: int) -> List[dict]:
    """Get pending outbox messages (DB agnostic)."""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT o.*, i.sender_name, i.body as original_message
            FROM outbox_messages o
            LEFT JOIN inbox_messages i ON o.inbox_message_id = i.id
            WHERE o.license_key_id = ? AND o.status IN ('pending', 'approved')
            ORDER BY o.created_at DESC
            """,
            [license_id],
        )
        return rows


async def get_inbox_conversations(
    license_id: int,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """
    Get inbox conversations using the optimized `inbox_conversations` table.
    This is O(1) per page instead of O(N) full scan.
    All chats appear in unified list - no filters.
    """
    params = [license_id]
    where_clauses = ["ic.license_key_id = ?"]

    # Filters removed - all chats appear in unified list
    where_sql = " AND ".join(where_clauses)
    
    query = f"""
        SELECT 
            ic.sender_contact, ic.sender_name, ic.channel,
            ic.last_message_id as id,
            last_message_body as body,
            last_message_ai_summary as ai_summary,
            last_message_at as created_at,
            last_message_attachments as attachments,
            ic.status,
            unread_count,
            message_count,
            lk.last_seen_at,
            lk.id as peer_license_id
        FROM inbox_conversations ic
        LEFT JOIN license_keys lk ON ic.sender_contact = lk.username AND ic.channel = 'almudeer'
        WHERE {where_sql}
        ORDER BY ic.last_message_at DESC
        LIMIT ? OFFSET ?
    """
    params.extend([limit, offset])
    
    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        conversations = [_parse_message_row(dict(row)) for row in rows]
        
        # Ensure last_seen_at datetime is serialized as ISO string (PostgreSQL returns datetime objects)
        for c in conversations:
            if c.get("last_seen_at") and hasattr(c["last_seen_at"], "isoformat"):
                c["last_seen_at"] = c["last_seen_at"].isoformat()
        
        # Add online status from Redis
        from services.websocket_manager import get_websocket_manager
        manager = get_websocket_manager()
        
        if manager.redis_enabled and conversations:
            try:
                redis = manager.redis_client
                # Filter for conversations that have a peer_license_id (channel='almudeer')
                peer_ids = [c["peer_license_id"] for c in conversations if c.get("peer_license_id")]
                
                if peer_ids:
                    # MGET all counts
                    keys = [f"almudeer:presence:count:{pid}" for pid in peer_ids]
                    counts = await redis.mget(keys)
                    
                    # Create a mapping
                    status_map = {}
                    for pid, count in zip(peer_ids, counts):
                        status_map[pid] = int(count) > 0 if count else False
                        
                    # Apply to conversations
                    for c in conversations:
                        pid = c.get("peer_license_id")
                        if pid:
                            c["is_online"] = status_map.get(pid, False)
                        else:
                            c["is_online"] = False
            except Exception as e:
                from logging_config import get_logger
                get_logger(__name__).warning(f"Failed to fetch online status from Redis: {e}")
                for c in conversations:
                    c["is_online"] = False
        else:
            # Fallback for no Redis
            for c in conversations:
                c["is_online"] = False
                
        return conversations


async def get_conversations_delta(
    license_id: int,
    since: datetime,
    limit: int = 50
) -> List[dict]:
    """
    Get conversations updated since a specific timestamp (Delta Sync).
    """
    # For SQLite compatibility with ISO strings
    ts_value = since if DB_TYPE == "postgresql" else since.isoformat()

    query = """
        SELECT 
            ic.id,
            ic.sender_contact, ic.sender_name, ic.channel,
            last_message_body as body,
            last_message_ai_summary as ai_summary,
            last_message_at as created_at,
            last_message_attachments as attachments,
            ic.status,
            unread_count,
            message_count
        FROM inbox_conversations ic
        WHERE license_key_id = ? 
          AND last_message_at > ?
        ORDER BY ic.last_message_at DESC
        LIMIT ?
    """
    params = [license_id, ts_value, limit]
    
    async with get_db() as db:
        rows = await fetch_all(db, query, params)
        return [_parse_message_row(dict(row)) for row in rows]


async def get_inbox_conversations_count(
    license_id: int
) -> int:
    """
    Get total number of unique conversations (senders).
    Uses the optimized inbox_conversations table.
    No filters - all chats counted.
    """
    query = "SELECT COUNT(*) as count FROM inbox_conversations WHERE license_key_id = ?"
    params = [license_id]

    async with get_db() as db:
        row = await fetch_one(db, query, params)
        return row["count"] if row else 0


async def get_inbox_status_counts(license_id: int) -> dict:
    """Get counts using the optimized inbox_conversations table."""
    async with get_db() as db:
        # We count ALL CONVERSATIONS since we are unifying the inbox
        # status IN ('analyzed', 'sent', 'ignored', 'approved', 'auto_replied')
        # Basically anything not 'pending'
        
        analyzed_row = await fetch_one(db, """
            SELECT COUNT(*) as count FROM inbox_conversations 
            WHERE license_key_id = ?
        """, [license_id])
        
        return {
            "analyzed": analyzed_row["count"] if analyzed_row else 0,
            "sent": 0,
            "ignored": 0
        }


async def _get_sender_aliases(db, license_id: int, sender_contact: str) -> tuple:
    """
    Get all sender_contact and sender_id variants for a given sender.
    P1-3: Optimized with early termination and UNION ALL for performance.
    """
    if not sender_contact:
        return set(), set()

    check_ids = [sender_contact]
    if sender_contact.startswith("tg:"):
        check_ids.append(sender_contact[3:])

    # Track results
    all_contacts = set([sender_contact])
    all_ids = set()
    for cid in check_ids:
        if cid.isdigit(): all_ids.add(cid)

    placeholders = ", ".join(["?" for _ in check_ids])

    # 1. First Pass: Strict match with LIMIT for early termination (P1-3)
    # Note: Use subqueries to apply LIMIT to each part of UNION ALL
    query = f"""
        SELECT sender_contact, sender_id FROM (
            SELECT sender_contact, sender_id
            FROM inbox_messages
            WHERE license_key_id = ?
            AND (sender_contact IN ({placeholders}) OR sender_id IN ({placeholders}))
            LIMIT 200
        ) AS inbox_subq
        UNION ALL
        SELECT sender_contact, sender_id FROM (
            SELECT recipient_email as sender_contact, recipient_id as sender_id
            FROM outbox_messages
            WHERE license_key_id = ?
            AND (recipient_email IN ({placeholders}) OR recipient_id IN ({placeholders}))
            LIMIT 200
        ) AS outbox_subq
    """
    params = [license_id] + check_ids + check_ids + [license_id] + check_ids + check_ids
    aliases = await fetch_all(db, query, params)

    # 2. Add found aliases to sets
    for row in aliases:
        if row.get("sender_contact"): all_contacts.add(row["sender_contact"])
        if row.get("sender_id"): all_ids.add(str(row["sender_id"]))

    # 3. P1-3: Early termination - skip LIKE if we already found aliases
    if not all_ids and len(sender_contact) > 5 and len(all_contacts) < 10:
        like_query = """
            SELECT sender_contact, sender_id FROM inbox_messages
            WHERE license_key_id = ? AND sender_contact LIKE ? LIMIT 10
        """
        like_aliases = await fetch_all(db, like_query, [license_id, f"%{sender_contact}%"])
        for row in like_aliases:
            if row.get("sender_contact"): all_contacts.add(row["sender_contact"])
            if row.get("sender_id"): all_ids.add(str(row["sender_id"]))

    # 4. Hop-2 expansion for cross-linked identities (P1-3: Limited to prevent runaway queries)
    if (all_contacts or all_ids) and len(all_contacts) < 100:
        pass2_contacts = list(all_contacts)
        pass2_ids = list(all_ids)
        placeholders_c = ", ".join(["?" for _ in pass2_contacts]) if pass2_contacts else "'__NONE__'"
        placeholders_i = ", ".join(["?" for _ in pass2_ids]) if pass2_ids else "'__NONE__'"
        
        query2 = f"""
            SELECT sender_contact, sender_id FROM inbox_messages 
            WHERE license_key_id = ? AND (sender_contact IN ({placeholders_c}) OR sender_id IN ({placeholders_i}))
            UNION
            SELECT recipient_email as sender_contact, recipient_id as sender_id FROM outbox_messages
            WHERE license_key_id = ? AND (recipient_email IN ({placeholders_c}) OR recipient_id IN ({placeholders_i}))
        """
        params2 = [license_id] + pass2_contacts + pass2_ids + [license_id] + pass2_contacts + pass2_ids
        aliases2 = await fetch_all(db, query2, params2)
        for row in aliases2:
            if row.get("sender_contact"): all_contacts.add(row["sender_contact"])
            if row.get("sender_id"): all_ids.add(str(row["sender_id"]))

    return tuple(all_contacts), tuple(all_ids)


def _parse_message_row(row: dict) -> dict:
    """Helper to parse JSON fields from a database row."""
    if not row:
        return row
    
    import json
    
    # Parse attachments if present and is a string
    attachments = row.get("attachments")
    if isinstance(attachments, str):
        try:
            row["attachments"] = json.loads(attachments)
        except Exception:
            row["attachments"] = []
    
    # Also handle outbox messages if they have attachments
    # (some queries might return both or have different column names)
    
    # Ensure numerical IDs are integers
    for id_col in ["id", "license_key_id", "inbox_message_id", "reply_to_id", "unread_count", "message_count"]:
        if row.get(id_col) is not None:
            try:
                row[id_col] = int(row[id_col])
            except (ValueError, TypeError):
                pass
                
    return row


async def get_conversation_messages(
    license_id: int,
    sender_contact: str,
    limit: int = 50
) -> List[dict]:
    """
    Get all messages from a specific sender (for conversation detail view).
    NOTE: Excludes 'pending' status messages - only shows messages after AI responds.

    Uses comprehensive alias matching to find all messages from the same sender,
    even if stored with different identifier formats (phone, username, ID).
    
    P0-4 FIX: Added fallback when alias matching returns empty results.
    """
    async with get_db() as db:
        # Get all aliases for this sender
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)

        # P0-4 FIX: If no aliases found, use original sender_contact as fallback
        # This prevents empty result sets when sender_contact format is unique
        if not all_contacts and not all_ids:
            all_contacts = {sender_contact} if sender_contact else set()

        # Build comprehensive WHERE clause
        conditions = []
        params = [license_id]

        # Match by sender_contact
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            conditions.append(f"sender_contact IN ({contact_placeholders})")
            params.extend(list(all_contacts))

        # Match by sender_id
        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            conditions.append(f"sender_id IN ({id_placeholders})")
            params.extend(list(all_ids))

        where_clause = " OR ".join(conditions) if conditions else "1=0"
        params.append(limit)

        rows = await fetch_all(
            db,
            f"""
            SELECT *, is_forwarded FROM inbox_messages
            WHERE license_key_id = ?
            AND ({where_clause})
            AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?
            """,
            params
        )
        return [_parse_message_row(dict(row)) for row in rows]


async def get_conversation_messages_cursor(
    license_id: int,
    sender_contact: str,
    limit: int = 25,
    cursor: Optional[str] = None,
    direction: str = "older"  # "older" (scroll up) or "newer" (new messages)
) -> dict:
    """
    Get messages from a specific sender with cursor-based pagination.
    Includes BOTH incoming (inbox) and outgoing (outbox) messages.
    
    Cursor format: "{created_at_iso}_{message_id}"
    
    Uses comprehensive alias matching to find all messages from the same sender/recipient.
    """
    import base64
    
    # Parse cursor if provided
    cursor_created_at = None
    cursor_id = None
    cursor_direction = None
    cursor_table_prefix = None
    cursor_body_hash = None  # P1-4 FIX: Support body hash for edge case tie-breaking
    
    if cursor:
        try:
            # Decode base64 cursor
            decoded = base64.b64decode(cursor).decode('utf-8')
            # P1-4 FIX: New format is "{ts}_{table_prefix}_{id}_{direction}_{body_hash}"
            # Previous format: "{ts}_{table_prefix}_{id}_{direction}"
            # Old format: "{ts}_{id}_{direction}"
            parts = decoded.rsplit('_', 4)  # Split into max 5 parts
            
            if len(parts) >= 3:
                # Parse timestamp to datetime object
                try:
                    cursor_created_at = datetime.fromisoformat(parts[0])
                    # Ensure naive UTC
                    if cursor_created_at.tzinfo is not None:
                        cursor_created_at = cursor_created_at.astimezone(timezone.utc).replace(tzinfo=None)
                except ValueError:
                    cursor_created_at = None

                # Check format version based on number of parts
                if len(parts) == 5:
                    # P1-4 FIX: New format with body hash
                    cursor_table_prefix = parts[1]  # 'i' or 'o'
                    cursor_id = int(parts[2])
                    cursor_direction = parts[3]  # 'i' or 'o'
                    # P0-6 FIX: Keep body_hash as string to prevent overflow
                    # Compare as strings during pagination
                    cursor_body_hash = parts[4]  # Body hash for tie-breaking
                elif len(parts) == 4:
                    # Format with table prefix but no body hash
                    cursor_table_prefix = parts[1]  # 'i' or 'o'
                    cursor_id = int(parts[2])
                    cursor_direction = parts[3]  # 'i' or 'o'
                else:
                    # Old format fallback
                    cursor_id = int(parts[1])
                    cursor_direction = parts[2] if len(parts) == 3 else None

                # If parsing failed, invalidate cursor
                if cursor_created_at is None:
                    cursor_id = None
                    cursor_direction = None
                    cursor_table_prefix = None
                    cursor_body_hash = None

        except Exception:
            pass  # Invalid cursor, start from beginning

    async with get_db() as db:
        # Get all aliases for this sender
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)

        # P0-4 FIX: If no aliases found, use original sender_contact as fallback
        # This prevents empty result sets when sender_contact format is unique
        if not all_contacts and not all_ids:
            all_contacts = {sender_contact} if sender_contact else set()

        # Build params
        params = []

        # --- Inbox Conditions ---
        inbox_conditions = ["i.license_key_id = ?"]
        inbox_params = [license_id]

        in_identifiers = []
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            in_identifiers.append(f"i.sender_contact IN ({contact_placeholders})")
            inbox_params.extend(list(all_contacts))

        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            in_identifiers.append(f"i.sender_id IN ({id_placeholders})")
            inbox_params.extend(list(all_ids))

        in_sender_where = " OR ".join(in_identifiers) if in_identifiers else "1=0"
        inbox_conditions.append(f"({in_sender_where})")
        # No status filter
        inbox_conditions.append("i.deleted_at IS NULL")

        inbox_where = " AND ".join(inbox_conditions)

        # --- Outbox Conditions ---
        outbox_conditions = ["o.license_key_id = ?"]
        outbox_params = [license_id]

        out_identifiers = []
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            out_identifiers.append(f"o.recipient_email IN ({contact_placeholders})")
            outbox_params.extend(list(all_contacts))

        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            out_identifiers.append(f"o.recipient_id IN ({id_placeholders})")
            outbox_params.extend(list(all_ids))

        out_sender_where = " OR ".join(out_identifiers) if out_identifiers else "1=0"
        outbox_conditions.append(f"({out_sender_where})")
        outbox_conditions.append("o.status IN ('approved', 'sent')")
        outbox_conditions.append("o.deleted_at IS NULL")

        outbox_where = " AND ".join(outbox_conditions)
        
        # --- Combined Query ---
        # We need to project common columns:
        # id, channel, body, created_at, received_at/sent_at, direction, status, sender_name
        
        # For inbox: effective_ts = COALESCE(received_at, created_at)
        # For outbox: effective_ts = COALESCE(sent_at, created_at)
        
        full_params = inbox_params + outbox_params
        
        base_query = f"""
            SELECT 
                id, channel, sender_name, sender_contact, sender_id,
                subject, body, 
                attachments,
                status,
                created_at, 
                received_at as timestamp,
                COALESCE(received_at, created_at) as effective_ts,
                'incoming' as direction,
                ai_summary, ai_draft_response,
                reply_to_id, reply_to_platform_id, reply_to_body_preview, reply_to_sender_name,
                is_forwarded,
                NULL as delivery_status,
                NULL as sent_at,
                i.edited_at
            FROM inbox_messages i
            WHERE {inbox_where}
            
            UNION ALL
            
            SELECT 
                id, channel, NULL as sender_name, recipient_email as sender_contact, recipient_id as sender_id,
                subject, body,
                attachments,
                status,
                created_at, 
                sent_at as timestamp,
                COALESCE(sent_at, created_at) as effective_ts,
                'outgoing' as direction,
                NULL as ai_summary, NULL as ai_draft_response,
                NULL as reply_to_id, o.reply_to_platform_id, o.reply_to_body_preview, o.reply_to_sender_name,
                is_forwarded,
                delivery_status,
                sent_at,
                o.edited_at
            FROM outbox_messages o
            WHERE {outbox_where}
        """
        
        # Apply Cursor Filter to the *Results* of the Union?
        # Ideally, we push it down, but for simplicity/correctness with UNION, 
        # wrapping in a CTE or subquery is cleanest for sorting/limits.
        
        if direction == "older":
            # Loading history (scrolling up)
            # Sort DESC (newest to oldest), take top N
            # Filter: effective_ts < cursor OR (effective_ts = cursor AND id < cursor_msg_id) -- Wait, ID collisions possible between tables?
            # Yes, ID collisions possible. We need a unique sort key if IDs collide. 
            # We can use (effective_ts, direction, id) but that's complex.
            # Ideally generate a unique row ID but that's expensive.
            # Let's assume (effective_ts, id) is unique enough or sufficient.
            # To be safe, let's treat ID as not unique across tables.
            pass
        
        # Wrap in subquery to apply order and limit
        final_query = f"""
            SELECT * FROM (
                {base_query}
            ) combined
        """
        
        where_clauses = []
        
        if cursor_created_at and cursor_id:
             # Use a robust tie-breaking filter that handles potential ID collisions between tables
             # by including direction in the cursor if necessary, or just using a strict inequality.
             # 'incoming' sorts before 'outgoing' if same TS and same ID (unlikely but possible).
             d_val = 1 if cursor_direction == 'i' else 2
             
             if direction == "older":
                 # (effective_ts, direction_rank, id) < (cursor_ts, cursor_d_rank, cursor_id)
                 where_clauses.append("""
                    (effective_ts < ?) OR 
                    (effective_ts = ? AND (
                        (CASE WHEN direction = 'incoming' THEN 1 ELSE 2 END < ?) OR
                        (CASE WHEN direction = 'incoming' THEN 1 ELSE 2 END = ? AND id < ?)
                    ))
                 """)
                 full_params.extend([cursor_created_at, cursor_created_at, d_val, d_val, cursor_id])
             else:
                 where_clauses.append("""
                    (effective_ts > ?) OR 
                    (effective_ts = ? AND (
                        (CASE WHEN direction = 'incoming' THEN 1 ELSE 2 END > ?) OR
                        (CASE WHEN direction = 'incoming' THEN 1 ELSE 2 END = ? AND id > ?)
                    ))
                 """)
                 full_params.extend([cursor_created_at, cursor_created_at, d_val, d_val, cursor_id])
                 
        if where_clauses:
            final_query += " WHERE " + " AND ".join(where_clauses)
            
        if direction == "older":
            final_query += " ORDER BY effective_ts DESC, (CASE WHEN direction = 'incoming' THEN 1 ELSE 2 END) DESC, id DESC"
        else:
            final_query += " ORDER BY effective_ts ASC, (CASE WHEN direction = 'incoming' THEN 1 ELSE 2 END) ASC, id ASC"
            
        final_query += " LIMIT ?"
        full_params.append(limit + 1)
        
        rows = await fetch_all(db, final_query, full_params)
        
        # Parsing
        has_more = len(rows) > limit
        result_rows = rows[:limit]
        
        # Parse JSON/Types and standardize
        messages = []
        for row in result_rows:
            msg = dict(row)
            # Parse attachments safely
            import json
            if isinstance(msg.get("attachments"), str):
                try:
                    msg["attachments"] = json.loads(msg["attachments"])
                except:
                    msg["attachments"] = []
            
            # Normalize status for outgoing
            if msg["direction"] == "outgoing":
                if msg["status"] == "approved":
                     msg["status"] = "sending"
            
            messages.append(msg)
            
        # P1-4 FIX: Generate composite cursor with microsecond precision and table-specific ID
        # This prevents edge case collisions when:
        # - Messages have identical timestamps AND IDs from different tables
        # - Direction changes mid-scroll causing ordering issues
        next_cursor = None
        if has_more and messages:
            last_msg = messages[-1]
            ts = last_msg.get("effective_ts")
            if hasattr(ts, 'isoformat'):
                # P1-4 FIX: Ensure microsecond precision for better uniqueness
                ts = ts.isoformat()
            elif isinstance(ts, str):
                # Ensure string timestamps are in ISO format
                try:
                    # Parse and re-format to ensure consistency
                    dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                    ts = dt.isoformat()
                except:
                    pass
            
            # P1-4 FIX: Use composite cursor with:
            # 1. Timestamp (microsecond precision)
            # 2. Table prefix ('i' for inbox, 'o' for outbox) - prevents ID collisions
            # 3. Message ID
            # 4. Direction (for additional tie-breaking)
            # Format: "{ts}_{table_prefix}_{id}_{direction}"
            d = 'i' if last_msg['direction'] == 'incoming' else 'o'
            table_prefix = 'i' if last_msg['direction'] == 'incoming' else 'o'

            # P0-6 FIX: Use stable hash for body to prevent overflow issues
            # Python's hash() can return negative values and varies between runs
            # Use SHA256 truncated for stable, positive hash
            import hashlib
            body_text = last_msg.get('body', '')[:50] if last_msg.get('body') else ''
            body_hash = int(hashlib.md5(body_text.encode()).hexdigest()[:8], 16)

            cursor_str = f"{ts}_{table_prefix}_{last_msg['id']}_{d}_{body_hash}"
            next_cursor = base64.b64encode(cursor_str.encode('utf-8')).decode('utf-8')
            
        # Fetch presence info for the peer
        is_online = False
        last_seen_at = None
        
        try:
            from services.websocket_manager import get_websocket_manager
            from logging_config import get_logger
            _logger = get_logger(__name__)
            manager = get_websocket_manager()
            
            # Find peer license ID by username
            peer = await fetch_one(db, "SELECT id, last_seen_at FROM license_keys WHERE username = ?", (sender_contact,))
            _logger.info(f"Presence lookup for '{sender_contact}': found={peer is not None}, last_seen_at={peer['last_seen_at'] if peer else None}")
            if peer:
                peer_id = peer["id"]
                last_seen_at = peer["last_seen_at"]
                # Convert to ISO string for the frontend
                if last_seen_at:
                    if hasattr(last_seen_at, "isoformat"):
                        last_seen_at = last_seen_at.isoformat()
                
                if manager.redis_enabled:
                    redis = manager.redis_client
                    count = await redis.get(f"almudeer:presence:count:{peer_id}")
                    is_online = int(count) > 0 if count else False
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Failed to fetch presence info in cursor: {e}")

        return {
            "messages": messages,
            "next_cursor": next_cursor,
            "has_more": has_more,
            "is_online": is_online,
            "last_seen_at": last_seen_at
        }


# ignore_chat removed as per request to unify inbox


async def approve_chat_messages(license_id: int, sender_contact: str) -> int:
    """
    Mark all 'analyzed' messages from a sender as 'approved'.
    Used when replying to a conversation to ensure the whole thread is marked as handled.
    Returns the count of messages updated.
    
    Uses comprehensive alias matching to find all messages from the same sender.
    """
    async with get_db() as db:
        # Get all aliases for this sender
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)
        
        # Build comprehensive WHERE clause
        conditions = []
        params = [license_id]
        
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            conditions.append(f"sender_contact IN ({contact_placeholders})")
            params.extend(list(all_contacts))
        
        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            conditions.append(f"sender_id IN ({id_placeholders})")
            params.extend(list(all_ids))
        
        sender_where = " OR ".join(conditions) if conditions else "1=0"
        
        # Update all 'analyzed' messages from this sender
        await execute_sql(
            db,
            f"""
            UPDATE inbox_messages 
            SET status = 'approved'
            WHERE license_key_id = ?
            AND ({sender_where})
            """,
            params
        )
        
        await commit_db(db)
        await upsert_conversation_state(license_id, sender_contact)
        return 1



async def fix_stale_inbox_status(license_id: int = None) -> int:
    """
    Scans for conversations that have a 'sent', 'approved', or 'auto_replied' status message LATER
    than an 'analyzed' message, and fixes the 'analyzed' ones to 'approved'.
    Returns number of fixed messages.
    """
    from db_helper import DB_TYPE
    
    # If license_id is None, we run for all licenses (ignoring the filter)
    license_filter = "license_key_id = ?" if license_id else "1=1"
    params = [license_id] if license_id else []

    query = f"""
    UPDATE inbox_messages
    SET status = 'approved'
    WHERE {license_filter}
    AND (
        EXISTS (
            SELECT 1 FROM inbox_messages m2
            WHERE m2.license_key_id = inbox_messages.license_key_id
            AND (m2.sender_contact = inbox_messages.sender_contact OR m2.sender_id = inbox_messages.sender_id)
            AND m2.status IN ('approved', 'sent', 'auto_replied')
            AND m2.created_at > inbox_messages.created_at
        )
        OR EXISTS (
            SELECT 1 FROM outbox_messages o
            WHERE o.license_key_id = inbox_messages.license_key_id
            AND (o.recipient_email = inbox_messages.sender_contact OR o.recipient_id = inbox_messages.sender_id)
            AND o.status IN ('approved', 'sent')
            AND o.created_at > inbox_messages.created_at
        )
    )
    """
    
    async with get_db() as db:
        await execute_sql(db, query, params)
        return 1


async def mark_message_as_read(message_id: int, license_id: int) -> bool:
    """Mark a single inbox message as read."""
    async with get_db() as db:
        query = "UPDATE inbox_messages SET is_read = 1 WHERE id = ? AND license_key_id = ?"
        params = [message_id, license_id]
        if DB_TYPE == "postgresql":
            query = "UPDATE inbox_messages SET is_read = TRUE WHERE id = ? AND license_key_id = ?"
            
        await execute_sql(db, query, params)
        await commit_db(db)
        
        # After marking as read, update the conversation's unread_count
        row = await fetch_one(db, "SELECT sender_contact FROM inbox_messages WHERE id = ?", [message_id])
        if row and row["sender_contact"]:
            await upsert_conversation_state(license_id, row["sender_contact"])
        return True

async def mark_chat_read(license_id: int, sender_contact: str) -> int:
    """
    Mark all messages from a sender as 'read'.
    This clears the unread badge for the conversation.
    Returns the count of messages updated.

    Uses comprehensive alias matching to find all messages from the same sender.
    """
    async with get_db() as db:
        # Get all aliases for this sender
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)

        # Build comprehensive WHERE clause
        conditions = []
        params = [license_id]

        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            conditions.append(f"sender_contact IN ({contact_placeholders})")
            params.extend(list(all_contacts))

        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            conditions.append(f"sender_id IN ({id_placeholders})")
            params.extend(list(all_ids))

        sender_where = " OR ".join(conditions) if conditions else "1=0"

        # Update all messages from this sender to is_read=1
        if DB_TYPE == "postgresql":
            query = f"""
                UPDATE inbox_messages
                SET is_read = TRUE
                WHERE license_key_id = ?
                AND ({sender_where})
                AND (is_read IS NOT TRUE)
            """
        else:
            query = f"""
                UPDATE inbox_messages
                SET is_read = 1
                WHERE license_key_id = ?
                AND ({sender_where})
                AND (is_read = 0 OR is_read IS NULL)
            """

        await execute_sql(db, query, params)
        await commit_db(db)
        await upsert_conversation_state(license_id, sender_contact)
        
        # FIX P0-9: Broadcast read receipt to other devices
        try:
            from services.websocket_manager import broadcast_conversation_read
            await broadcast_conversation_read(license_id, sender_contact)
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Failed to broadcast read receipt: {e}")
        
        return 1










async def get_full_chat_history(
    license_id: int,
    sender_contact: str,
    limit: int = 100
) -> List[dict]:
    """
    Get complete chat history including both incoming (inbox) and outgoing (outbox) messages.
    Returns messages sorted by timestamp, each marked with 'direction' field.
    
    Uses comprehensive alias matching to find all messages from the same sender,
    even if stored with different identifier formats (phone, username, ID).
    """
    async with get_db() as db:
        # Get all aliases for this sender
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)
        
        # Build comprehensive WHERE clause for sender matching
        conditions = []
        inbox_params = [license_id]
        
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            conditions.append(f"sender_contact IN ({contact_placeholders})")
            inbox_params.extend(list(all_contacts))
        
        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            conditions.append(f"sender_id IN ({id_placeholders})")
            inbox_params.extend(list(all_ids))
        
        sender_where = " OR ".join(conditions) if conditions else "1=0"
        inbox_params.append(limit)
        
        # Get incoming messages (from client to us)
        inbox_rows = await fetch_all(
            db,
            f"""
            SELECT 
                id, channel, sender_name, sender_contact, sender_id, 
                subject, body, attachments,
                intent, urgency, sentiment, language, dialect,
                ai_summary, ai_draft_response, status,
                created_at, received_at,
                reply_to_id, reply_to_platform_id, reply_to_body_preview, reply_to_sender_name,
                COALESCE(received_at, created_at) as effective_ts,
                edited_at
            FROM inbox_messages
            WHERE license_key_id = ?
            AND ({sender_where})
            AND deleted_at IS NULL
            ORDER BY effective_ts ASC
            LIMIT ?
            """,
            inbox_params
        )
        
        # Build params for outbox (uses recipient_email and recipient_id)
        out_conditions = []
        out_params = [license_id]
        
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            out_conditions.append(f"o.recipient_email IN ({contact_placeholders})")
            out_params.extend(list(all_contacts))
        
        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            out_conditions.append(f"o.recipient_id IN ({id_placeholders})")
            out_params.extend(list(all_ids))
        
        out_where = " OR ".join(out_conditions) if out_conditions else "1=0"
        out_params.append(limit)
        
        outbox_rows = await fetch_all(
            db,
            f"""
            SELECT 
                o.id, o.channel, o.recipient_email as sender_contact, o.recipient_id as sender_id,
                o.subject, o.body, o.attachments, o.status,
                o.created_at, o.sent_at, o.edited_at,
                o.delivery_status,
                o.reply_to_platform_id, o.reply_to_body_preview,
                i.sender_name
            FROM outbox_messages o
            LEFT JOIN inbox_messages i ON o.inbox_message_id = i.id
            WHERE o.license_key_id = ?
            AND ({out_where})
            AND o.status IN ('sent', 'approved')
            AND o.deleted_at IS NULL
            ORDER BY o.created_at ASC
            LIMIT ?
            """,
            out_params
        )
        
        # Convert to list with direction marker
        messages = []
        
        for row in inbox_rows:
            msg = _parse_message_row(dict(row))
            msg["direction"] = "incoming"
            msg["timestamp"] = msg.get("received_at") or msg.get("created_at")
            messages.append(msg)
        
        for row in outbox_rows:
            msg = _parse_message_row(dict(row))
            msg["direction"] = "outgoing"
            msg["timestamp"] = msg.get("sent_at") or msg.get("created_at")
            # Mark outgoing status as descriptive
            if msg.get("status") == "sent":
                msg["status"] = "sent"
            elif msg.get("status") == "approved":
                msg["status"] = "sending"
            msg["is_edited"] = bool(msg.get("edited_at")) # Infer is_edited from edited_at
            messages.append(msg)
        
        # Sort all messages by timestamp
        def get_timestamp(m):
            ts = m.get("timestamp")
            if ts is None:
                return ""
            if isinstance(ts, str):
                return ts
            return ts.isoformat() if hasattr(ts, 'isoformat') else str(ts)
        
        messages.sort(key=get_timestamp)
        
        return messages






# ============ Message Editing Functions ============

async def save_synced_outbox_message(
    license_id: int,
    channel: str,
    body: str,
    recipient_id: str = None,
    recipient_email: str = None,
    recipient_name: str = None, # Optional, for UI
    subject: str = None,
    attachments: Optional[List[dict]] = None,
    sent_at: datetime = None,
    platform_message_id: str = None,
    is_forwarded: bool = False
) -> int:
    """
    Save a synced outgoing message (sent from external platform) to outbox.
    Status will be 'sent'.
    """
    
    # Check for duplicates using platform_message_id if provided isn't ideal because outbox doesn't have platform_message_id column by default usually?
    # Wait, looking at schema in `create_outbox_message`... it DOES NOT have `platform_message_id`.
    # It has `reply_to_platform_id`.
    # But checking `inbox.py` schema for `outbox_messages`:
    # CREATE TABLE IF NOT EXISTS outbox_messages (
    # ...
    # )
    # We might need to rely on timestamps or exact body match if we lack a unique ID column for outbox.
    # However, `inbox_messages` has `platform_message_id`. 
    # `outbox_messages` usually stores our own ID.
    # Let's check `models/inbox.py` columns again from `create_outbox_message`:
    # recipient_id, recipient_email, subject, body, attachments, reply_to_platform_id
    
    # We risk duplicates if we don't have a way to deduce "we already have this".
    # For now, we can check if a message with same body + recipient + approx timestamp exists? 
    # Or just Insert. Telegram listener runs live, so it shouldn't duplicate unless restarted and getting old updates.
    # Gmail fetching logic usually handles deduping by ID, but we need to store ID somewhere.
    # If we don't have a column, we can't fully prevent duplicates on re-fetch without external state.
    # PROPOSAL: Use `reply_to_platform_id` column to store the message ID? No, that's for threading.
    # Use `inbox_message_id`? No.
    # Let's blindly insert for V1 and rely on listener logic to not send duplicates.
    
    
    # Normalize sent_at
    if isinstance(sent_at, str):
        try:
            sent_ts = datetime.fromisoformat(sent_at)
        except ValueError:
            sent_ts = datetime.utcnow()
    elif isinstance(sent_at, datetime):
        sent_ts = sent_at
    else:
        sent_ts = datetime.utcnow()

    if sent_ts.tzinfo is not None:
        sent_ts = sent_ts.astimezone(timezone.utc).replace(tzinfo=None)

    ts_value: Any
    if DB_TYPE == "postgresql":
        ts_value = sent_ts
    else:
        ts_value = sent_ts.isoformat()

    # Serialize attachments
    import json
    attachments_json = json.dumps(attachments) if attachments else None

    async with get_db() as db:

        # ---------------------------------------------------------
        # Canonical Identity Lookup (Prevent Duplicates)
        # ---------------------------------------------------------
        # For outgoing, 'recipient' is the contact.
        contact_val = recipient_email or recipient_id
        if contact_val and license_id:
             existing_row = await fetch_one(
                db,
                """
                SELECT sender_contact
                FROM inbox_messages
                WHERE license_key_id = ? AND sender_id = ?
                AND sender_contact IS NOT NULL AND sender_contact != ''
                LIMIT 1
                """,
                [license_id, contact_val]
            )
             if existing_row and existing_row['sender_contact']:
                 # If we found a known contact for this ID, use it to ensure consistency
                 # This helps mapping recipient_id (12345) to recipient_email/phone (+971...)
                 canonical = existing_row['sender_contact']
                 if recipient_email and recipient_email != canonical: recipient_email = canonical
                 if recipient_id and recipient_id != canonical: recipient_id = canonical

        # FIX P0-11: Check for duplicate using platform_message_id before inserting
        # This prevents duplicate messages when Telegram listener restarts and re-fetches updates
        if platform_message_id:
            existing = await fetch_one(
                db,
                "SELECT id FROM outbox_messages WHERE license_key_id = ? AND channel = ? AND platform_message_id = ?",
                [license_id, channel, platform_message_id]
            )
            if existing:
                logger.info(f"Skipping duplicate outbox message: platform_message_id={platform_message_id}")
                return existing["id"]  # Return existing ID to prevent duplicate

        await execute_sql(
            db,
            """
            INSERT INTO outbox_messages
                (license_key_id, channel, recipient_id,
                 recipient_email, subject, body, attachments,
                 status, sent_at, created_at, is_forwarded, platform_message_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'sent', ?, ?, ?, ?)
            """,
            [
                license_id, channel, recipient_id,
                recipient_email, subject, body, attachments_json,
                ts_value, ts_value, is_forwarded, platform_message_id
            ],
        )

        row = await fetch_one(
            db,
            """
            SELECT id FROM outbox_messages
            WHERE license_key_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            [license_id],
        )
        await commit_db(db)

        message_id = row["id"] if row else 0
        
        # Update conversation state
        contact = recipient_email or recipient_id
        if contact:
            await upsert_conversation_state(license_id, contact, recipient_name, channel)
            
        # Broadcast via WebSocket
        try:
            from services.websocket_manager import broadcast_new_message
            
            evt_data = {
                "id": message_id,
                "outbox_id": message_id,  # Include outbox_id for status tracking
                "channel": channel,
                "sender_contact": contact,
                "sender_name": None, # It's us
                "body": body,
                "status": "sent",
                "direction": "outgoing",
                "timestamp": ts_value.isoformat() if hasattr(ts_value, 'isoformat') else str(ts_value),
                "attachments": attachments or [],
                "is_forwarded": is_forwarded
            }
            await broadcast_new_message(license_id, evt_data)
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in save_synced_outbox_message: {e}")

        return message_id


async def get_outbox_message_by_id(message_id: int, license_id: int) -> Optional[dict]:
    """Get a single outbox message by ID."""
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT * FROM outbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        return row


async def edit_outbox_message(
    message_id: int,
    license_id: int,
    new_body: str
) -> dict:
    """
    Edit an outbox message (agent's sent message).
    Rules: Only 'almudeer' and 'saved' channels, and within 24 hours.
    """
    async with get_db() as db:
        # Get the message
        message = await fetch_one(
            db,
            "SELECT * FROM outbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        
        if not message:
            raise ValueError("الرسالة غير موجودة")
        
        channel = message.get("channel")
        
        # Channel-specific restrictions: Only almudeer and saved (Drafts) are editable
        if channel not in ['almudeer', 'saved']:
            raise ValueError(f"لا يمكن تعديل الرسائل المرسلة عبر {channel}")
            
        # 24-hour edit window
        created_at = message.get("created_at")
        if created_at:
            if isinstance(created_at, str):
                try:
                    # Parse ISO format if string
                    created_at = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                except ValueError:
                    pass
            
            if isinstance(created_at, datetime):
                # Ensure offset-aware comparison
                if created_at.tzinfo is None:
                    created_at = created_at.replace(tzinfo=timezone.utc)
                
                if datetime.now(timezone.utc) - created_at > timedelta(hours=24):
                    raise ValueError("انتهت الفترة المتاحة لتعديل الرسالة (24 ساعة)")
        
        # Store original body if this is the first edit
        original_body = message.get("original_body") or message.get("body", "")
        current_edit_count = message.get("edit_count", 0) or 0
        
        now = datetime.now(timezone.utc)
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        # Update the message
        await execute_sql(
            db,
            """
            UPDATE outbox_messages 
            SET body = ?, 
                edited_at = ?,
                original_body = COALESCE(original_body, ?),
                edit_count = ?
            WHERE id = ? AND license_key_id = ?
            """,
            [new_body, ts_value, original_body, current_edit_count + 1, message_id, license_id]
        )
        
        # ---------------------------------------------------------
        # Sync to Internal Recipient (Almudeer Channel)
        # ---------------------------------------------------------
        # If this is an internal message, we must also update the recipient's inbox message
        if message.get("channel") == "almudeer":
            platform_id = f"alm_{message_id}"
            await execute_sql(
                db,
                "UPDATE inbox_messages SET body = ?, edited_at = ? WHERE platform_message_id = ?",
                [new_body, ts_value, platform_id]
            )

        await commit_db(db)
        
        # Update conversation if this was the last message
        recipient = message.get("recipient_email") or message.get("recipient_id")
        if recipient:
             await upsert_conversation_state(license_id, recipient)
        
        # Broadcast the edit via WebSocket
        try:
            from services.websocket_manager import broadcast_message_edited
            await broadcast_message_edited(
                license_id=license_id,
                message_id=message_id,
                new_body=new_body,
                edited_at=ts_value if isinstance(ts_value, str) else ts_value.isoformat(),
                sender_contact=recipient
            )
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in edit_outbox_message: {e}")
            
        return {
            "success": True,
            "message": "تم تعديل الرسالة بنجاح",
            "edited_at": now.isoformat(),
            "edit_count": current_edit_count + 1
        }


async def soft_delete_outbox_message(message_id: int, license_id: int) -> dict:
    """Soft delete an outbox message."""
    async with get_db() as db:
        # Check if message exists and is owned by this license
        message = await fetch_one(
            db,
            "SELECT id, deleted_at, recipient_email, recipient_id FROM outbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        
        if not message:
            raise ValueError("الرسالة غير موجودة")
        
        if message.get("deleted_at"):
            # Already deleted, but let's re-run upsert to ensure state is clean
            recipient = message.get("recipient_email") or message.get("recipient_id")
            if recipient:
                 await upsert_conversation_state(license_id, recipient)
            return {
                "success": True,
                "message": "الرسالة محذوفة مسبقاً",
                "deleted_at": message["deleted_at"] if isinstance(message["deleted_at"], str) else message["deleted_at"].isoformat()
            }
        
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        # Soft delete
        await execute_sql(
            db,
            "UPDATE outbox_messages SET deleted_at = ? WHERE id = ? AND license_key_id = ?",
            [ts_value, message_id, license_id]
        )
        await commit_db(db)
        
        # Update conversation
        recipient = message.get("recipient_email") or message.get("recipient_id")
        if recipient:
             await upsert_conversation_state(license_id, recipient)
        
        # Broadcast deletion via WebSocket
        try:
            from services.websocket_manager import broadcast_message_deleted
            await broadcast_message_deleted(
                license_id=license_id,
                message_id=message_id,
                sender_contact=recipient
            )
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in soft_delete_outbox_message: {e}")
            
        return {
            "success": True,
            "message": "تم حذف الرسالة بنجاح",
            "deleted_at": now.isoformat()
        }


async def soft_delete_message(message_id: int, license_id: int, msg_type: str = None) -> dict:
    """
    Unified delete function. Tries to delete from outbox first, then inbox.
    If msg_type is provided ('outgoing'/'incoming'), targets specific table to avoid ID collisions.
    """
    if msg_type == 'outgoing':
        return await soft_delete_outbox_message(message_id, license_id)
    elif msg_type == 'incoming':
        return await soft_delete_inbox_message(message_id, license_id)

    try:
        # Try outbox first (most common for deletion)
        return await soft_delete_outbox_message(message_id, license_id)
    except ValueError as e:
        # If not found in outbox, try inbox
        if str(e) == "الرسالة غير موجودة":
            return await soft_delete_inbox_message(message_id, license_id)
        raise e


async def soft_delete_inbox_message(message_id: int, license_id: int) -> dict:
    """Soft delete an inbox message."""
    async with get_db() as db:
        message = await fetch_one(
            db,
            "SELECT id, deleted_at, sender_contact FROM inbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        
        if not message:
            raise ValueError("الرسالة غير موجودة")
            
        if message.get("deleted_at"):
            # Already deleted, but ensure state is clean
            if message.get("sender_contact"):
                await upsert_conversation_state(license_id, message["sender_contact"])
            return {
                "success": True, 
                "message": "الرسالة محذوفة مسبقاً",
                "deleted_at": message["deleted_at"] if isinstance(message["deleted_at"], str) else message["deleted_at"].isoformat()
            }
            
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        await execute_sql(
            db,
            "UPDATE inbox_messages SET deleted_at = ? WHERE id = ? AND license_key_id = ?",
            [ts_value, message_id, license_id]
        )
        await commit_db(db)
        
        if message.get("sender_contact"):
            await upsert_conversation_state(license_id, message["sender_contact"])

        # Broadcast deletion via WebSocket
        try:
            from services.websocket_manager import broadcast_message_deleted
            await broadcast_message_deleted(
                license_id=license_id,
                message_id=message_id,
                sender_contact=message.get("sender_contact")
            )
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Broadcast failed in soft_delete_inbox_message: {e}")

        return {
            "success": True, 
            "message": "تم حذف الرسالة بنجاح",
            "deleted_at": now.isoformat()
        }


async def soft_delete_conversation(license_id: int, sender_contact: str, db=None) -> dict:
    """
    Soft delete an entire conversation (both inbox and outbox messages).
    Then updates conversation state (which should effectively remove it).

    FIX: Also cleans up attachments from disk/S3 to prevent storage bloat.
    
    Args:
        license_id: License ID
        sender_contact: Sender contact to delete
        db: Optional database connection (for transaction wrapping)
    """
    from datetime import datetime, timezone
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

    # P0-5: Allow optional db parameter for transaction wrapping
    should_close_db = False
    if db is None:
        db = await get_db()
        should_close_db = True
    
    try:
        # Get all aliases for this sender to ensure we clear EVERYTHING
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)

        # FIX: Collect attachment paths before soft delete for cleanup
        attachment_paths = []
        
        # Collect inbox attachments
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            inbox_atts = await fetch_all(
                db,
                f"SELECT attachments FROM inbox_messages WHERE license_key_id = ? AND sender_contact IN ({contact_placeholders}) AND deleted_at IS NULL AND attachments IS NOT NULL",
                [license_id] + list(all_contacts)
            )
        else:
            inbox_atts = await fetch_all(
                db,
                "SELECT attachments FROM inbox_messages WHERE license_key_id = ? AND sender_contact = ? AND deleted_at IS NULL AND attachments IS NOT NULL",
                [license_id, sender_contact]
            )
        
        for row in inbox_atts:
            if row.get("attachments"):
                import json
                try:
                    atts = json.loads(row["attachments"]) if isinstance(row["attachments"], str) else row["attachments"]
                    for att in atts:
                        if att.get("local_path"):
                            attachment_paths.append(att["local_path"])
                except:
                    pass
        
        # Collect outbox attachments
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            outbox_atts = await fetch_all(
                db,
                f"SELECT attachments FROM outbox_messages WHERE license_key_id = ? AND (recipient_email IN ({contact_placeholders}) OR recipient_id IN ({contact_placeholders})) AND deleted_at IS NULL AND attachments IS NOT NULL",
                [license_id] + list(all_contacts) + list(all_contacts)
            )
        else:
            outbox_atts = await fetch_all(
                db,
                "SELECT attachments FROM outbox_messages WHERE license_key_id = ? AND (recipient_email = ? OR recipient_id = ?) AND deleted_at IS NULL AND attachments IS NOT NULL",
                [license_id, sender_contact, sender_contact]
            )
        
        for row in outbox_atts:
            if row.get("attachments"):
                import json
                try:
                    atts = json.loads(row["attachments"]) if isinstance(row["attachments"], str) else row["attachments"]
                    for att in atts:
                        if att.get("local_path"):
                            attachment_paths.append(att["local_path"])
                except:
                    pass

        # Build conditions for inbox
        in_conditions = []
        in_params = [ts_value, license_id]

        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            in_conditions.append(f"sender_contact IN ({contact_placeholders})")
            in_params.extend(list(all_contacts))

        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            in_conditions.append(f"sender_id IN ({id_placeholders})")
            in_params.extend(list(all_ids))

        in_where = " OR ".join(in_conditions) if in_conditions else "1=0"

        # Params for outbox: recipient_email/id
        out_conditions = []
        out_params = [ts_value, license_id]

        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            out_conditions.append(f"recipient_email IN ({contact_placeholders})")
            out_params.extend(list(all_contacts))

        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            out_conditions.append(f"recipient_id IN ({id_placeholders})")
            out_params.extend(list(all_ids))

        out_where = " OR ".join(out_conditions) if out_conditions else "1=0"

        # Diagnostic logging
        from logging_config import get_logger
        logger = get_logger(__name__)
        logger.info(f"[CLEAR] Starting soft delete for {sender_contact}. Aliases: contacts={all_contacts}, ids={all_ids}")

        # Update Inbox
        res_in = await execute_sql(
            db,
            f"""
            UPDATE inbox_messages
            SET deleted_at = ?
            WHERE license_key_id = ?
            AND ({in_where})
            AND deleted_at IS NULL
            """,
            in_params
        )

        # Update Outbox
        await execute_sql(
            db,
            f"""
            UPDATE outbox_messages
            SET deleted_at = ?
            WHERE license_key_id = ?
            AND ({out_where})
             AND deleted_at IS NULL
            """,
            out_params
        )
        # Note: postgres connection.execute doesn't always return rowcount easily via this helper
        # but the query should execute.

        # FIX: Move commit to after all operations for proper transaction handling
        # This ensures atomic deletion of messages AND conversation entries
        logger.info(f"[CLEAR] Soft delete started for {sender_contact}")

        # FIX P0-7: Use distributed lock for attachment cleanup to prevent race conditions
        # when multiple devices delete the same conversation simultaneously
        attachment_cleanup_success = True
        try:
            from services.distributed_lock import DistributedLock
            lock_key = f"attachment_cleanup_{license_id}_{sender_contact}"
            lock = DistributedLock(lock_id=license_id, lock_name=lock_key)
            
            if await lock.acquire():
                try:
                    # Clean up attachments from disk
                    if attachment_paths:
                        from services.file_storage_service import get_file_storage
                        storage = get_file_storage()
                        cleaned_count = 0
                        for path in attachment_paths:
                            try:
                                await storage.delete_file_async(path)
                                cleaned_count += 1
                            except Exception as e:
                                logger.warning(f"Failed to delete attachment {path}: {e}")
                        logger.info(f"[CLEAR] Cleaned up {cleaned_count}/{len(attachment_paths)} attachments for {sender_contact}")
                finally:
                    await lock.release()
            else:
                logger.warning(f"[CLEAR] Skipped attachment cleanup for {sender_contact} - lock held by another process")
        except Exception as e:
            logger.error(f"[CLEAR] Error during attachment cleanup: {e}")
            # Don't fail the whole deletion if attachment cleanup fails
            attachment_cleanup_success = False

        # FIX: Delete conversation entries only ONCE (removed duplicate code)
        # Explicitly delete ALL conversation entries for discovered personas
        if all_contacts:
            placeholders_ic = ", ".join(["?" for _ in all_contacts])
            await execute_sql(
                db,
                f"DELETE FROM inbox_conversations WHERE license_key_id = ? AND sender_contact IN ({placeholders_ic})",
                [license_id] + list(all_contacts)
            )
        else:
            await execute_sql(
                db,
                "DELETE FROM inbox_conversations WHERE license_key_id = ? AND sender_contact = ?",
                [license_id, sender_contact]
            )
        
        # FIX: Single commit at the end for atomic transaction
        await commit_db(db)
        logger.info(f"[CLEAR] Soft delete completed for {sender_contact}")

        return {"success": True, "message": "تم حذف المحادثة بنجاح"}
    
    finally:
        # P0-5: Close db only if we created it
        if should_close_db:
            try:
                await db.close()
            except Exception as e:
                logger.warning(f"Error closing database: {e}")


async def clear_conversation_messages(license_id: int, sender_contact: str) -> dict:
    """
    Clear all messages in a conversation (soft delete) and reset conversation state.
    Keep the conversation entry in the inbox list but with zero counts.
    """
    from datetime import datetime, timezone
    now = datetime.utcnow()
    ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
    
    async with get_db() as db:
        # Get all aliases for this sender to ensure we clear EVERYTHING
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)
        
        # Build conditions for inbox
        in_conditions = []
        in_params = [ts_value, license_id]
        
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            in_conditions.append(f"sender_contact IN ({contact_placeholders})")
            in_params.extend(list(all_contacts))
        
        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            in_conditions.append(f"sender_id IN ({id_placeholders})")
            in_params.extend(list(all_ids))
            
        in_where = " OR ".join(in_conditions) if in_conditions else "1=0"

        # Params for outbox: recipient_email/id
        out_conditions = []
        out_params = [ts_value, license_id]
        
        if all_contacts:
            contact_placeholders = ", ".join(["?" for _ in all_contacts])
            out_conditions.append(f"recipient_email IN ({contact_placeholders})")
            out_params.extend(list(all_contacts))
        
        if all_ids:
            id_placeholders = ", ".join(["?" for _ in all_ids])
            out_conditions.append(f"recipient_id IN ({id_placeholders})")
            out_params.extend(list(all_ids))
            
        out_where = " OR ".join(out_conditions) if out_conditions else "1=0"

        from logging_config import get_logger
        logger = get_logger(__name__)
        logger.info(f"[CLEAR_MESSAGES] Starting messages clear for {sender_contact}. Aliases: contacts={all_contacts}, ids={all_ids}")

        # 1. Soft delete Inbox Messages
        await execute_sql(
            db,
            f"""
            UPDATE inbox_messages 
            SET deleted_at = ?
            WHERE license_key_id = ?
            AND ({in_where})
            AND deleted_at IS NULL
            """,
            in_params
        )
        
        # 2. Soft delete Outbox Messages
        await execute_sql(
            db,
            f"""
            UPDATE outbox_messages 
            SET deleted_at = ?
            WHERE license_key_id = ?
            AND ({out_where})
            AND deleted_at IS NULL
            """,
            out_params
        )
        await commit_db(db)
        
    # 3. Reset conversation state for all discovered personas
    for contact in all_contacts:
        await upsert_conversation_state(license_id, contact)
    
    return {"success": True, "message": "تم مسح الرسائل بنجاح"}


async def restore_deleted_message(message_id: int, license_id: int) -> dict:
    """
    Restore a soft-deleted outbox message.
    
    Args:
        message_id: ID of the message to restore
        license_id: License ID for ownership verification
        
    Returns:
        {"success": True/False, "message": str}
    """
    async with get_db() as db:
        message = await fetch_one(
            db,
            "SELECT id, deleted_at FROM outbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        
        if not message:
            raise ValueError("الرسالة غير موجودة")
        
        if not message.get("deleted_at"):
            raise ValueError("الرسالة غير محذوفة")
        
        await execute_sql(
            db,
            "UPDATE outbox_messages SET deleted_at = NULL WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        await commit_db(db)
        
        return {
            "success": True,
            "message": "تم استعادة الرسالة بنجاح"
        }


async def search_messages(
    license_id: int,
    query: str,
    sender_contact: str = None,
    limit: int = 50,
    offset: int = 0
) -> dict:
    """
    Search messages using Full-Text Search.
    Supports SQLite (FTS5) and PostgreSQL (TSVector).
    Returns a unified list of inbox/outbox messages sorted by relevance.
    """
    if not query:
        return {"messages": [], "total": 0}

    results = []
    
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            # PostgreSQL Search
            params = [query, license_id, limit, offset]
            filter_clause = ""
            if sender_contact:
                params = [query, license_id, sender_contact, limit, offset]
                # We need to filter both parts of UNION
                # Use parameter $3 for contact
                filter_clause = "AND (sender_contact = $3 OR target = $3)" 
                # Wait, separate queries need correct param index?
                # Actually, simpler to inject param placeholder or adjust list.
                # Let's simple use formatted string for parameter index or careful construction.
                # $3 is contact.
                
                search_query = """
                WITH search_results AS (
                    SELECT 
                        'inbox' as source_table, 
                        id, 
                        body, 
                        sender_name, 
                        sender_contact,
                        received_at as timestamp, 
                        subject,
                        is_read::int as is_read,
                        ts_rank(search_vector, websearch_to_tsquery('english', $1)) as rank
                    FROM inbox_messages
                    WHERE search_vector @@ websearch_to_tsquery('english', $1) 
                      AND license_key_id = $2
                      AND ($3::text IS NULL OR sender_contact = $3)
                    
                    UNION ALL
                    
                    SELECT 
                        'outbox' as source_table, 
                        id, 
                        body, 
                        COALESCE(recipient_email, recipient_id) as sender_name, 
                        COALESCE(recipient_email, recipient_id) as sender_contact,
                        created_at as timestamp, 
                        NULL as subject,
                        1 as is_read,
                        ts_rank(search_vector, websearch_to_tsquery('english', $1)) as rank
                    FROM outbox_messages
                    WHERE search_vector @@ websearch_to_tsquery('english', $1) 
                      AND license_key_id = $2
                      AND ($3::text IS NULL OR COALESCE(recipient_email, recipient_id) = $3)
                )
                SELECT *, count(*) OVER() as full_count 
                FROM search_results
                ORDER BY rank DESC, timestamp DESC
                LIMIT $4 OFFSET $5
                """
                # Params: query, license_id, sender_contact, limit, offset
            else:
                 # No contact filter
                 search_query = """
                WITH search_results AS (
                    SELECT 
                        'inbox' as source_table, 
                        id, 
                        body, 
                        sender_name, 
                        sender_contact,
                        received_at as timestamp, 
                        subject,
                        is_read::int as is_read,
                        ts_rank(search_vector, websearch_to_tsquery('english', $1)) as rank
                    FROM inbox_messages
                    WHERE search_vector @@ websearch_to_tsquery('english', $1) 
                      AND license_key_id = $2
                    
                    UNION ALL
                    
                    SELECT 
                        'outbox' as source_table, 
                        id, 
                        body, 
                        COALESCE(recipient_email, recipient_id) as sender_name, 
                        COALESCE(recipient_email, recipient_id) as sender_contact,
                        created_at as timestamp, 
                        NULL as subject,
                        1 as is_read,
                        ts_rank(search_vector, websearch_to_tsquery('english', $1)) as rank
                    FROM outbox_messages
                    WHERE search_vector @@ websearch_to_tsquery('english', $1) 
                      AND license_key_id = $2
                )
                SELECT *, count(*) OVER() as full_count 
                FROM search_results
                ORDER BY rank DESC, timestamp DESC
                LIMIT $3 OFFSET $4
                """
            
            rows = await fetch_all(db, search_query, params)
            
        else:
            # SQLite Search
            params = [query, license_id, limit, offset]
            contact_filter = ""
            if sender_contact:
                params = [query, license_id, sender_contact, limit, offset]
                contact_filter = """
                    AND (
                        (m.source_table = 'inbox' AND i.sender_contact = ?)
                        OR
                        (m.source_table = 'outbox' AND COALESCE(o.recipient_email, o.recipient_id) = ?)
                    )
                """ 
                # But wait, parameter binding order!
                # query, license, contact, contact, limit, offset?
                # Or use named parameters? fetch_all usually positional.
                # Let's adjust params list manually.
                params = [query, license_id, sender_contact, sender_contact, limit, offset]

            search_query = f"""
                SELECT 
                    m.source_table,
                    m.source_id as id,
                    m.body,
                    m.sender_name,
                    CASE 
                        WHEN m.source_table = 'inbox' THEN i.sender_contact 
                        ELSE COALESCE(o.recipient_email, o.recipient_id) 
                    END as sender_contact,
                    CASE 
                        WHEN m.source_table = 'inbox' THEN i.received_at 
                        ELSE o.created_at 
                    END as timestamp,
                    CASE 
                        WHEN m.source_table = 'inbox' THEN i.subject 
                        ELSE NULL 
                    END as subject,
                    CASE
                        WHEN m.source_table = 'inbox' THEN COALESCE(i.is_read, 0)
                        ELSE 1
                    END as is_read
                FROM messages_fts m
                LEFT JOIN inbox_messages i ON m.source_table = 'inbox' AND m.source_id = i.id
                LEFT JOIN outbox_messages o ON m.source_table = 'outbox' AND m.source_id = o.id
                WHERE m.messages_fts MATCH ? 
                  AND m.license_id = ?
                  {contact_filter if sender_contact else ""}
                ORDER BY m.rank, timestamp DESC
                LIMIT ? OFFSET ?
            """
            
            rows = await fetch_all(db, search_query, params)

    # Formatting results
    formatted_messages = []
    full_count = 0
    
    if rows:
        # Try to get full_count from first row if available (Postgres)
        first_row = dict(rows[0])
        full_count = first_row.get("full_count", len(rows)) # Approx for SQLite if not implemented

        for row in rows:
            r = dict(row)
            formatted_messages.append({
                "id": r["id"],
                "type": r["source_table"], # 'inbox' or 'outbox'
                "body": r["body"],
                "sender_name": r["sender_name"],
                "sender_contact": r["sender_contact"],
                "subject": r.get("subject"),
                "timestamp": r["timestamp"], # datetime object or string
                "is_read": bool(r.get("is_read", True))
            })

    return {
        "results": formatted_messages,
        "count": full_count if full_count != 0 else len(formatted_messages)
    }


# ============ Conversation Optimization (Denormalized) ============

async def upsert_conversation_state(
    license_id: int,
    sender_contact: str,
    sender_name: Optional[str] = None,
    channel: Optional[str] = None,
    use_lock: bool = True
):
    """
    Recalculate and update the cached conversation state in `inbox_conversations`.
    Optimized: Combines multiple queries into a single pull where possible.

    FIX P1-5: Added early exit optimization - skip if conversation doesn't exist
    FIX: Added distributed lock to prevent race conditions in multi-device scenarios.

    Args:
        license_id: The license ID
        sender_contact: The contact identifier
        sender_name: Optional sender name
        channel: Optional channel type
        use_lock: Whether to use distributed lock (default True for safety)
    """
    from db_helper import DB_TYPE

    # FIX P1-5: Early exit - check if conversation exists before expensive operations
    async with get_db() as db:
        conv_exists = await fetch_one(
            db,
            "SELECT 1 FROM inbox_conversations WHERE license_key_id = ? AND sender_contact = ?",
            [license_id, sender_contact]
        )
        if not conv_exists:
            # Conversation doesn't exist, no need to update
            return

    # FIX P0-1: Use distributed lock with retry queue to prevent race conditions
    # Instead of skipping when lock is held, queue for retry to ensure updates aren't lost
    # FIX: Add logger import
    from logging_config import get_logger
    logger = get_logger(__name__)
    
    if use_lock:
        from services.distributed_lock import DistributedLock
        from utils.redis_pool import get_redis_client
        
        lock_key = f"conversation_state:{license_id}:{sender_contact}"
        lock = DistributedLock(lock_id=license_id, lock_name=lock_key)

        try:
            acquired = await lock.acquire()
            if not acquired:
                # Lock already held - another process is updating this conversation
                # P0-1 FIX: Queue for retry instead of skipping to prevent lost updates
                redis = await get_redis_client()
                if redis:
                    retry_key = f"conversation_state_retry:{license_id}"
                    # Add to retry queue with sender_contact and timestamp
                    await redis.lpush(
                        retry_key,
                        json.dumps({
                            "sender_contact": sender_contact,
                            "sender_name": sender_name,
                            "channel": channel,
                            "timestamp": datetime.utcnow().isoformat(),
                            "use_lock": use_lock
                        })
                    )
                    # Keep queue bounded - remove old entries
                    await redis.ltrim(retry_key, 0, 99)
                    logger.debug(f"Queued conversation state update for retry: {sender_contact}")
                return
            # Proceed with lock held
        except Exception as e:
            logger.error(f"Error acquiring conversation lock: {e}")
            # Continue without lock to avoid blocking (degraded but functional)
    
    async with get_db() as db:
        # 1. Get Stats and Aliases
        all_contacts, all_ids = await _get_sender_aliases(db, license_id, sender_contact)
        
        # Build optimized WHERE clauses
        in_params = [license_id]
        in_filt = []
        if all_contacts:
            in_filt.append(f"sender_contact IN ({', '.join(['?' for _ in all_contacts])})")
            in_params.extend(all_contacts)
        if all_ids:
            in_filt.append(f"sender_id IN ({', '.join(['?' for _ in all_ids])})")
            in_params.extend(all_ids)
        in_where = f"({' OR '.join(in_filt)})" if in_filt else "1=0"

        out_params = [license_id]
        out_filt = []
        if all_contacts:
            out_filt.append(f"recipient_email IN ({', '.join(['?' for _ in all_contacts])})")
            out_params.extend(all_contacts)
        if all_ids:
            out_filt.append(f"recipient_id IN ({', '.join(['?' for _ in all_ids])})")
            out_params.extend(all_ids)
        out_where = f"({' OR '.join(out_filt)})" if out_filt else "1=0"

        # Optimization: Combined Counts and Latest Message
        stats_query = f"""
            SELECT 
                (SELECT COUNT(*) FROM inbox_messages WHERE license_key_id = ? AND ({in_where}) AND deleted_at IS NULL AND (is_read IS NOT TRUE)) as unread_count,
                (SELECT COUNT(*) FROM inbox_messages WHERE license_key_id = ? AND ({in_where}) AND deleted_at IS NULL) as count_in,
                (SELECT COUNT(*) FROM outbox_messages WHERE license_key_id = ? AND ({out_where}) AND deleted_at IS NULL) as count_out
        """
        row_stats = await fetch_one(db, stats_query, [license_id] + in_params[1:] + [license_id] + in_params[1:] + [license_id] + out_params[1:])
        unread_count = row_stats["unread_count"] if row_stats else 0
        message_count = (row_stats["count_in"] if row_stats else 0) + (row_stats["count_out"] if row_stats else 0)

        # 2-in-1 Latest Message Query
        latest_msg_query = f"""
            SELECT id, body, attachments, received_at as created_at, status, channel
            FROM inbox_messages WHERE license_key_id = ? AND ({in_where}) AND deleted_at IS NULL
            UNION ALL
            SELECT id, body, attachments, created_at, status, channel
            FROM outbox_messages WHERE license_key_id = ? AND ({out_where}) AND deleted_at IS NULL
            ORDER BY created_at DESC LIMIT 1
        """
        last_message = await fetch_one(db, latest_msg_query, [license_id] + in_params[1:] + [license_id] + out_params[1:])

        if not last_message:
            ts_now = datetime.now(timezone.utc).replace(tzinfo=None) if DB_TYPE == "postgresql" else datetime.utcnow().isoformat()
            await execute_sql(db, """
                UPDATE inbox_conversations SET 
                    last_message_id = 0, last_message_body = '', unread_count = 0, message_count = 0, updated_at = ?
                WHERE license_key_id = ? AND sender_contact = ?
            """, [ts_now, license_id, sender_contact])
            await commit_db(db)
            return

        # Body formatting with Attachment Emojis
        status = last_message["status"]
        body = last_message["body"] or ""
        msg_id = last_message["id"]
        last_message_at = last_message["created_at"]
        last_attachments = last_message["attachments"]
        if not channel: channel = last_message.get("channel")

        if last_attachments:
            import json
            try:
                att_list = json.loads(last_attachments) if isinstance(last_attachments, str) else last_attachments
                if att_list:
                    att = att_list[0]
                    mime = (att.get("mime_type") or "").lower()
                    filename = (att.get("filename") or att.get("file_name") or "").lower()
                    att_type = (att.get("type") or "").lower()
                    
                    emoji = "📄"
                    if att_type in ["note", "task", "voice", "audio", "image", "photo", "video"]:
                        emoji = {"note":"📝","task":"✅","voice":"🎤","audio":"🎵","image":"📸","photo":"📸","video":"🎥"}[att_type]
                    elif mime.startswith("audio/"): emoji = "🎵"
                    elif mime.startswith("image/"): emoji = "📸"
                    elif mime.startswith("video/"): emoji = "🎥"
                    elif filename.endswith((".zip", ".rar", ".7z")): emoji = "📦"
                    
                    label_map = {"📝":"ملاحظة","✅":"مَهمَّة","🎤":"تسجيل صوتي","🎵":"ملف صوتي","📸":"صورة","🎥":"فيديو","📦":"ملف مضغوط","📄":"ملف"}
                    body = f"{emoji} {body}" if body.strip() else f"{emoji} {label_map.get(emoji, 'ملف')}"
            except: pass

        # 3. Upsert State
        now = datetime.utcnow()
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        if DB_TYPE == "postgresql" and isinstance(last_message_at, str):
            try: last_message_at = datetime.fromisoformat(last_message_at.replace('Z', '+00:00'))
            except: pass
        elif DB_TYPE != "postgresql" and isinstance(last_message_at, datetime):
            last_message_at = last_message_at.isoformat()

        fields = ["license_key_id", "sender_contact", "last_message_id", "last_message_body", 
                  "last_message_at", "last_message_attachments", "status", "unread_count", "message_count", "updated_at"]
        params = [license_id, sender_contact, msg_id, body, last_message_at, last_attachments, status, unread_count, message_count, ts_value]
        
        if sender_name: fields.append("sender_name"); params.append(sender_name)
        if channel: fields.append("channel"); params.append(channel)
            
        placeholders = ", ".join(["?" for _ in fields])
        cols = ", ".join(fields)
        update_cols = ", ".join([f"{f} = EXCLUDED.{f}" if DB_TYPE == "postgresql" else f"{f} = excluded.{f}" for f in fields if f not in ["license_key_id", "sender_contact"]])
        
        sql = f"INSERT INTO inbox_conversations ({cols}) VALUES ({placeholders}) ON CONFLICT (license_key_id, sender_contact) DO UPDATE SET {update_cols}"
        await execute_sql(db, sql, params)
        await commit_db(db)

    # FIX: Release the distributed lock
    if use_lock and 'lock' in locals():
        try:
            await lock.release()
        except Exception as e:
            logger.error(f"Error releasing conversation lock: {e}")


async def process_conversation_state_retry_queue(license_id: int, max_batch_size: int = 10) -> int:
    """
    P0-1 FIX: Process queued conversation state updates from retry queue.
    Called periodically by background workers to ensure no updates are lost.
    
    Args:
        license_id: The license ID to process retries for
        max_batch_size: Maximum number of retries to process in one batch
        
    Returns:
        Number of retries processed
    """
    from utils.redis_pool import get_redis_client
    
    redis = await get_redis_client()
    if not redis:
        return 0
    
    retry_key = f"conversation_state_retry:{license_id}"
    processed = 0
    
    try:
        for _ in range(max_batch_size):
            # Get next retry from queue
            retry_data = await redis.rpop(retry_key)
            if not retry_data:
                break
            
            data = json.loads(retry_data)
            sender_contact = data.get("sender_contact")
            sender_name = data.get("sender_name")
            channel = data.get("channel")
            
            if sender_contact:
                # Retry the update without lock to prevent infinite loop
                # (if lock fails again, it will be re-queued)
                await upsert_conversation_state(
                    license_id,
                    sender_contact,
                    sender_name,
                    channel,
                    use_lock=False  # Don't re-acquire lock during retry processing
                )
                processed += 1
                logger.debug(f"Processed conversation state retry: {sender_contact}")
    
    except Exception as e:
        logger.error(f"Error processing conversation state retry queue: {e}")
    
    return processed


# ============ Advanced Conversation Features ============

async def archive_conversation(
    license_id: int,
    sender_contact: str,
    is_archived: bool
) -> dict:
    """
    Archive or unarchive a conversation.
    Archived conversations are hidden from the main inbox but not deleted.
    """
    from datetime import datetime, timezone
    
    async with get_db() as db:
        now = datetime.now(timezone.utc)
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        if is_archived:
            await execute_sql(
                db,
                """
                UPDATE inbox_conversations
                SET is_archived = TRUE, archived_at = ?
                WHERE license_key_id = ? AND sender_contact = ?
                """,
                [ts_value, license_id, sender_contact]
            )
        else:
            await execute_sql(
                db,
                """
                UPDATE inbox_conversations
                SET is_archived = FALSE, archived_at = NULL
                WHERE license_key_id = ? AND sender_contact = ?
                """,
                [license_id, sender_contact]
            )
        
        await commit_db(db)
    
    return {
        "success": True,
        "message": "تمت أرشفة المحادثة" if is_archived else "تمت إعادة المحادثة",
        "message_en": "Conversation archived" if is_archived else "Conversation unarchived",
        "is_archived": is_archived
    }


async def pin_message(
    message_id: int,
    license_id: int,
    is_pinned: bool
) -> dict:
    """
    Pin or unpin a message.
    Pinned messages appear at the top of the conversation.
    """
    from datetime import datetime, timezone
    
    async with get_db() as db:
        # Verify message exists and belongs to license
        msg = await fetch_one(
            db,
            "SELECT id FROM inbox_messages WHERE id = ? AND license_key_id = ?",
            [message_id, license_id]
        )
        
        if not msg:
            raise ValueError("الرسالة غير موجودة")
        
        now = datetime.now(timezone.utc)
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        if is_pinned:
            await execute_sql(
                db,
                """
                UPDATE inbox_messages
                SET is_pinned = TRUE, pinned_at = ?
                WHERE id = ?
                """,
                [ts_value, message_id]
            )
        else:
            await execute_sql(
                db,
                """
                UPDATE inbox_messages
                SET is_pinned = FALSE, pinned_at = NULL
                WHERE id = ?
                """,
                [message_id]
            )
        
        await commit_db(db)
    
    return {
        "success": True,
        "message": "تم تثبيت الرسالة" if is_pinned else "تم إزالة التثبيت",
        "message_en": "Message pinned" if is_pinned else "Message unpinned",
        "is_pinned": is_pinned
    }


async def forward_message(
    license_id: int,
    message_id: int,
    target_contact: str,
    target_channel: str
) -> dict:
    """
    Forward a message to another conversation or channel.
    Creates a copy of the message with forward metadata.
    """
    from datetime import datetime, timezone
    
    async with get_db() as db:
        # Get original message
        original = await fetch_one(
            db,
            """
            SELECT body, attachments, sender_name
            FROM inbox_messages
            WHERE id = ? AND license_key_id = ?
            """,
            [message_id, license_id]
        )
        
        if not original:
            raise ValueError("الرسالة غير موجودة")
        
        # Get original sender info for forward attribution
        original_sender = original.get("sender_name", "Unknown")
        
        # Create forwarded message
        now = datetime.now(timezone.utc)
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()
        
        # Prepare forward body with attribution
        forward_body = f"↪️ Forwarded from {original_sender}:\n\n{original.get('body', '')}"
        
        await execute_sql(
            db,
            """
            INSERT INTO inbox_messages
            (license_key_id, channel, sender_name, sender_contact, body,
             attachments, received_at, is_forwarded, forwarded_from, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, TRUE, ?, 'analyzed')
            """,
            [
                license_id,
                target_channel,
                original_sender,  # Show original sender
                target_contact,
                forward_body,
                original.get("attachments"),
                ts_value,
                original.get("sender_name")
            ]
        )
        
        await commit_db(db)
        
        # Update conversation state for target
        await upsert_conversation_state(license_id, target_contact)
        
        # Broadcast to target conversation
        try:
            from services.websocket_manager import broadcast_new_message
            await broadcast_new_message(license_id, {
                "id": message_id,
                "sender_contact": target_contact,
                "body": forward_body,
                "channel": target_channel,
                "timestamp": now.isoformat(),
                "status": "analyzed",
                "direction": "incoming",
                "is_forwarded": True,
                "forwarded_from": original_sender,
            })
        except Exception as e:
            from logging_config import get_logger
            get_logger(__name__).warning(f"Forward broadcast failed: {e}")
    
    return {
        "success": True,
        "message": "تمت إعادة توجيه الرسالة",
        "message_en": "Message forwarded successfully"
    }


def _parse_message_row(row: Optional[dict]) -> Optional[dict]:
    """Parse JSON fields and normalize status for UI."""
    if not row:
        return None
    
    # Standardize as dict
    msg = dict(row)
    
    # Parse attachments safely
    import json
    if "attachments" in msg and isinstance(msg["attachments"], str):
        try:
            msg["attachments"] = json.loads(msg["attachments"])
        except:
            msg["attachments"] = []

    # Normalize status for outgoing messages in consistent UI format
    # 'approved' means it's ready to go, and usually shown as 'sending' in UI
    if msg.get("direction") == "outgoing" and msg.get("status") == "approved":
        msg["status"] = "sending"

    return msg


async def search_messages_in_conversation(
    license_id: int,
    sender_contact: str,
    query: str,
    limit: int = 50,
    offset: int = 0
) -> List[dict]:
    """
    Search for messages within a specific conversation.
    Uses full-text search if available, fallback to LIKE query.
    Returns matching messages sorted by timestamp (newest first).
    
    Args:
        license_id: The license ID
        sender_contact: The contact to search within
        query: Search query string
        limit: Maximum number of results
        offset: Pagination offset
    
    Returns:
        List of matching messages with direction info
    """
    if not query or not sender_contact:
        return []
    
    results = []
    async with get_db() as db:
        # Search in inbox_messages
        inbox_query = """
            SELECT 
                id, body, sender_name, sender_contact, 
                received_at as created_at, channel, attachments,
                'incoming' as direction
            FROM inbox_messages
            WHERE license_key_id = ? 
              AND sender_contact = ?
              AND deleted_at IS NULL
              AND (
                  body LIKE ? 
                  OR sender_name LIKE ?
              )
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """
        search_pattern = f"%{query}%"
        inbox_rows = await fetch_all(
            db, 
            inbox_query, 
            [license_id, sender_contact, search_pattern, search_pattern, limit, offset]
        )
        
        for row in inbox_rows:
            results.append(_parse_message_row(dict(row)))
        
        # Search in outbox_messages
        outbox_query = """
            SELECT 
                id, body, 
                COALESCE(recipient_email, recipient_id) as sender_name,
                COALESCE(recipient_email, recipient_id) as sender_contact,
                created_at, channel, attachments,
                'outgoing' as direction
            FROM outbox_messages
            WHERE license_key_id = ? 
              AND (recipient_email = ? OR recipient_id = ?)
              AND deleted_at IS NULL
              AND body LIKE ?
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """
        outbox_rows = await fetch_all(
            db,
            outbox_query,
            [license_id, sender_contact, sender_contact, search_pattern, limit, offset]
        )
        
        for row in outbox_rows:
            results.append(_parse_message_row(dict(row)))
        
        # Sort by timestamp (newest first)
        results.sort(
            key=lambda x: x.get('created_at', '') or '',
            reverse=True
        )
    
    return results
