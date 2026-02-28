"""
Sync routes for offline operation support.

Provides batch sync endpoint for mobile clients to sync pending operations
with idempotency key support to prevent duplicate processing.

P0-1 FIX: Added atomic idempotency locking to prevent race conditions
when concurrent requests use the same idempotency key.
"""
import asyncio
import json
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Tuple, Any
from fastapi import APIRouter, Depends, Request, BackgroundTasks
from pydantic import BaseModel, Field

from dependencies import get_license_from_header
from logging_config import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/api/v1/sync", tags=["sync"])

# P0-1 FIX: Async locks for atomic idempotency operations
_idempotency_locks: Dict[str, asyncio.Lock] = {}
_idempotency_lock_cleanup: Dict[str, datetime] = {}

# In-memory idempotency key cache (in production, use Redis)
# Key: idempotency_key, Value: (result, timestamp)
_idempotency_cache: dict = {}
IDEMPOTENCY_CACHE_TTL_HOURS = 24


async def _cleanup_stale_locks():
    """Clean up stale locks older than 30 seconds to prevent memory leaks."""
    now = datetime.now(timezone.utc)
    stale_locks = [
        key for key, created in _idempotency_lock_cleanup.items()
        if (now - created).total_seconds() > 30
    ]
    for key in stale_locks:
        if key in _idempotency_locks and key in _idempotency_lock_cleanup:
            del _idempotency_locks[key]
            del _idempotency_lock_cleanup[key]


async def _acquire_idempotency_lock(key: str) -> bool:
    """
    P0-1 FIX: Acquire lock for idempotency key atomically.
    Returns True if lock acquired, False if another request is processing.
    """
    await _cleanup_stale_locks()
    
    if key not in _idempotency_locks:
        _idempotency_locks[key] = asyncio.Lock()
        _idempotency_lock_cleanup[key] = datetime.now(timezone.utc)
    
    try:
        # Try to acquire lock without blocking (timeout after 5 seconds)
        acquired = await asyncio.wait_for(_idempotency_locks[key].acquire(), timeout=5.0)
        if acquired:
            # Reset cleanup timer while lock is held
            _idempotency_lock_cleanup[key] = datetime.now(timezone.utc) + timedelta(minutes=5)
        return acquired
    except asyncio.TimeoutError:
        logger.warning(f"Timeout acquiring idempotency lock for key: {key}")
        return False


def _release_idempotency_lock(key: str):
    """Release lock for idempotency key."""
    if key in _idempotency_locks and _idempotency_locks[key].locked():
        _idempotency_locks[key].release()


def _check_idempotency(key: str) -> Optional[SyncResult]:
    """Check if operation was already processed."""
    if key in _idempotency_cache:
        result, timestamp = _idempotency_cache[key]
        age = (datetime.now(timezone.utc) - timestamp).total_seconds() / 3600
        if age < IDEMPOTENCY_CACHE_TTL_HOURS:
            return result
        else:
            del _idempotency_cache[key]
    return None


def _store_idempotency(key: str, result: SyncResult):
    """Store operation result for idempotency."""
    _idempotency_cache[key] = (result, datetime.now(timezone.utc))

    # Clean old entries
    if len(_idempotency_cache) > 10000:
        cutoff = datetime.now(timezone.utc)
        to_delete = [
            k for k, (_, t) in _idempotency_cache.items()
            if (cutoff - t).total_seconds() / 3600 > IDEMPOTENCY_CACHE_TTL_HOURS
        ]
        for k in to_delete:
            del _idempotency_cache[k]


class SyncOperation(BaseModel):
    """A single operation to sync."""
    id: str = Field(..., description="Client-generated operation ID")
    type: str = Field(..., description="Operation type: approve, ignore, send, delete, etc.")
    idempotency_key: str = Field(..., description="Unique key to prevent duplicate processing")
    payload: dict = Field(default_factory=dict, description="Operation-specific data")
    client_timestamp: Optional[datetime] = Field(None, description="When operation was created on client")


class SyncRequest(BaseModel):
    """Batch sync request."""
    operations: List[SyncOperation]
    device_id: Optional[str] = None


class SyncResult(BaseModel):
    """Result of a single sync operation."""
    operation_id: str
    success: bool
    error: Optional[str] = None
    conflict: bool = False
    server_state: Optional[dict] = None
    server_timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class SyncResponse(BaseModel):
    """Batch sync response."""
    results: List[SyncResult]
    processed_count: int
    failed_count: int
    conflict_count: int = 0
    server_timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# In-memory idempotency key cache (in production, use Redis)
# Key: idempotency_key, Value: (result, timestamp)
_idempotency_cache: dict = {}
IDEMPOTENCY_CACHE_TTL_HOURS = 24


