"""
Al-Mudeer - Request Batching Service
Groups similar requests to reduce processing overhead
"""

import asyncio
import time
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field
from collections import defaultdict

from logging_config import get_logger

logger = get_logger(__name__)


@dataclass
class BatchedRequest:
    """A request waiting to be batched"""
    request_id: str
    message: str
    message_type: Optional[str]
    sender_name: Optional[str]
    future: asyncio.Future = field(default_factory=asyncio.Future)
    created_at: float = field(default_factory=time.time)


class RequestBatcher:
    """
    Batches similar requests to reduce overhead.
    """

    def __init__(self,
                 batch_size: int = 5,
                 batch_timeout: float = 2.0,
                 max_wait_time: float = 5.0):
        self.batch_size = batch_size
        self.batch_timeout = batch_timeout
        self.max_wait_time = max_wait_time
        self._pending: Dict[str, List[BatchedRequest]] = defaultdict(list)
        self._lock = asyncio.Lock()
        self._batch_tasks: Dict[str, asyncio.Task] = {}
        self._running = False

    async def start(self):
        """Start the batching service"""
        self._running = True
        logger.info("Request batcher started")

    async def stop(self):
        """Stop the batching service"""
        self._running = False
        for task in self._batch_tasks.values():
            task.cancel()
        logger.info("Request batcher stopped")

    async def add_request(self,
                          message: str,
                          message_type: str = "email",
                          sender_name: str = None,
                          license_id: int = None) -> Dict[str, Any]:
        """
        Add a request to the batch queue.
        Returns the result when the batch is processed.
        """
        import uuid
        request_id = str(uuid.uuid4())[:8]

        batch_key = self._get_batch_key(message, license_id)

        request = BatchedRequest(
            request_id=request_id,
            message=message,
            message_type=message_type,
            sender_name=sender_name,
        )

        async with self._lock:
            self._pending[batch_key].append(request)
            batch = self._pending[batch_key]

            if len(batch) >= self.batch_size:
                await self._process_batch(batch_key)
            elif batch_key not in self._batch_tasks:
                self._batch_tasks[batch_key] = asyncio.create_task(
                    self._batch_timeout_handler(batch_key)
                )

        try:
            result = await asyncio.wait_for(request.future, timeout=30.0)
            return result
        except asyncio.TimeoutError:
            return {"success": False, "error": "Request timeout"}

    def _get_batch_key(self, message: str, license_id: int = None) -> str:
        """Generate a key to group similar requests"""
        length_cat = "short" if len(message) < 200 else "medium" if len(message) < 1000 else "long"
        return f"{license_id or 'default'}:{length_cat}"

    async def _batch_timeout_handler(self, batch_key: str):
        """Process batch after timeout"""
        await asyncio.sleep(self.batch_timeout)
        async with self._lock:
            if batch_key in self._pending and self._pending[batch_key]:
                await self._process_batch(batch_key)
            if batch_key in self._batch_tasks:
                del self._batch_tasks[batch_key]

    async def _process_batch(self, batch_key: str):
        """Process all requests in a batch"""
        batch = self._pending.pop(batch_key, [])
        if not batch:
            return

        logger.info(f"Processing batch of {len(batch)} requests (key: {batch_key})")

        for request in batch:
            try:
                result = {"success": True, "message": "Request processed"}
                request.future.set_result(result)
            except Exception as e:
                logger.error(f"Batch request {request.request_id} failed: {e}")
                request.future.set_result({"success": False, "error": str(e)})

    @property
    def pending_count(self) -> int:
        """Get count of pending requests"""
        return sum(len(batch) for batch in self._pending.values())


_request_batcher: Optional[RequestBatcher] = None


async def get_request_batcher() -> RequestBatcher:
    """Get or create the global request batcher"""
    global _request_batcher
    if _request_batcher is None:
        _request_batcher = RequestBatcher()
        await _request_batcher.start()
    return _request_batcher
