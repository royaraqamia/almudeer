"""
Al-Mudeer - Retry and Circuit Breaker Utilities
Resilience patterns for handling transient failures.

Features:
- Exponential backoff retry logic
- Circuit breaker for cascading failure prevention
- Decorator-based usage for easy integration
"""

import asyncio
import time
import logging
from functools import wraps
from typing import Optional, Callable, Any, Dict, Type, Tuple, List
from enum import Enum

logger = logging.getLogger(__name__)


class CircuitState(Enum):
    """Circuit breaker states"""
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, reject requests
    HALF_OPEN = "half_open"  # Testing if service recovered


class CircuitBreakerError(Exception):
    """Raised when circuit breaker is open"""
    pass


class RetryError(Exception):
    """Raised when all retries exhausted"""
    def __init__(self, message: str, last_exception: Optional[Exception] = None):
        super().__init__(message)
        self.last_exception = last_exception


class CircuitBreaker:
    """
    Circuit breaker implementation.
    
    States:
    - CLOSED: Normal operation, requests pass through
    - OPEN: Service failing, requests fail immediately
    - HALF_OPEN: Testing if service recovered
    
    Usage:
        breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=30)
        
        @breaker
        async def call_external_service():
            ...
    """
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        half_open_max_calls: int = 3,
        name: str = "default"
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls
        self.name = name
        
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time: Optional[float] = None
        self._half_open_calls = 0
        self._lock = asyncio.Lock()
    
    @property
    def state(self) -> CircuitState:
        """Get current circuit state"""
        return self._state
    
    @property
    def is_closed(self) -> bool:
        """Check if circuit is closed (normal operation)"""
        return self._state == CircuitState.CLOSED
    
    @property
    def is_open(self) -> bool:
        """Check if circuit is open (failing)"""
        return self._state == CircuitState.OPEN
    
    async def _check_state(self):
        """Check and potentially update circuit state"""
        if self._state == CircuitState.OPEN:
            # Check if recovery timeout has passed
            if self._last_failure_time and \
               time.time() - self._last_failure_time > self.recovery_timeout:
                logger.info(f"Circuit breaker '{self.name}': Moving to HALF_OPEN state")
                self._state = CircuitState.HALF_OPEN
                self._half_open_calls = 0
    
    async def record_success(self):
        """Record successful call"""
        async with self._lock:
            if self._state == CircuitState.HALF_OPEN:
                self._success_count += 1
                if self._success_count >= self.half_open_max_calls:
                    logger.info(f"Circuit breaker '{self.name}': Moving to CLOSED state")
                    self._state = CircuitState.CLOSED
                    self._failure_count = 0
                    self._success_count = 0
            else:
                self._failure_count = 0
    
    async def record_failure(self):
        """Record failed call"""
        async with self._lock:
            self._failure_count += 1
            self._last_failure_time = time.time()
            
            if self._state == CircuitState.HALF_OPEN:
                # Immediately go back to OPEN
                logger.warning(f"Circuit breaker '{self.name}': Moving to OPEN state (failure in half-open)")
                self._state = CircuitState.OPEN
                self._success_count = 0
            elif self._failure_count >= self.failure_threshold:
                logger.warning(
                    f"Circuit breaker '{self.name}': Moving to OPEN state "
                    f"(failures: {self._failure_count}/{self.failure_threshold})"
                )
                self._state = CircuitState.OPEN
    
    async def call(self, func: Callable, *args, **kwargs) -> Any:
        """
        Execute function through circuit breaker.
        
        Raises CircuitBreakerError if circuit is open.
        """
        await self._check_state()
        
        if self._state == CircuitState.OPEN:
            time_since_failure = time.time() - self._last_failure_time if self._last_failure_time else 0
            raise CircuitBreakerError(
                f"Circuit breaker '{self.name}' is OPEN. "
                f"Retry after {self.recovery_timeout - time_since_failure:.1f}s"
            )
        
        if self._state == CircuitState.HALF_OPEN:
            async with self._lock:
                self._half_open_calls += 1
                if self._half_open_calls > self.half_open_max_calls:
                    raise CircuitBreakerError(
                        f"Circuit breaker '{self.name}' half-open limit reached"
                    )
        
        try:
            result = await func(*args, **kwargs)
            await self.record_success()
            return result
        except Exception as e:
            await self.record_failure()
            raise
    
    def __call__(self, func: Callable) -> Callable:
        """Decorator usage"""
        @wraps(func)
        async def wrapper(*args, **kwargs):
            return await self.call(func, *args, **kwargs)
        return wrapper
    
    def get_stats(self) -> Dict[str, Any]:
        """Get circuit breaker statistics"""
        return {
            "name": self.name,
            "state": self._state.value,
            "failure_count": self._failure_count,
            "success_count": self._success_count,
            "last_failure_time": self._last_failure_time
        }