def _check_idempotency(key: str) -> Optional[SyncResult]:
    """Check if operation was already processed."""
    if key in _idempotency_cache:
        result, timestamp = _idempotency_cache[key]
        age = (datetime.now(timezone.utc) - timestamp).total_seconds() / 3600
        if age < IDEMPOTENCY_CACHE_TTL_HOURS:
            return result
        else:
            del _idempotency_cache[key]
    return None


def _store_idempotency(key: str, result: SyncResult):
    """Store operation result for idempotency."""
    _idempotency_cache[key] = (result, datetime.now(timezone.utc))
    
    # Clean old entries
    if len(_idempotency_cache) > 10000:
        cutoff = datetime.now(timezone.utc)
        to_delete = [
            k for k, (_, t) in _idempotency_cache.items()
            if (cutoff - t).total_seconds() / 3600 > IDEMPOTENCY_CACHE_TTL_HOURS
        ]
        for k in to_delete:
            del _idempotency_cache[k]


@router.post("/batch", response_model=SyncResponse)
async def sync_batch(
    request: Request,
    sync_request: SyncRequest,
    background_tasks: BackgroundTasks,
    license_data: dict = Depends(get_license_from_header),
):
    """
    Process a batch of offline operations with idempotency support.

    Each operation includes an idempotency_key to prevent duplicate processing.
    Operations are processed in order.
    
    P0-1 FIX: Added atomic locking to prevent race conditions when concurrent
    requests use the same idempotency key.
    """
    license_id = license_data.get("license_id")
    results: List[SyncResult] = []

    for op in sync_request.operations:
        try:
            # P0-1 FIX: Acquire lock for atomic idempotency check
            lock_acquired = await _acquire_idempotency_lock(op.idempotency_key)
            
            if not lock_acquired:
                # Another request is processing this key - wait briefly and check cache
                await asyncio.sleep(0.1)
                cached = _check_idempotency(op.idempotency_key)
                if cached:
                    results.append(cached)
                    continue
                else:
                    # Still processing - return conflict
                    results.append(SyncResult(
                        operation_id=op.id,
                        success=False,
                        error="Concurrent operation in progress",
                        conflict=True,
                    ))
                    continue
            
            try:
                # Check idempotency first (in-memory cache) - now atomic
                cached = _check_idempotency(op.idempotency_key)
                if cached:
                    results.append(cached)
                    continue

                # Process operation
                result = await _process_operation(op, license_id, background_tasks)

                _store_idempotency(op.idempotency_key, result)
                results.append(result)
            
            finally:
                # Always release lock
                _release_idempotency_lock(op.idempotency_key)

        except Exception as e:
            # Log error but don't crash batch
            logger.error(f"Sync error op {op.id}: {e}", exc_info=True)
            result = SyncResult(
                operation_id=op.id,
                success=False,
                error=str(e),
            )
            # Try to store result even on error (may fail if lock not held)
            try:
                _store_idempotency(op.idempotency_key, result)
            except:
                pass
            results.append(result)

    return SyncResponse(
        results=results,
        processed_count=sum(1 for r in results if r.success),
        failed_count=sum(1 for r in results if not r.success),
        conflict_count=sum(1 for r in results if r.conflict),
    )


