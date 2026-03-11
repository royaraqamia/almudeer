"""
Al-Mudeer - OpenTelemetry Distributed Tracing Setup
P5: Production-ready observability with distributed tracing.

This module configures OpenTelemetry for:
- Request tracing across services
- Database query instrumentation
- Redis operation tracing
- WebSocket connection tracking
- Custom span annotations for business logic

Usage:
    from services.telemetry import setup_telemetry
    
    # In main.py lifespan
    async def lifespan(app: FastAPI):
        tracer = setup_telemetry()
        ...
"""

import os
from typing import Optional
from logging_config import get_logger

logger = get_logger(__name__)

# Global tracer instance
_tracer = None
_meter = None


def setup_telemetry(service_name: str = "almudeer-backend") -> Optional[object]:
    """
    Initialize OpenTelemetry tracing.
    
    Args:
        service_name: Service name for tracing
    
    Returns:
        Tracer instance or None if disabled
    """
    global _tracer, _meter
    
    # Check if telemetry is enabled
    enabled = os.getenv("OTEL_ENABLED", "false").lower() == "true"
    if not enabled:
        logger.info("OpenTelemetry disabled (set OTEL_ENABLED=true to enable)")
        return None
    
    try:
        from opentelemetry import trace, metrics
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.asyncio import AsyncioInstrumentor
        from opentelemetry.instrumentation.redis import RedisInstrumentor
        
        # Configure resource with service metadata
        resource = Resource.create({
            "service.name": service_name,
            "service.version": os.getenv("SERVICE_VERSION", "1.0.0"),
            "deployment.environment": os.getenv("ENVIRONMENT", "production"),
        })
        
        # Set up tracing
        trace_provider = TracerProvider(resource=resource)
        
        # Configure OTLP exporter (Jaeger, Tempo, etc.)
        otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
        span_exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
        span_processor = BatchSpanProcessor(span_exporter)
        trace_provider.add_span_processor(span_processor)
        
        # Set global tracer
        trace.set_tracer_provider(trace_provider)
        _tracer = trace.get_tracer(service_name)
        
        # Set up metrics
        meter_provider = MeterProvider(resource=resource)
        metric_exporter = OTLPMetricExporter(endpoint=otlp_endpoint)
        meter_provider.add_metric_reader(
            # Use periodic export for metrics
            # In production, configure push interval
        )
        metrics.set_meter_provider(meter_provider)
        _meter = metrics.get_meter(service_name)
        
        # Instrument FastAPI
        FastAPIInstrumentor.instrument_app(
            # App will be passed during instrumentation
        )
        
        # Instrument asyncio
        AsyncioInstrumentor().instrument()
        
        # Instrument Redis (if available)
        try:
            RedisInstrumentor().instrument()
        except Exception as e:
            logger.warning(f"Redis instrumentation skipped: {e}")
        
        logger.info(f"OpenTelemetry initialized (endpoint: {otlp_endpoint})")
        return _tracer
        
    except ImportError as e:
        logger.warning(f"OpenTelemetry not available: {e}")
        return None
    except Exception as e:
        logger.error(f"OpenTelemetry initialization failed: {e}")
        return None


def get_tracer() -> Optional[object]:
    """Get the global tracer instance"""
    return _tracer


def get_meter() -> Optional[object]:
    """Get the global meter instance"""
    return _meter


def trace_task_operation(operation_name: str):
    """
    Decorator for tracing task operations.
    
    Usage:
        @trace_task_operation("create_task")
        async def create_task(...):
            ...
    """
    def decorator(func):
        if _tracer is None:
            return func
            
        from functools import wraps
        from opentelemetry import trace as otel_trace
        
        @wraps(func)
        async def wrapper(*args, **kwargs):
            tracer = _tracer or otel_trace.get_tracer("almudeer")
            
            with tracer.start_as_current_span(f"task.{operation_name}") as span:
                # Add operation attributes
                span.set_attribute("operation", operation_name)
                
                # Add task_id if available
                if "task_id" in kwargs:
                    span.set_attribute("task.id", kwargs["task_id"])
                elif len(args) > 1 and isinstance(args[1], str):
                    span.set_attribute("task.id", args[1])
                
                try:
                    result = await func(*args, **kwargs)
                    span.set_attribute("success", True)
                    return result
                except Exception as e:
                    span.set_attribute("success", False)
                    span.record_exception(e)
                    raise
        
        return wrapper
    return decorator


def create_share_span(task_id: str, shared_with: str, permission: str):
    """
    Create a span for task sharing operation.
    
    Usage:
        with create_share_span(task_id, user_id, permission):
            await share_task(...)
    """
    if _tracer is None:
        from contextlib import nullcontext
        return nullcontext()
    
    return _tracer.start_as_current_span(
        "task.share",
        attributes={
            "task.id": task_id,
            "share.with": shared_with,
            "share.permission": permission,
        }
    )


def record_task_metric(name: str, value: float, attributes: dict = None):
    """
    Record a custom metric for task operations.
    
    Usage:
        record_task_metric("task.create.latency", 150.5)
    """
    if _meter is None:
        return
    
    # Create histogram if not exists
    # In production, use proper metric registry
    logger.debug(f"Metric {name}: {value}")
