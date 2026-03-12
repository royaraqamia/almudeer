"""
Logging configuration for Al-Mudeer
Structured logging for production monitoring

FIX LOG-001: Added correlation ID support for tracing task operations
"""

import logging
import sys
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional
from contextvars import ContextVar

# Context variable for correlation ID (per-request tracking)
_correlation_id: ContextVar[str] = ContextVar("correlation_id", default="")


def get_correlation_id() -> str:
    """Get current correlation ID"""
    return _correlation_id.get()


def set_correlation_id(correlation_id: Optional[str] = None) -> str:
    """
    Set correlation ID for current context.
    If not provided, generates a new UUID.
    
    FIX LOG-001: Enables tracing of task operations across services
    """
    cid = correlation_id or str(uuid.uuid4())[:8]
    _correlation_id.set(cid)
    return cid


def clear_correlation_id() -> None:
    """Clear correlation ID from current context"""
    _correlation_id.set("")


class StructuredFormatter(logging.Formatter):
    """Custom formatter for structured JSON-like logs"""

    def format(self, record: logging.LogRecord) -> str:
        log_data: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }

        # FIX LOG-001: Add correlation ID if present
        correlation_id = get_correlation_id()
        if correlation_id:
            log_data["correlation_id"] = correlation_id

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        # Add extra fields if present
        if hasattr(record, "extra_fields"):
            log_data.update(record.extra_fields)

        # Format as JSON-like string (simple, no external deps)
        import json
        return json.dumps(log_data, ensure_ascii=False)


def setup_logging(log_level: str = "INFO") -> None:
    """
    Setup structured logging for the application.
    
    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    """
    # Get root logger
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, log_level.upper()))
    
    # Remove existing handlers
    logger.handlers.clear()
    
    # Create console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(getattr(logging, log_level.upper()))
    
    # Set formatter
    formatter = StructuredFormatter()
    console_handler.setFormatter(formatter)
    
    # Add handler to logger
    logger.addHandler(console_handler)
    
    # Set levels for third-party loggers
    logging.getLogger("uvicorn").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("fastapi").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("telethon").setLevel(logging.WARNING)
    logging.getLogger("aiosqlite").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance with the given name.

    Args:
        name: Logger name (usually __name__)

    Returns:
        Logger instance
    """
    return logging.getLogger(name)


class TaskOperationLogger:
    """
    Specialized logger for task operations with automatic correlation ID.
    
    FIX LOG-001: Provides structured logging for task CRUD operations
    with automatic correlation ID tracking.
    
    Usage:
        task_logger = TaskOperationLogger()
        task_logger.create(task_id, user_id, extra_data)
        task_logger.update(task_id, user_id, changes)
        task_logger.delete(task_id, user_id)
    """
    
    def __init__(self, logger_name: str = "task_operations"):
        self.logger = get_logger(logger_name)
    
    def _log(
        self,
        level: int,
        operation: str,
        task_id: str,
        user_id: str,
        license_id: int,
        **extra_data
    ):
        """Internal log method with common fields"""
        correlation_id = get_correlation_id()
        
        log_data = {
            "operation": operation,
            "task_id": task_id,
            "user_id": user_id,
            "license_id": license_id,
            "correlation_id": correlation_id,
            **extra_data
        }
        
        # Create log record with extra fields
        message = f"Task {operation}: {task_id} by user {user_id}"
        record = self.logger.makeRecord(
            self.logger.name,
            level,
            "",
            0,
            message,
            (),
            None
        )
        record.extra_fields = log_data
        self.logger.handle(record)
    
    def create(
        self,
        task_id: str,
        user_id: str,
        license_id: int,
        **extra_data
    ):
        """Log task creation"""
        self._log(
            logging.INFO,
            "create",
            task_id,
            user_id,
            license_id,
            **extra_data
        )
    
    def update(
        self,
        task_id: str,
        user_id: str,
        license_id: int,
        changes: Optional[Dict[str, Any]] = None,
        **extra_data
    ):
        """Log task update"""
        self._log(
            logging.INFO,
            "update",
            task_id,
            user_id,
            license_id,
            changes=changes or {},
            **extra_data
        )
    
    def delete(
        self,
        task_id: str,
        user_id: str,
        license_id: int,
        **extra_data
    ):
        """Log task deletion"""
        self._log(
            logging.INFO,
            "delete",
            task_id,
            user_id,
            license_id,
            **extra_data
        )
    
    def share(
        self,
        task_id: str,
        user_id: str,
        license_id: int,
        shared_with: str,
        permission: str,
        **extra_data
    ):
        """Log task sharing"""
        self._log(
            logging.INFO,
            "share",
            task_id,
            user_id,
            license_id,
            shared_with=shared_with,
            permission=permission,
            **extra_data
        )
    
    def error(
        self,
        operation: str,
        task_id: str,
        user_id: str,
        license_id: int,
        error: Exception,
        **extra_data
    ):
        """Log task operation error"""
        self._log(
            logging.ERROR,
            f"{operation}_error",
            task_id,
            user_id,
            license_id,
            error=str(error),
            **extra_data
        )


# Global task operation logger instance
task_operation_logger = TaskOperationLogger()

