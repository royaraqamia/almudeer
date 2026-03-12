"""
Al-Mudeer - Library Metrics Service
Prometheus-compatible metrics for library operations monitoring.

Metrics exposed:
- library_uploads_total: Counter of total uploads
- library_downloads_total: Counter of total downloads
- library_upload_bytes_total: Counter of bytes uploaded
- library_download_bytes_total: Counter of bytes downloaded
- library_storage_usage_bytes: Gauge of current storage usage per license
- library_items_total: Gauge of total items per license
- library_operations_duration: Histogram of operation latencies
- library_errors_total: Counter of errors by type
- library_shares_total: Counter of share operations
- library_quota_warnings: Gauge of quota warning levels
"""

import os
import time
import logging
from typing import Dict, Optional, Any
from functools import wraps
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# Try to import prometheus_client, but make it optional for backward compatibility
try:
    from prometheus_client import Counter, Gauge, Histogram, CollectorRegistry, generate_latest, CONTENT_TYPE_LATEST
    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    logger.warning("prometheus_client not installed - metrics will not be exposed")

# Create registry
if PROMETHEUS_AVAILABLE:
    REGISTRY = CollectorRegistry()
else:
    REGISTRY = None

# ============================================================================
# COUNTERS - Track total occurrences
# ============================================================================

if PROMETHEUS_AVAILABLE:
    LIBRARY_UPLOADS_TOTAL = Counter(
        'library_uploads_total',
        'Total number of library uploads',
        ['license_id', 'item_type', 'status'],
        registry=REGISTRY
    )

    LIBRARY_DOWNLOADS_TOTAL = Counter(
        'library_downloads_total',
        'Total number of library downloads',
        ['license_id', 'item_type'],
        registry=REGISTRY
    )

    LIBRARY_UPLOAD_BYTES_TOTAL = Counter(
        'library_upload_bytes_total',
        'Total bytes uploaded to library',
        ['license_id', 'item_type'],
        registry=REGISTRY
    )

    LIBRARY_DOWNLOAD_BYTES_TOTAL = Counter(
        'library_download_bytes_total',
        'Total bytes downloaded from library',
        ['license_id', 'item_type'],
        registry=REGISTRY
    )

    LIBRARY_ERRORS_TOTAL = Counter(
        'library_errors_total',
        'Total library errors by type',
        ['license_id', 'error_type', 'operation'],
        registry=REGISTRY
    )

    LIBRARY_SHARES_TOTAL = Counter(
        'library_shares_total',
        'Total share operations',
        ['license_id', 'action', 'permission'],
        registry=REGISTRY
    )

    LIBRARY_OPERATIONS_TOTAL = Counter(
        'library_operations_total',
        'Total library operations',
        ['license_id', 'operation', 'status'],
        registry=REGISTRY
    )

# ============================================================================
# GAUGES - Track current values
# ============================================================================

if PROMETHEUS_AVAILABLE:
    LIBRARY_STORAGE_USAGE = Gauge(
        'library_storage_usage_bytes',
        'Current storage usage in bytes',
        ['license_id'],
        registry=REGISTRY,
        multiprocess_mode='liveall'
    )

    LIBRARY_ITEMS_COUNT = Gauge(
        'library_items_total',
        'Total number of library items',
        ['license_id', 'item_type'],
        registry=REGISTRY,
        multiprocess_mode='liveall'
    )

    LIBRARY_QUOTA_WARNING = Gauge(
        'library_quota_warning',
        'Storage quota warning level (0=normal, 1=80%, 2=90%, 3=95%)',
        ['license_id'],
        registry=REGISTRY
    )

    LIBRARY_ACTIVE_UPLOADS = Gauge(
        'library_active_uploads',
        'Number of active uploads',
        ['license_id'],
        registry=REGISTRY
    )

    LIBRARY_SHARED_ITEMS = Gauge(
        'library_shared_items_total',
        'Number of shared items',
        ['license_id'],
        registry=REGISTRY
    )

# ============================================================================
# HISTOGRAMS - Track latency distributions
# ============================================================================

if PROMETHEUS_AVAILABLE:
    LIBRARY_OPERATION_DURATION = Histogram(
        'library_operation_duration_seconds',
        'Library operation duration in seconds',
        ['license_id', 'operation'],
        buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
        registry=REGISTRY
    )

    LIBRARY_UPLOAD_DURATION = Histogram(
        'library_upload_duration_seconds',
        'Library upload duration in seconds',
        ['license_id', 'item_type'],
        buckets=(0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0),
        registry=REGISTRY
    )


# ============================================================================
# Metrics Service Class
# ============================================================================

