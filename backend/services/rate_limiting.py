"""
Al-Mudeer Rate Limiting Service
Async rate limiter for WebSocket and internal services.
"""

import time
import asyncio
from typing import Dict, List


class RateLimiter:
    """
    Async in-memory rate limiter using sliding window.
    Thread-safe for concurrent requests.
    
    Usage:
        rate_limiter = RateLimiter()
        if await rate_limiter.is_allowed("user:123", max_requests=10, period_seconds=60):
            # Request allowed
        else:
            # Rate limit exceeded
    """

    def __init__(self):
        self._requests: Dict[str, List[float]] = {}
        self._lock = asyncio.Lock()
        self._call_count = 0

    async def is_allowed(self, key: str, max_requests: int = 10, period_seconds: int = 60) -> bool:
        """
        Check if request is allowed for the given key.

        Args:
            key: Unique identifier for the rate limit bucket (e.g., "typing_indicator:123")
            max_requests: Maximum number of requests allowed in the window
            period_seconds: Time window in seconds

        Returns:
            True if request is allowed, False if rate limit exceeded
        """
        now = time.time()
        window_start = now - period_seconds

        async with self._lock:
            # Periodic cleanup: every 100 calls, purge stale entries
            self._call_count += 1
            if self._call_count >= 100:
                self._call_count = 0
                await self._cleanup_stale(window_start)

            # Get existing requests for this key
            if key not in self._requests:
                self._requests[key] = []

            # Remove expired requests
            self._requests[key] = [
                ts for ts in self._requests[key] if ts > window_start
            ]

            # Check if under limit
            current_count = len(self._requests[key])

            if current_count >= max_requests:
                return False

            # Record this request
            self._requests[key].append(now)
            return True

    async def _cleanup_stale(self, cutoff: float):
        """Remove all keys with no requests in the current window. Must hold _lock."""
        for key in list(self._requests.keys()):
            self._requests[key] = [
                ts for ts in self._requests[key] if ts > cutoff
            ]
            if not self._requests[key]:
                del self._requests[key]

    async def cleanup_old_entries(self):
        """Remove entries older than the window. Call periodically."""
        now = time.time()
        # Use the oldest window we might have (default 60 seconds)
        cutoff = now - 60
        async with self._lock:
            for key in list(self._requests.keys()):
                self._requests[key] = [
                    ts for ts in self._requests[key] if ts > cutoff
                ]
                if not self._requests[key]:
                    del self._requests[key]

    async def get_retry_after(self, key: str, max_requests: int = 10, period_seconds: int = 60) -> int:
        """
        Calculate seconds until the client can retry.

        Args:
            key: Unique identifier for the rate limit bucket
            max_requests: Maximum number of requests allowed in the window
            period_seconds: Time window in seconds

        Returns:
            Seconds until retry is allowed (minimum 1, maximum period_seconds)
        """
        now = time.time()
        window_start = now - period_seconds

        async with self._lock:
            if key not in self._requests:
                return 1

            # Get valid requests
            valid_requests = [
                ts for ts in self._requests[key] if ts > window_start
            ]

            if len(valid_requests) < max_requests:
                return 1

            # Find the oldest request that will expire soonest
            if valid_requests:
                oldest = min(valid_requests)
                retry_after = int(oldest + period_seconds - now)
                return max(1, min(retry_after, period_seconds))

            return 1