def retry_with_backoff(
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0,
    jitter: bool = True,
    retryable_exceptions: Optional[Tuple[Type[Exception], ...]] = None,
    logger_name: Optional[str] = None
):
    """
    Retry decorator with exponential backoff.
    
    Args:
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay in seconds
        max_delay: Maximum delay in seconds
        exponential_base: Base for exponential backoff
        jitter: Add random jitter to delay
        retryable_exceptions: Tuple of exception types to retry on
        logger_name: Logger name for logging
        
    Usage:
        @retry_with_backoff(max_retries=3, retryable_exceptions=(DatabaseError,))
        async def database_operation():
            ...
    """
    
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            _logger = logging.getLogger(logger_name or func.__module__)
            
            last_exception = None
            attempt = 0
            
            while attempt <= max_retries:
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    last_exception = e
                    attempt += 1
                    
                    # Check if exception is retryable
                    if retryable_exceptions and not isinstance(e, retryable_exceptions):
                        _logger.error(f"{func.__name__}: Non-retryable error: {e}")
                        raise
                    
                    if attempt > max_retries:
                        _logger.error(f"{func.__name__}: All retries exhausted")
                        raise RetryError(
                            f"{func.__name__} failed after {max_retries} retries",
                            last_exception
                        )
                    
                    # Calculate delay with exponential backoff
                    delay = min(base_delay * (exponential_base ** (attempt - 1)), max_delay)
                    
                    if jitter:
                        import random
                        delay *= (0.5 + random.random() * 0.5)  # 0.5x to 1.5x
                    
                    _logger.warning(
                        f"{func.__name__}: Attempt {attempt}/{max_retries + 1} failed. "
                        f"Retrying in {delay:.2f}s. Error: {e}"
                    )
                    
                    await asyncio.sleep(delay)
            
            # Should not reach here, but just in case
            raise RetryError(f"{func.__name__} failed", last_exception)
        
        return wrapper
    return decorator


# ============================================================================
# Pre-configured Circuit Breakers for Library Services
# ============================================================================

# File Storage Circuit Breaker
file_storage_circuit_breaker = CircuitBreaker(
    name="file_storage",
    failure_threshold=5,
    recovery_timeout=30.0,
    half_open_max_calls=2
)

# Database Circuit Breaker
database_circuit_breaker = CircuitBreaker(
    name="database",
    failure_threshold=10,
    recovery_timeout=10.0,
    half_open_max_calls=3
)

# External API Circuit Breaker
external_api_circuit_breaker = CircuitBreaker(
    name="external_api",
    failure_threshold=3,
    recovery_timeout=60.0,
    half_open_max_calls=1
)


# ============================================================================
# Retry Configuration for Common Operations
# ============================================================================

# Database retry (for transient connection errors)
retry_database = retry_with_backoff(
    max_retries=3,
    base_delay=0.5,
    max_delay=10.0,
    retryable_exceptions=(Exception,),  # Customize based on your DB exceptions
    logger_name="almudeer.database"
)

# File storage retry (for I/O errors)
retry_file_storage = retry_with_backoff(
    max_retries=3,
    base_delay=1.0,
    max_delay=5.0,
    retryable_exceptions=(IOError, OSError),
    logger_name="almudeer.file_storage"
)

# External API retry (for network errors)
retry_external_api = retry_with_backoff(
    max_retries=5,
    base_delay=1.0,
    max_delay=30.0,
    retryable_exceptions=(Exception,),  # httpx.HTTPError, etc.
    logger_name="almudeer.external_api"
)


# ============================================================================
# Circuit Breaker Registry for Monitoring
# ============================================================================

_circuit_breakers: Dict[str, CircuitBreaker] = {
    "file_storage": file_storage_circuit_breaker,
    "database": database_circuit_breaker,
    "external_api": external_api_circuit_breaker
}


def get_circuit_breaker(name: str) -> Optional[CircuitBreaker]:
    """Get circuit breaker by name"""
    return _circuit_breakers.get(name)


def get_all_circuit_breaker_stats() -> Dict[str, Dict[str, Any]]:
    """Get statistics for all circuit breakers"""
    return {name: cb.get_stats() for name, cb in _circuit_breakers.items()}


async def reset_circuit_breaker(name: str):
    """Reset a circuit breaker to closed state"""
    cb = _circuit_breakers.get(name)
    if cb:
        async with cb._lock:
            cb._state = CircuitState.CLOSED
            cb._failure_count = 0
            cb._success_count = 0
            cb._last_failure_time = None
            logger.info(f"Circuit breaker '{name}' manually reset")
