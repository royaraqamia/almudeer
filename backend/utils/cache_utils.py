"""
Shared Cache Utilities

Centralized LRU cache implementation for share systems.
Prevents code duplication between task_shares.py and library_advanced.py.

Features:
- True LRU eviction using access time tracking
- Thread-safe operations with asyncio.Lock
- Configurable TTL and max cache size
- Metrics tracking for monitoring
- Proper orphaned entry cleanup
"""

import asyncio
import os
import logging
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any, Callable, Awaitable

logger = logging.getLogger(__name__)

# Configurable cache settings via environment variables
_DEFAULT_CACHE_TTL_SECONDS = int(os.getenv("SHARE_CACHE_TTL_SECONDS", "300"))  # 5 minutes
_DEFAULT_MAX_CACHE_SIZE = int(os.getenv("SHARE_CACHE_MAX_SIZE", "100"))
_CACHE_METRICS_ENABLED = os.getenv("CACHE_METRICS_ENABLED", "true").lower() == "true"


class LRUCache:
    """
    Thread-safe LRU cache with TTL support.
    
    Usage:
        cache = LRUCache(
            name="shared_tasks",
            ttl_seconds=300,
            max_size=100
        )
        
        # Store
        await cache.set(key, data)
        
        # Retrieve
        data = await cache.get(key)
        
        # Invalidate
        await cache.invalidate(key)
        await cache.invalidate_prefix(prefix)
    """
    
    def __init__(
        self,
        name: str,
        ttl_seconds: int = _DEFAULT_CACHE_TTL_SECONDS,
        max_size: int = _DEFAULT_MAX_CACHE_SIZE
    ):
        self.name = name
        self.ttl_seconds = ttl_seconds
        self.max_size = max_size
        
        # Internal storage
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._access_times: Dict[str, float] = {}
        self._lock = asyncio.Lock()
        
        # Metrics counters
        self._hits = 0
        self._misses = 0
        self._evictions = 0
        self._sets = 0
        self._invalidations = 0
    
    async def get(self, key: str) -> Optional[Any]:
        """
        Get value from cache if not expired.
        Updates access time for LRU tracking.
        """
        async with self._lock:
            if key not in self._cache:
                self._misses += 1
                return None
            
            cache_entry = self._cache[key]
            now = datetime.now(timezone.utc).timestamp()
            
            # Check expiration
            if now - cache_entry["timestamp"] >= self.ttl_seconds:
                # Expired - remove from cache
                del self._cache[key]
                self._access_times.pop(key, None)
                self._misses += 1
                logger.debug(f"[{self.name}] Cache miss (expired): {key}")
                return None
            
            # Hit - update access time for LRU tracking
            self._access_times[key] = now
            self._hits += 1
            logger.debug(f"[{self.name}] Cache hit: {key}")
            return cache_entry["data"]
    
    async def set(self, key: str, data: Any):
        """
        Set value in cache with LRU eviction.
        """
        async with self._lock:
            now = datetime.now(timezone.utc).timestamp()
            
            # LRU Eviction: If at capacity, evict the least recently used entry
            if len(self._cache) >= self.max_size and key not in self._cache:
                # Find the entry with the oldest access time (LRU)
                lru_key = None
                oldest_access_time = float('inf')
                
                for cache_key, access_time in self._access_times.items():
                    if access_time < oldest_access_time:
                        oldest_access_time = access_time
                        lru_key = cache_key
                
                # Evict the LRU entry if found
                if lru_key:
                    logger.debug(f"[{self.name}] LRU eviction: removing key '{lru_key}' (max size: {self.max_size})")
                    del self._cache[lru_key]
                    self._access_times.pop(lru_key, None)
                    self._evictions += 1
            
            # Add new entry with current timestamp
            self._cache[key] = {
                "data": data,
                "timestamp": now
            }
            # Track access time for LRU
            self._access_times[key] = now
            self._sets += 1
            logger.debug(f"[{self.name}] Cache set: {key}")
    
    async def invalidate(self, key: str):
        """
        Invalidate a specific cache entry.
        Ensures complete cleanup of both cache and access times.
        """
        async with self._lock:
            self._cache.pop(key, None)
            self._access_times.pop(key, None)
            self._invalidations += 1
            logger.debug(f"[{self.name}] Cache invalidated: {key}")
    
    async def invalidate_prefix(self, prefix: str):
        """
        Invalidate all cache entries starting with a prefix.
        Ensures complete cleanup of both cache and access times.
        """
        async with self._lock:
            # Build list first to avoid modifying dict during iteration
            keys_to_delete = [k for k in self._cache.keys() if k.startswith(prefix)]
            
            for key in keys_to_delete:
                self._cache.pop(key, None)
                self._access_times.pop(key, None)
                self._invalidations += 1
            
            # Clean up any orphaned access times (keys in access_times but not in cache)
            orphaned_access_keys = [
                k for k in self._access_times.keys()
                if k.startswith(prefix) and k not in self._cache
            ]
            for key in orphaned_access_keys:
                self._access_times.pop(key, None)
            
            if keys_to_delete:
                logger.debug(f"[{self.name}] Cache invalidated {len(keys_to_delete)} entries with prefix: {prefix}")
    
    async def clear(self):
        """Clear all cache entries."""
        async with self._lock:
            self._cache.clear()
            self._access_times.clear()
            logger.info(f"[{self.name}] Cache cleared")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics for monitoring."""
        total_requests = self._hits + self._misses
        hit_rate = (self._hits / total_requests * 100) if total_requests > 0 else 0.0
        
        return {
            "name": self.name,
            "size": len(self._cache),
            "max_size": self.max_size,
            "ttl_seconds": self.ttl_seconds,
            "hits": self._hits,
            "misses": self._misses,
            "evictions": self._evictions,
            "sets": self._sets,
            "invalidations": self._invalidations,
            "hit_rate_percent": round(hit_rate, 2)
        }
    
    async def record_metrics(self, metrics_service=None):
        """
        Record cache metrics to the metrics service.
        Call this periodically or on significant events.
        """
        if not _CACHE_METRICS_ENABLED or metrics_service is None:
            return
        
        try:
            stats = self.get_stats()
            await metrics_service.increment_counter(f"{self.name}_cache_hits", {"count": str(self._hits)})
            await metrics_service.increment_counter(f"{self.name}_cache_misses", {"count": str(self._misses)})
            await metrics_service.increment_counter(f"{self.name}_cache_evictions", {"count": str(self._evictions)})
        except Exception as e:
            logger.warning(f"Failed to record cache metrics for {self.name}: {e}")


# Pre-configured caches for share systems
_shared_tasks_cache: Optional[LRUCache] = None
_shared_items_cache: Optional[LRUCache] = None


def get_shared_tasks_cache() -> LRUCache:
    """Get or create the shared tasks cache."""
    global _shared_tasks_cache
    if _shared_tasks_cache is None:
        _shared_tasks_cache = LRUCache(name="shared_tasks")
    return _shared_tasks_cache


def get_shared_items_cache() -> LRUCache:
    """Get or create the shared items cache."""
    global _shared_items_cache
    if _shared_items_cache is None:
        _shared_items_cache = LRUCache(name="shared_items")
    return _shared_items_cache


def reset_caches():
    """Reset all caches (useful for testing)."""
    global _shared_tasks_cache, _shared_items_cache
    _shared_tasks_cache = None
    _shared_items_cache = None


async def broadcast_safe(coro: Awaitable, description: str):
    """
    Wrapper to safely execute broadcast coroutines without raising exceptions.
    Prevents background broadcast failures from affecting main operations.
    
    Usage:
        asyncio.create_task(
            broadcast_safe(
                broadcast_task_shared(...),
                "broadcast task share event"
            )
        )
    """
    try:
        await coro
    except Exception as e:
        logger.warning(f"Failed to {description}: {e}", exc_info=True)
