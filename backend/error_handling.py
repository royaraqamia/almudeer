"""
Al-Mudeer - Enhanced Error Handling and Retry Logic
Premium-level error handling with exponential backoff and circuit breakers
"""

import asyncio
import time
from typing import Callable, Optional, TypeVar, Any
from functools import wraps
from logging_config import get_logger

logger = get_logger(__name__)

T = TypeVar('T')


class RetryConfig:
    """Configuration for retry logic"""
    
    def __init__(
        self,
        max_retries: int = 3,
        initial_delay: float = 1.0,
        max_delay: float = 60.0,
        exponential_base: float = 2.0,
        jitter: bool = True
    ):
        self.max_retries = max_retries
        self.initial_delay = initial_delay
        self.max_delay = max_delay
        self.exponential_base = exponential_base
        self.jitter = jitter


class CircuitBreaker:
    """Circuit breaker pattern for external service calls"""
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        expected_exception: type = Exception
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.expected_exception = expected_exception
        self.failure_count = 0
        self.last_failure_time: Optional[float] = None
        self.state = "closed"  # closed, open, half_open
    
    def call(self, func: Callable, *args, **kwargs):
        """Execute function with circuit breaker"""
        if self.state == "open":
            # Check if recovery timeout has passed
            if self.last_failure_time and (time.time() - self.last_failure_time) > self.recovery_timeout:
                self.state = "half_open"
                logger.info("Circuit breaker: Attempting recovery")
            else:
                raise Exception("Circuit breaker is OPEN - service unavailable")
        
        try:
            result = func(*args, **kwargs)
            # Success - reset failure count
            if self.state == "half_open":
                self.state = "closed"
            self.failure_count = 0
            return result
        except self.expected_exception as e:
            self.failure_count += 1
            self.last_failure_time = time.time()
            
            if self.failure_count >= self.failure_threshold:
                self.state = "open"
                logger.warning(f"Circuit breaker OPENED after {self.failure_count} failures")
            
            raise


async def retry_async(
    func: Callable[..., Any],
    *args,
    config: Optional[RetryConfig] = None,
    on_retry: Optional[Callable] = None,
    **kwargs
) -> Any:
    """
    Retry an async function with exponential backoff.
    
    Args:
        func: Async function to retry
        *args: Positional arguments for func
        config: Retry configuration
        on_retry: Optional callback called on each retry
        **kwargs: Keyword arguments for func
        
    Returns:
        Result of func
        
    Raises:
        Last exception if all retries fail
    """
    if config is None:
        config = RetryConfig()
    
    last_exception = None
    
    for attempt in range(config.max_retries + 1):
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            last_exception = e
            
            if attempt < config.max_retries:
                # Calculate delay with exponential backoff
                delay = min(
                    config.initial_delay * (config.exponential_base ** attempt),
                    config.max_delay
                )
                
                # Add jitter to prevent thundering herd
                if config.jitter:
                    import random
                    delay = delay * (0.5 + random.random() * 0.5)
                
                logger.warning(
                    f"Attempt {attempt + 1}/{config.max_retries + 1} failed: {e}. "
                    f"Retrying in {delay:.2f}s..."
                )
                
                if on_retry:
                    try:
                        on_retry(attempt + 1, e, delay)
                    except:
                        pass
                
                await asyncio.sleep(delay)
            else:
                logger.error(f"All {config.max_retries + 1} attempts failed. Last error: {e}")
    
    raise last_exception


def retry_sync(
    func: Callable,
    *args,
    config: Optional[RetryConfig] = None,
    on_retry: Optional[Callable] = None,
    **kwargs
) -> Any:
    """
    Retry a sync function with exponential backoff.
    """
    if config is None:
        config = RetryConfig()
    
    last_exception = None
    
    for attempt in range(config.max_retries + 1):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            last_exception = e
            
            if attempt < config.max_retries:
                delay = min(
                    config.initial_delay * (config.exponential_base ** attempt),
                    config.max_delay
                )
                
                if config.jitter:
                    import random
                    delay = delay * (0.5 + random.random() * 0.5)
                
                logger.warning(
                    f"Attempt {attempt + 1}/{config.max_retries + 1} failed: {e}. "
                    f"Retrying in {delay:.2f}s..."
                )
                
                if on_retry:
                    try:
                        on_retry(attempt + 1, e, delay)
                    except:
                        pass
                
                time.sleep(delay)
            else:
                logger.error(f"All {config.max_retries + 1} attempts failed. Last error: {e}")
    
    raise last_exception


def safe_execute(func: Callable, *args, default_return=None, **kwargs):
    """
    Safely execute a function, returning default on error.
    
    Args:
        func: Function to execute
        *args: Positional arguments
        default_return: Value to return on error
        **kwargs: Keyword arguments
        
    Returns:
        Function result or default_return on error
    """
    try:
        return func(*args, **kwargs)
    except Exception as e:
        logger.error(f"Error in safe_execute: {e}", exc_info=True)
        return default_return


async def safe_execute_async(func: Callable, *args, default_return=None, **kwargs):
    """Async version of safe_execute"""
    try:
        return await func(*args, **kwargs)
    except Exception as e:
        logger.error(f"Error in safe_execute_async: {e}", exc_info=True)
        return default_return


# Decorator for automatic retry
def with_retry(config: Optional[RetryConfig] = None):
    """Decorator to add retry logic to async functions"""
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            return await retry_async(func, *args, config=config, **kwargs)
        return wrapper
    return decorator


# Integration-specific error handlers

class IntegrationError(Exception):
    """Base exception for integration errors"""
    pass


class EmailConnectionError(IntegrationError):
    """Email connection error"""
    pass


class TelegramAPIError(IntegrationError):
    """Telegram API error"""
    pass


class WhatsAppAPIError(IntegrationError):
    """WhatsApp API error"""
    pass


def handle_integration_error(error: Exception, integration_type: str) -> Dict[str, Any]:
    """
    Handle integration-specific errors and return user-friendly message.
    
    Args:
        error: The exception that occurred
        integration_type: Type of integration (email, telegram, whatsapp)
        
    Returns:
        Dictionary with error details
    """
    error_message = str(error)
    
    # Common error patterns
    if "timeout" in error_message.lower() or "connection" in error_message.lower():
        return {
            "error_type": "connection_error",
            "message": "فشل الاتصال. يرجى التحقق من إعدادات الاتصال والمحاولة مرة أخرى.",
            "retryable": True
        }
    
    if "authentication" in error_message.lower() or "unauthorized" in error_message.lower():
        return {
            "error_type": "authentication_error",
            "message": "خطأ في المصادقة. يرجى التحقق من بيانات الاعتماد.",
            "retryable": False
        }
    
    if "rate limit" in error_message.lower() or "too many requests" in error_message.lower():
        return {
            "error_type": "rate_limit_error",
            "message": "تم تجاوز الحد المسموح. يرجى المحاولة لاحقاً.",
            "retryable": True
        }
    
    # Generic error
    return {
        "error_type": "unknown_error",
        "message": f"حدث خطأ غير متوقع: {error_message}",
        "retryable": True
    }

