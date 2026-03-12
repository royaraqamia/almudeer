"""
Al-Mudeer - Alerting Service
Monitors metrics thresholds and triggers alerts for production monitoring.

P6-1 FIX: Proactive alerting for notification failures and other critical issues.
"""

import os
import asyncio
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List, Callable
from logging_config import get_logger

logger = get_logger(__name__)


class AlertThreshold:
    """Configuration for alert thresholds"""
    
    def __init__(
        self,
        metric_name: str,
        threshold: int,
        window_minutes: int = 5,
        severity: str = "warning",  # warning, critical, emergency
        alert_channels: Optional[List[str]] = None
    ):
        self.metric_name = metric_name
        self.threshold = threshold
        self.window_minutes = window_minutes
        self.severity = severity
        self.alert_channels = alert_channels or ["log"]


class AlertingService:
    """
    Monitors metrics and triggers alerts when thresholds are exceeded.
    
    Features:
    - Configurable thresholds per metric
    - Time-window based evaluation
    - Multiple alert channels (log, webhook)
    - Alert deduplication to prevent spam
    """
    
    # Default alert thresholds for production
    DEFAULT_THRESHOLDS = [
        # Notification failures
        AlertThreshold(
            metric_name="task_share_notification_failures",
            threshold=10,
            window_minutes=5,
            severity="warning"
        ),
        AlertThreshold(
            metric_name="task_share_notification_failures",
            threshold=50,
            window_minutes=5,
            severity="critical"
        ),
        # Share revocation notification failures
        AlertThreshold(
            metric_name="share_revoked_notification_failures",
            threshold=10,
            window_minutes=5,
            severity="warning"
        ),
        # WebSocket broadcast failures
        AlertThreshold(
            metric_name="task_share_broadcast_failures",
            threshold=5,
            window_minutes=5,
            severity="warning"
        ),
        # Database connection issues
        AlertThreshold(
            metric_name="db_connection_failures",
            threshold=3,
            window_minutes=1,
            severity="critical"
        ),
        # API error rate
        AlertThreshold(
            metric_name="api_error_5xx",
            threshold=20,
            window_minutes=5,
            severity="warning"
        ),
        AlertThreshold(
            metric_name="api_error_5xx",
            threshold=100,
            window_minutes=5,
            severity="critical"
        ),
    ]
    
    def __init__(self):
        self._thresholds: List[AlertThreshold] = self.DEFAULT_THRESHOLDS.copy()
        self._metric_counts: Dict[str, List[datetime]] = {}
        self._last_alert: Dict[str, datetime] = {}
        self._alert_cooldown_minutes = 15  # Prevent alert spam
        self._running = False
        self._monitor_task: Optional[asyncio.Task] = None
        
        # Alert callbacks
        self._alert_handlers: List[Callable] = []
        
        # Register default log handler
        self.add_alert_handler(self._log_alert_handler)
    
    def add_threshold(self, threshold: AlertThreshold):
        """Add a custom alert threshold"""
        self._thresholds.append(threshold)
    
    def add_alert_handler(self, handler: Callable):
        """Add a custom alert handler callback"""
        self._alert_handlers.append(handler)
    
    async def record_metric(self, metric_name: str, count: int = 1):
        """
        Record a metric occurrence.
        
        Args:
            metric_name: Name of the metric (e.g., "task_share_notification_failures")
            count: Number of occurrences to record
        """
        now = datetime.utcnow()
        
        if metric_name not in self._metric_counts:
            self._metric_counts[metric_name] = []
        
        # Add timestamps for each occurrence
        for _ in range(count):
            self._metric_counts[metric_name].append(now)
        
        # Check thresholds after recording
        await self._check_thresholds(metric_name)
    
    async def _check_thresholds(self, metric_name: str):
        """Check if any thresholds are exceeded for a metric"""
        now = datetime.utcnow()
        
        for threshold in self._thresholds:
            if threshold.metric_name != metric_name:
                continue
            
            # Count occurrences in the time window
            window_start = now - timedelta(minutes=threshold.window_minutes)
            count = sum(
                1 for ts in self._metric_counts.get(metric_name, [])
                if ts > window_start
            )
            
            # Check if threshold exceeded
            if count >= threshold.threshold:
                # Check cooldown
                alert_key = f"{metric_name}:{threshold.severity}"
                last_alert = self._last_alert.get(alert_key)
                
                if last_alert and (now - last_alert).total_seconds() < (self._alert_cooldown_minutes * 60):
                    continue  # Still in cooldown
                
                # Trigger alert
                await self._trigger_alert(
                    metric_name=metric_name,
                    current_value=count,
                    threshold=threshold
                )
                
                # Update last alert time
                self._last_alert[alert_key] = now
    
    async def _trigger_alert(
        self,
        metric_name: str,
        current_value: int,
        threshold: AlertThreshold
    ):
        """Trigger an alert to all registered handlers"""
        alert_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "metric": metric_name,
            "current_value": current_value,
            "threshold": threshold.threshold,
            "window_minutes": threshold.window_minutes,
            "severity": threshold.severity,
            "message": self._generate_alert_message(metric_name, current_value, threshold),
        }
        
        logger.warning(
            f"🚨 ALERT [{threshold.severity.upper()}]: {alert_data['message']}"
        )
        
        # Call all registered handlers
        for handler in self._alert_handlers:
            try:
                if asyncio.iscoroutinefunction(handler):
                    await handler(alert_data)
                else:
                    handler(alert_data)
            except Exception as e:
                logger.error(f"Alert handler failed: {e}")
    
    def _generate_alert_message(
        self,
        metric_name: str,
        current_value: int,
        threshold: AlertThreshold
    ) -> str:
        """Generate human-readable alert message"""
        # Map metric names to readable descriptions
        metric_descriptions = {
            "task_share_notification_failures": "Task share notification failures",
            "share_revoked_notification_failures": "Share revocation notification failures",
            "task_share_broadcast_failures": "Task share WebSocket broadcast failures",
            "db_connection_failures": "Database connection failures",
            "api_error_5xx": "API 5xx errors",
        }
        
        description = metric_descriptions.get(metric_name, metric_name)
        
        return (
            f"{description} exceeded threshold: "
            f"{current_value} occurrences in {threshold.window_minutes} minutes "
            f"(threshold: {threshold.threshold})"
        )
    
    async def _log_alert_handler(self, alert_data: Dict[str, Any]):
        """Default alert handler - logs to file"""
        # Already logged in _trigger_alert
        pass
    
    async def start_monitoring(self):
        """Start the background monitoring task"""
        if self._running:
            return
        
        self._running = True
        self._monitor_task = asyncio.create_task(self._monitoring_loop())
        logger.info("AlertingService started monitoring")
    
    async def stop_monitoring(self):
        """Stop the background monitoring task"""
        self._running = False
        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass
        logger.info("AlertingService stopped monitoring")
    
    async def _monitoring_loop(self):
        """Background loop to clean up old metric data"""
        while self._running:
            try:
                await asyncio.sleep(60)  # Run every minute
                
                # Clean up old metric data (older than max window)
                max_window = max(t.window_minutes for t in self._thresholds)
                cutoff = datetime.utcnow() - timedelta(minutes=max_window + 5)
                
                for metric_name in list(self._metric_counts.keys()):
                    self._metric_counts[metric_name] = [
                        ts for ts in self._metric_counts[metric_name]
                        if ts > cutoff
                    ]
                    # Remove empty lists
                    if not self._metric_counts[metric_name]:
                        del self._metric_counts[metric_name]
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"AlertingService monitoring error: {e}")
    
    def get_alert_status(self) -> Dict[str, Any]:
        """Get current alerting status for health checks"""
        return {
            "running": self._running,
            "active_thresholds": len(self._thresholds),
            "tracked_metrics": len(self._metric_counts),
            "last_alerts": {
                k: v.isoformat() for k, v in self._last_alert.items()
            }
        }


# Global alerting service instance
_alerting_service: Optional[AlertingService] = None


def get_alerting_service() -> AlertingService:
    """Get the global alerting service instance"""
    global _alerting_service
    if _alerting_service is None:
        _alerting_service = AlertingService()
    return _alerting_service


async def record_alertable_metric(metric_name: str, count: int = 1):
    """
    Convenience function to record a metric that may trigger alerts.
    
    Usage:
        await record_alertable_metric("task_share_notification_failures")
    """
    await get_alerting_service().record_metric(metric_name, count)
