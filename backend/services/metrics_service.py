"""
Al-Mudeer - Monitoring Metrics Service
Real-time metrics for Redis, WebSocket, and Database pool health.
"""

import os
import time
import asyncio
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from logging_config import get_logger

logger = get_logger(__name__)


class MetricsCollector:
    """
    Collects and exposes system metrics for monitoring dashboards.
    """
    
    def __init__(self):
        self._metrics: Dict[str, Any] = {}
        self._history: List[Dict[str, Any]] = []
        self._max_history = 100  # Keep last 100 snapshots
        self._last_collection: Optional[datetime] = None
    
    async def collect_all_metrics(self) -> Dict[str, Any]:
        """Collect all system metrics"""
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "redis": await self._collect_redis_metrics(),
            "websocket": await self._collect_websocket_metrics(),
            "database": await self._collect_database_metrics(),
            "outbox": await self._collect_outbox_metrics(),
            "system": self._collect_system_metrics(),
        }
        
        self._metrics = metrics
        self._last_collection = datetime.utcnow()
        
        # Store in history
        self._history.append(metrics)
        if len(self._history) > self._max_history:
            self._history.pop(0)
        
        return metrics
    
    async def _collect_redis_metrics(self) -> Dict[str, Any]:
        """Collect Redis health metrics"""
        from services.websocket_manager import get_websocket_manager
        
        manager = get_websocket_manager()
        
        if not manager.redis_enabled:
            return {
                "available": False,
                "status": "disabled"
            }
        
        try:
            redis = manager.redis_client
            start_time = time.time()
            
            # Ping test
            await redis.ping()
            latency_ms = (time.time() - start_time) * 1000
            
            # Memory usage
            info = await redis.info("memory")
            memory_used_mb = info.get("used_memory", 0) / (1024 * 1024)
            
            # Connection count
            connected_clients = 0
            try:
                clients_info = await redis.info("clients")
                connected_clients = clients_info.get("connected_clients", 0)
            except:
                pass
            
            # Count presence keys
            presence_keys = 0
            try:
                cursor = 0
                while True:
                    cursor, keys = await redis.scan(
                        cursor,
                        match="almudeer:presence:*",
                        count=100
                    )
                    presence_keys += len(keys)
                    if cursor == 0:
                        break
            except:
                pass
            
            return {
                "available": True,
                "status": "healthy",
                "latency_ms": round(latency_ms, 2),
                "memory_used_mb": round(memory_used_mb, 2),
                "connected_clients": connected_clients,
                "presence_keys": presence_keys,
            }
        except Exception as e:
            logger.error(f"Redis metrics collection failed: {e}")
            return {
                "available": True,
                "status": "unhealthy",
                "error": str(e),
            }
    
    async def _collect_websocket_metrics(self) -> Dict[str, Any]:
        """Collect WebSocket connection metrics"""
        from services.websocket_manager import get_websocket_manager
        
        manager = get_websocket_manager()
        
        return {
            "total_connections": manager.connection_count,
            "connected_licenses": len(manager.get_connected_licenses()),
            "redis_backed": manager.redis_enabled,
        }
    
    async def _collect_database_metrics(self) -> Dict[str, Any]:
        """Collect database pool and query metrics"""
        from db_helper import get_db, fetch_one, DB_TYPE
        
        try:
            async with get_db() as db:
                # Inbox messages count
                inbox_count = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM inbox_messages WHERE deleted_at IS NULL"
                )
                
                # Outbox messages count
                outbox_count = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM outbox_messages WHERE deleted_at IS NULL"
                )
                
                # Pending outbox
                pending_count = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM outbox_messages WHERE status = 'pending' AND deleted_at IS NULL"
                )
                
                # Failed outbox (needs attention)
                failed_count = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM outbox_messages WHERE status = 'failed' AND deleted_at IS NULL"
                )
                
                # Conversations count
                conv_count = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM inbox_conversations"
                )
                
                # Database size (SQLite specific)
                db_size_mb = 0
                if DB_TYPE != "postgresql":
                    try:
                        import os
                        db_path = os.getenv("DATABASE_PATH", "almudeer.db")
                        if os.path.exists(db_path):
                            db_size_mb = os.path.getsize(db_path) / (1024 * 1024)
                    except:
                        pass
                
                return {
                    "status": "healthy",
                    "type": DB_TYPE,
                    "inbox_messages": inbox_count["count"] if inbox_count else 0,
                    "outbox_messages": outbox_count["count"] if outbox_count else 0,
                    "pending_outbox": pending_count["count"] if pending_count else 0,
                    "failed_outbox": failed_count["count"] if failed_count else 0,
                    "conversations": conv_count["count"] if conv_count else 0,
                    "size_mb": round(db_size_mb, 2),
                }
        except Exception as e:
            logger.error(f"Database metrics collection failed: {e}")
            return {
                "status": "unhealthy",
                "error": str(e),
            }
    
    async def _collect_outbox_metrics(self) -> Dict[str, Any]:
        """Collect outbox queue health metrics"""
        from db_helper import get_db, fetch_one
        
        try:
            async with get_db() as db:
                # Messages by retry count
                retry_0 = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM outbox_messages WHERE status = 'pending' AND (retry_count IS NULL OR retry_count = 0)"
                )
                
                retry_1_3 = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM outbox_messages WHERE status = 'pending' AND retry_count BETWEEN 1 AND 3"
                )
                
                retry_4_plus = await fetch_one(
                    db,
                    "SELECT COUNT(*) as count FROM outbox_messages WHERE status = 'pending' AND retry_count >= 4"
                )
                
                # Oldest pending message
                oldest = await fetch_one(
                    db,
                    """
                    SELECT created_at FROM outbox_messages 
                    WHERE status = 'pending' 
                    ORDER BY created_at ASC 
                    LIMIT 1
                    """
                )
                
                oldest_age_minutes = 0
                if oldest and oldest.get("created_at"):
                    try:
                        created = datetime.fromisoformat(oldest["created_at"])
                        age = datetime.utcnow() - created
                        oldest_age_minutes = int(age.total_seconds() / 60)
                    except:
                        pass
                
                return {
                    "status": "healthy",
                    "pending_no_retry": retry_0["count"] if retry_0 else 0,
                    "pending_retry_1_3": retry_1_3["count"] if retry_1_3 else 0,
                    "pending_retry_4_plus": retry_4_plus["count"] if retry_4_plus else 0,
                    "oldest_pending_age_minutes": oldest_age_minutes,
                }
        except Exception as e:
            return {
                "status": "unknown",
                "error": str(e),
            }
    
    def _collect_system_metrics(self) -> Dict[str, Any]:
        """Collect system-level metrics"""
        import os
        import psutil
        
        process = psutil.Process(os.getpid())
        
        return {
            "cpu_percent": process.cpu_percent(),
            "memory_mb": process.memory_info().rss / (1024 * 1024),
            "memory_percent": process.memory_percent(),
            "threads": process.num_threads(),
            "uptime_seconds": time.time() - process.create_time(),
        }
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get latest collected metrics"""
        return self._metrics
    
    def get_history(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Get metrics history"""
        return self._history[-limit:]
    
    def get_health_summary(self) -> Dict[str, Any]:
        """Get simplified health summary for dashboards"""
        if not self._metrics:
            return {"status": "unknown", "message": "No metrics collected yet"}
        
        issues = []
        
        # Check Redis
        redis_status = self._metrics.get("redis", {})
        if redis_status.get("status") == "unhealthy":
            issues.append("Redis unhealthy")
        
        # Check database
        db_status = self._metrics.get("database", {})
        if db_status.get("status") == "unhealthy":
            issues.append("Database unhealthy")
        
        # Check failed outbox
        outbox_status = self._metrics.get("outbox", {})
        failed_count = outbox_status.get("failed_outbox", 0)
        if failed_count > 10:
            issues.append(f"{failed_count} failed outbox messages")
        
        # Check pending age
        oldest_age = outbox_status.get("oldest_pending_age_minutes", 0)
        if oldest_age > 60:
            issues.append(f"Oldest pending message: {oldest_age} minutes")
        
        overall_status = "unhealthy" if issues else "healthy"
        
        return {
            "status": overall_status,
            "issues": issues,
            "issue_count": len(issues),
            "last_check": self._last_collection.isoformat() if self._last_collection else None,
        }