class LibraryMetricsService:
    """
    Service for tracking library metrics.
    
    Usage:
        metrics = LibraryMetricsService()
        await metrics.track_upload(license_id, item_type, file_size, duration)
    """

    def __init__(self):
        self.enabled = PROMETHEUS_AVAILABLE
        if not self.enabled:
            logger.info("Library metrics disabled - prometheus_client not installed")

    def _safe_increment(self, counter, labels: Dict[str, str]):
        """Safely increment a counter, handling missing prometheus_client"""
        if not self.enabled:
            return
        try:
            counter.labels(**labels).inc()
        except Exception as e:
            logger.warning(f"Failed to increment metric {counter._name}: {e}")

    def _safe_set(self, gauge, value: float, labels: Dict[str, str]):
        """Safely set a gauge value"""
        if not self.enabled:
            return
        try:
            gauge.labels(**labels).set(value)
        except Exception as e:
            logger.warning(f"Failed to set metric {gauge._name}: {e}")

    def _safe_observe(self, histogram, duration: float, labels: Dict[str, str]):
        """Safely observe a histogram value"""
        if not self.enabled:
            return
        try:
            histogram.labels(**labels).observe(duration)
        except Exception as e:
            logger.warning(f"Failed to observe metric {histogram._name}: {e}")

    # ========================================================================
    # Upload Metrics
    # ========================================================================

    async def track_upload_start(self, license_id: int):
        """Track upload start"""
        self._safe_increment(LIBRARY_OPERATIONS_TOTAL, {
            'license_id': str(license_id),
            'operation': 'upload',
            'status': 'started'
        })
        self._safe_increment(LIBRARY_ACTIVE_UPLOADS, {
            'license_id': str(license_id)
        })

    async def track_upload_complete(
        self,
        license_id: int,
        item_type: str,
        file_size: int,
        duration: float,
        success: bool
    ):
        """Track upload completion"""
        status = 'success' if success else 'failed'
        
        self._safe_increment(LIBRARY_UPLOADS_TOTAL, {
            'license_id': str(license_id),
            'item_type': item_type,
            'status': status
        })
        
        self._safe_increment(LIBRARY_UPLOAD_BYTES_TOTAL, {
            'license_id': str(license_id),
            'item_type': item_type
        },)
        
        self._safe_observe(LIBRARY_UPLOAD_DURATION, duration, {
            'license_id': str(license_id),
            'item_type': item_type
        })
        
        self._safe_increment(LIBRARY_OPERATIONS_TOTAL, {
            'license_id': str(license_id),
            'operation': 'upload',
            'status': status
        })
        
        self._safe_increment(LIBRARY_ACTIVE_UPLOADS, {
            'license_id': str(license_id)
        })

    # ========================================================================
    # Download Metrics
    # ========================================================================

    async def track_download(
        self,
        license_id: int,
        item_type: str,
        file_size: int,
        duration: float,
        success: bool,
        failure_reason: Optional[str] = None
    ):
        """
        Track download with failure reason tracking.
        
        P10 FIX: Added failure_reason parameter to track why downloads fail.
        
        Args:
            license_id: License key ID
            item_type: Type of item (note, image, file, audio, video)
            file_size: Size of file in bytes
            duration: Download duration in seconds
            success: Whether download succeeded
            failure_reason: Reason for failure (network_error, file_not_found, permission_denied, etc.)
        """
        status = 'success' if success else 'failed'

        self._safe_increment(LIBRARY_DOWNLOADS_TOTAL, {
            'license_id': str(license_id),
            'item_type': item_type,
            'status': status
        })

        if success and file_size > 0:
            self._safe_increment(LIBRARY_DOWNLOAD_BYTES_TOTAL, {
                'license_id': str(license_id),
                'item_type': item_type
            })

        self._safe_observe(LIBRARY_OPERATION_DURATION, duration, {
            'license_id': str(license_id),
            'operation': 'download'
        })

        # P10 FIX: Track download failures with reason
        if not success:
            error_type = failure_reason or 'download_failure'
            self._safe_increment(LIBRARY_ERRORS_TOTAL, {
                'license_id': str(license_id),
                'error_type': error_type,
                'operation': 'download'
            })
            logger.warning(
                f"Download failed: license={license_id}, type={item_type}, "
                f"reason={failure_reason}"
            )

    async def track_download_failure(
        self,
        license_id: int,
        item_id: int,
        item_type: str,
        failure_reason: str,
        error_details: Optional[Dict] = None
    ):
        """
        P10 FIX: Detailed download failure tracking.
        
        Args:
            license_id: License key ID
            item_id: Library item ID that failed to download
            item_type: Type of item
            failure_reason: Categorized failure reason
            error_details: Additional error context
        """
        self._safe_increment(LIBRARY_ERRORS_TOTAL, {
            'license_id': str(license_id),
            'error_type': f'download_{failure_reason}',
            'operation': 'download'
        })
        
        logger.warning(
            f"Download failure: license={license_id}, item={item_id}, "
            f"type={item_type}, reason={failure_reason}, details={error_details}"
        )

    # ========================================================================
    # Error Metrics
    # ========================================================================

    async def track_error(
        self,
        license_id: int,
        error_type: str,
        operation: str,
        details: Optional[Dict] = None
    ):
        """Track error"""
        self._safe_increment(LIBRARY_ERRORS_TOTAL, {
            'license_id': str(license_id),
            'error_type': error_type,
            'operation': operation
        })
        
        if details:
            logger.error(f"Library error: {operation} - {error_type} - {details}")
        else:
            logger.error(f"Library error: {operation} - {error_type}")

    # ========================================================================
    # Share Metrics
    # ========================================================================

    async def track_share(
        self,
        license_id: int,
        action: str,  # 'create', 'revoke', 'update'
        permission: str,
        success: bool
    ):
        """Track share operation"""
        status = 'success' if success else 'failed'
        
        self._safe_increment(LIBRARY_SHARES_TOTAL, {
            'license_id': str(license_id),
            'action': action,
            'permission': permission
        })
        
        self._safe_increment(LIBRARY_OPERATIONS_TOTAL, {
            'license_id': str(license_id),
            'operation': f'share_{action}',
            'status': status
        })

    # ========================================================================
    # Storage Metrics
    # ========================================================================

    async def update_storage_usage(self, license_id: int, bytes_used: int, limit: int):
        """Update storage usage gauge and check quota warnings"""
        self._safe_set(LIBRARY_STORAGE_USAGE, bytes_used, {
            'license_id': str(license_id)
        })
        
        # Calculate quota percentage and set warning level
        percentage = (bytes_used / limit * 100) if limit > 0 else 0
        
        if percentage >= 95:
            warning_level = 3
        elif percentage >= 90:
            warning_level = 2
        elif percentage >= 80:
            warning_level = 1
        else:
            warning_level = 0
        
        self._safe_set(LIBRARY_QUOTA_WARNING, warning_level, {
            'license_id': str(license_id)
        })
        
        return warning_level

    async def update_items_count(self, license_id: int, item_type: str, count: int):
        """Update items count gauge"""
        self._safe_set(LIBRARY_ITEMS_COUNT, count, {
            'license_id': str(license_id),
            'item_type': item_type
        })

    # ========================================================================
    # Context Manager for Timing Operations
    # ========================================================================

    def track_operation(self, license_id: int, operation: str):
        """
        Context manager for timing operations.
        
        Usage:
            with metrics.track_operation(license_id, 'create_note'):
                # do operation
        """
        return OperationTimer(self, license_id, operation)

    # ========================================================================
    # Prometheus Metrics Endpoint
    # ========================================================================

    def get_metrics(self) -> str:
        """Get Prometheus-formatted metrics"""
        if not self.enabled:
            return "# Prometheus metrics not available"
        return generate_latest(REGISTRY).decode('utf-8')


class OperationTimer:
    """Context manager for timing operations"""
    
    def __init__(self, metrics: LibraryMetricsService, license_id: int, operation: str):
        self.metrics = metrics
        self.license_id = license_id
        self.operation = operation
        self.start_time = None

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration = time.time() - self.start_time
        success = exc_type is None
        
        self.metrics._safe_observe(LIBRARY_OPERATION_DURATION, duration, {
            'license_id': str(self.license_id),
            'operation': self.operation
        })
        
        self.metrics._safe_increment(LIBRARY_OPERATIONS_TOTAL, {
            'license_id': str(self.license_id),
            'operation': self.operation,
            'status': 'success' if success else 'failed'
        })
        
        if exc_type:
            self.metrics._safe_increment(LIBRARY_ERRORS_TOTAL, {
                'license_id': str(self.license_id),
                'error_type': type(exc_type).__name__,
                'operation': self.operation
            })
        
        return False  # Don't suppress exceptions


# Singleton instance
_metrics_instance: Optional[LibraryMetricsService] = None


def get_library_metrics() -> LibraryMetricsService:
    """Get singleton metrics instance"""
    global _metrics_instance
    if _metrics_instance is None:
        _metrics_instance = LibraryMetricsService()
    return _metrics_instance