async def _process_operation(op: SyncOperation, license_id: int, background_tasks: BackgroundTasks) -> SyncResult:
    """Process a single sync operation using shared business logic."""
    from models import (
        create_outbox_message,
        approve_outbox_message,
        get_full_chat_history,
    )
    from models.inbox import (
        get_inbox_message_by_id,
        approve_chat_messages,
        update_inbox_status,
        soft_delete_message,
        mark_chat_read,
        soft_delete_conversation,
    )
    from routes.chat_routes import send_approved_message

    try:
        if op.type == "approve":
            message_id = op.payload.get("messageId")
            edited_body = op.payload.get("editedBody")
            
            message = await get_inbox_message_by_id(message_id, license_id)
            if not message:
                return SyncResult(operation_id=op.id, success=False, error="Message not found")
            
            body = edited_body or message.get("ai_draft_response")
            if not body:
                return SyncResult(operation_id=op.id, success=False, error="No response body")
            
            # Create and approve outbox message
            outbox_id = await create_outbox_message(
                inbox_message_id=message_id,
                license_id=license_id,
                channel=message["channel"],
                body=body,
                recipient_id=message.get("sender_id"),
                recipient_email=message.get("sender_contact")
            )
            await approve_outbox_message(outbox_id, body)
            await update_inbox_status(message_id, "approved")
            
            sender = message.get("sender_contact") or message.get("sender_id")
            if sender:
                await approve_chat_messages(license_id, sender)
            
            # Queue for sending
            background_tasks.add_task(send_approved_message, outbox_id, license_id)
            return SyncResult(operation_id=op.id, success=True)
            
        elif op.type == "ignore":
            # LEGACY: Treat ignore as 'approve' (handled) for unified inbox
            message_id = op.payload.get("messageId")
            message = await get_inbox_message_by_id(message_id, license_id)
            
            if message:
                sender = message.get("sender_contact") or message.get("sender_id")
                if sender:
                    # Mark all as approved (handled)
                    await approve_chat_messages(license_id, sender)
                else:
                    await update_inbox_status(message_id, "approved")
            
            return SyncResult(operation_id=op.id, success=True)
            
        elif op.type == "send":
            sender_contact = op.payload.get("senderContact")
            body = op.payload.get("body")
            
            if not body:
                return SyncResult(operation_id=op.id, success=False, error="Empty body")

            # Need to fetch conversation to get recipient_id and channel
            from models import get_full_chat_history
            history = await get_full_chat_history(license_id, sender_contact, limit=1)
            if not history:
                 return SyncResult(operation_id=op.id, success=False, error="Conversation not found")

            channel = history[0].get("channel", "whatsapp")
            recipient_id = history[0].get("sender_id")

            outbox_id = await create_outbox_message(
                inbox_message_id=0,
                license_id=license_id,
                channel=channel,
                body=body,
                recipient_id=recipient_id,
                recipient_email=sender_contact,
                attachments=None
            )
            
            await approve_outbox_message(outbox_id, body)
            background_tasks.add_task(send_approved_message, outbox_id, license_id)
            
            return SyncResult(operation_id=op.id, success=True)
            
        elif op.type == "delete":
            message_id = op.payload.get("messageId")
            await soft_delete_message(message_id, license_id)
            return SyncResult(operation_id=op.id, success=True)
            
        elif op.type == "mark_read":
            sender_contact = op.payload.get("senderContact")
            await mark_chat_read(license_id, sender_contact)
            return SyncResult(operation_id=op.id, success=True)
            
        elif op.type == "delete_conversation":
            sender_contact = op.payload.get("senderContact")
            await soft_delete_conversation(license_id, sender_contact)
            return SyncResult(operation_id=op.id, success=True)
            
        elif op.type == "add_customer":
            name = op.payload.get("name")
            phone = op.payload.get("phone")
            email = op.payload.get("email")
            
            from models.customers import get_or_create_customer
            customer = await get_or_create_customer(
                license_id=license_id,
                phone=phone,
                email=email,
                name=name
            )
            return SyncResult(
                operation_id=op.id, 
                success=True, 
                server_state={"customer_id": customer.get("id")}
            )
            
        elif op.type in ["sync_quran_progress", "sync_athkar_counts"]:
            # These are stored in user_preferences as JSON blobs
            from models.preferences import update_preferences
            key = "quran_progress" if op.type == "sync_quran_progress" else "athkar_stats"
            data = op.payload.get("data")
            
            if data is not None:
                success = await update_preferences(license_id, **{key: json.dumps(data)})
                return SyncResult(operation_id=op.id, success=success)
            else:
                return SyncResult(operation_id=op.id, success=False, error="Missing data payload")
                
        else:
            return SyncResult(
                operation_id=op.id,
                success=False,
                error=f"Unknown operation type: {op.type}",
            )
            
    except Exception as e:
        print(f"Error processing op {op.type}: {e}")
        return SyncResult(
            operation_id=op.id,
            success=False,
            error=str(e),
        )


@router.get("/status")
async def get_sync_status(
    license_data: dict = Depends(get_license_from_header),
):
    """
    Get sync status for the current license.
    
    Returns server timestamp for client sync coordination.
    """
    return {
        "server_timestamp": datetime.now(timezone.utc).isoformat(),
    }


class DeltaSyncResponse(BaseModel):
    """Response for delta sync."""
    customers: List[dict]
    conversations: List[dict]
    server_timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


@router.get("/delta", response_model=DeltaSyncResponse)
async def get_delta_sync(
    since: Optional[datetime] = None,
    limit: int = 50,
    license_data: dict = Depends(get_license_from_header),
):
    """
    Get incremental updates for customers and conversations.

    - `since`: ISO timestamp of last sync. If missing, returns recent active context.
    - `limit`: Maximum items to return per category.
    
    P2-11 FIX: Added proper error handling and logging for malformed timestamps.
    """
    license_id = license_data.get("license_id")

    # If no timestamp provided, default to recent history (e.g., 30 days ago)
    # or just rely on limit to get "Active Context"
    if not since:
        since = datetime.now(timezone.utc) - timedelta(days=30)
    elif since.tzinfo is None:
        # P2-11 FIX: Log warning for naive timestamp and assume UTC
        logger.warning(f"Delta sync received naive timestamp (no timezone): {since}. Assuming UTC.")
        since = since.replace(tzinfo=timezone.utc)

    from models.customers import get_customers_delta
    from models.inbox import get_conversations_delta

    customers = await get_customers_delta(license_id, since, limit)
    conversations = await get_conversations_delta(license_id, since, limit)

    return DeltaSyncResponse(
        customers=customers,
        conversations=conversations,
        server_timestamp=datetime.now(timezone.utc)
    )