# Global metrics collector
_metrics_collector: Optional[MetricsCollector] = None


def get_metrics_collector() -> MetricsCollector:
    """Get or create global metrics collector"""
    global _metrics_collector
    if _metrics_collector is None:
        _metrics_collector = MetricsCollector()
    return _metrics_collector


# ============ API Endpoint Helper ============

async def get_metrics_endpoint() -> Dict[str, Any]:
    """
    Helper for /metrics endpoint.
    Collects fresh metrics and returns them.
    """
    collector = get_metrics_collector()
    await collector.collect_all_metrics()
    
    return {
        "health": collector.get_health_summary(),
        "metrics": collector.get_metrics(),
        "history_available": len(collector.get_history()) > 0,
    }


# ============ Background Collection Task ============

async def start_metrics_collection(interval_seconds: int = 60):
    """
    Start background metrics collection task.
    Call this from main.py lifespan.
    """
    collector = get_metrics_collector()
    
    async def collect_loop():
        while True:
            try:
                await collector.collect_all_metrics()
                logger.debug("Metrics collected successfully")
            except Exception as e:
                logger.error(f"Metrics collection failed: {e}")
            
            await asyncio.sleep(interval_seconds)
    
    # Start background task
    asyncio.create_task(collect_loop())
    logger.info(f"Metrics collection started (interval: {interval_seconds}s)")


async def stop_metrics_collection():
    """Stop metrics collection (cleanup on shutdown)"""
    logger.info("Metrics collection stopped")
