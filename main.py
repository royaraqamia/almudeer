"""
Al-Mudeer (المدير) - FastAPI Backend
B2B AI Agent for Syrian and Arab Market
"""

import os
import warnings

# Disable ChromaDB telemetry BEFORE any imports that might use it
# This fixes PostHog compatibility errors
os.environ["ANONYMIZED_TELEMETRY"] = "False"

# Suppress harmless Pydantic field shadowing warnings from ChromaDB
warnings.filterwarnings("ignore", message="Field name .* shadows an attribute in parent")

import json
import asyncio
from contextlib import asynccontextmanager
from typing import Optional
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

from fastapi import FastAPI, HTTPException, Depends, Header, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi.staticfiles import StaticFiles

# Performance middleware
from middleware import PerformanceMiddleware, SecurityHeadersMiddleware

# Logging
from logging_config import setup_logging, get_logger

# Setup logging
setup_logging(os.getenv("LOG_LEVEL", "INFO"))
logger = get_logger(__name__)
DEBUG_ERRORS = os.getenv("DEBUG_ERRORS", "0") == "1"

from database import (
    init_database,
    create_demo_license,
    validate_license_key,
    increment_usage,
    save_crm_entry,
    get_crm_entries,
    get_entry_by_id,
    generate_license_key,
)
from schemas import (
    ProcessingResponse,
    CRMEntryCreate,
    CRMEntry,
    CRMListResponse,
    CRMListResponse,
    HealthCheck,
    LicenseKeyCreate,
    MessageInput,
    AnalysisResult
)
# from agent import process_message (AI removed)
from models import (
    init_enhanced_tables,
    init_customers_and_analytics,
    get_preferences,
    get_recent_conversation,
)
from models.tasks import init_tasks_table
# Debug logging for imports
import logging
logger = logging.getLogger("startup")
try:
    from routes import (
        system_router,
        email_router,
        telegram_router,
        chat_router,
        features_router,
        whatsapp_router,
        export_router,
        notifications_router,
        library_router,
        auth_router,
        tasks,
        global_assets
    )
    from routes.tasks import router as tasks_router
    from routes.global_assets import router as global_assets_router
    from routes.knowledge import router as knowledge_router
    from routes.library_attachments import router as library_attachments_router
    from routes.devices import router as devices_router
    from routes.transfers import router as transfers_router
    from routes.qr_codes import router as qr_codes_router
    # Reactions router removed
    logger.info("Successfully imported modular routes")
except ImportError as e:
    logger.error(f"Failed to import routes: {e}")
    raise e
from routes.subscription import router as subscription_router
from errors import AuthorizationError, register_error_handlers
from security_config import SECURITY_HEADERS, ADMIN_KEY
from security import sanitize_message, sanitize_string
from workers import start_message_polling, stop_message_polling, start_subscription_reminders, stop_subscription_reminders, start_token_cleanup_worker, stop_token_cleanup_worker, start_library_trash_cleanup_worker, stop_library_trash_cleanup_worker
from db_pool import db_pool
from services.websocket_manager import get_websocket_manager, broadcast_new_message
from services.pagination import paginate_inbox, paginate_crm, paginate_customers, PaginationParams
from services.request_batcher import get_request_batcher, batch_analyze
from services.db_indexes import create_indexes
from services.telegram_listener_service import get_telegram_listener
from errors import AuthorizationError, register_error_handlers


# ============ App Lifecycle ============

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database on startup"""
    # Ensure logger is defined in local scope
    logger = logging.getLogger("startup")
    try:
        logger.info("Initializing Al-Mudeer backend...")

        # Initialize database connection pool (SQLite now, PostgreSQL-ready)
        try:
            await db_pool.initialize()
            logger.info(f"Database pool initialized using DB_TYPE={os.getenv('DB_TYPE', 'sqlite')}")
        except Exception as e:
            logger.warning(f"Database pool initialization failed (fallback to direct connections): {e}")
        
        # Run migrations first
        try:
            from migrations import migration_manager
            await migration_manager.migrate()
            logger.info("Database migrations completed")
        except Exception as e:
            logger.warning(f"Migration check failed (may be first run): {e}")

        # Ensure Full-Text Search setup
        try:
            from migrations.fts_setup import setup_full_text_search
            await setup_full_text_search()
        except Exception as e:
            logger.warning(f"FTS setup warning: {e}")
        
        await init_database()
        
        # Import necessary functions for parallelization
        from services.notification_service import init_notification_tables
        from services.push_service import log_vapid_status, ensure_push_subscription_table
        from migrations.users_table import create_users_table
        from migrations.fix_customers_serial import fix_customers_serial
        from migrations.backfill_queue_table import create_backfill_queue_table
        from migrations.task_queue_table import create_task_queue_table
        from migrations.edit_delete_message import ensure_message_edit_delete_schema
        from models.qr_codes import init_qr_tables

        # Parallelize independent table initializations to speed up startup
        init_tasks = [
            init_enhanced_tables(),
            init_notification_tables(),
            init_customers_and_analytics(),
            init_tasks_table(),
            create_indexes(),
            ensure_push_subscription_table(),
            create_users_table(),
            fix_customers_serial(),
            create_backfill_queue_table(),
            create_task_queue_table(),
            ensure_message_edit_delete_schema(),
            init_qr_tables(),
        ]
        
        results = await asyncio.gather(*init_tasks, return_exceptions=True)
        
        # Log any migration/init warnings
        for i, res in enumerate(results):
            if isinstance(res, Exception):
                logger.warning(f"Startup task {i} warning: {res}")
        
        logger.info("Database tables and indexes verified/created")

        # Log VAPID status after ensure_push_subscription_table might have run
        try:
            log_vapid_status()
        except Exception as e:
            logger.warning(f"VAPID status logging warning: {e}")
        
        # Ensure language/dialect columns exist in inbox_messages
        try:
            from migrations.manager import ensure_inbox_columns, ensure_outbox_columns
            await ensure_inbox_columns()
            await ensure_outbox_columns()
            logger.info("Inbox/Outbox columns verified")
        except Exception as e:
            logger.warning(f"Inbox/Outbox column migration warning: {e}")
        
        # Ensure user_preferences columns exist (tone, business_name, etc.)
        try:
            from migrations.manager import ensure_user_preferences_columns, ensure_inbox_conversations_pk
            await ensure_user_preferences_columns()
            await ensure_inbox_conversations_pk()
            logger.info("User preferences and inbox_conversations PK verified")
        except Exception as e:
            logger.warning(f"Schema verification warning (preferences/PK): {e}")
        
        # Ensure chat features schema exists (reactions, presence, voice)
        try:
            from migrations.chat_features import ensure_chat_features_schema
            await ensure_chat_features_schema()
            logger.info("Chat features schema verified (reactions, presence, voice)")
        except Exception as e:
            logger.warning(f"Chat features schema migration warning: {e}")
        
        # Fix int32 range issues for message IDs (BIGINT migration)
        try:
            from migrations.fix_int32_range import fix_int32_range_issues
            await fix_int32_range_issues()
            logger.info("Int32 range fixes applied (message IDs now BIGINT)")
        except Exception as e:
            logger.warning(f"Int32 range fix migration warning: {e}")
        
        demo_key = await create_demo_license()
        if demo_key:
            logger.info(f"Demo license key created: {demo_key[:20]}...")
            print(f"\n{'='*50}")
            print(f"Demo License Key: {demo_key}")
            print(f"{'='*50}\n")
        
        # Start background workers for message polling
        try:
            await start_message_polling()
            logger.info("Message polling workers started")
        except Exception as e:
            logger.warning(f"Failed to start message polling workers: {e}")

        try:
            await start_subscription_reminders()
            logger.info("Subscription reminder worker started")
        except Exception as e:
            logger.warning(f"Failed to start subscription reminder worker: {e}")

        # P1-6 FIX: Start token blacklist cleanup background task
        try:
            async def cleanup_blacklist_periodically():
                """Clean up expired token blacklist entries daily"""
                from services.token_blacklist import cleanup_token_blacklist
                while True:
                    await asyncio.sleep(86400)  # 24 hours
                    try:
                        await cleanup_token_blacklist()
                        logger.info("Token blacklist cleanup completed")
                    except Exception as e:
                        logger.error(f"Token blacklist cleanup failed: {e}")

            # Start cleanup task in background
            asyncio.create_task(cleanup_blacklist_periodically())
            logger.info("Token blacklist cleanup task started (runs daily)")
        except Exception as e:
            logger.warning(f"Failed to start token blacklist cleanup task: {e}")

        # Start metrics collection (monitoring)
        try:
            from services.metrics_service import start_metrics_collection
            await start_metrics_collection(interval_seconds=60)
            logger.info("Metrics collection started (60s interval)")
        except Exception as e:
            logger.warning(f"Failed to start metrics collection: {e}")
        
        # Start FCM token cleanup worker (daily)
        try:
            await start_token_cleanup_worker()
            logger.info("FCM token cleanup worker started")
        except Exception as e:
            logger.warning(f"Failed to start FCM token cleanup worker: {e}")

        # Start Library Trash cleanup worker (daily - auto-delete after 30 days)
        try:
            await start_library_trash_cleanup_worker()
            logger.info("Library Trash cleanup worker started")
        except Exception as e:
            logger.warning(f"Failed to start Library Trash cleanup worker: {e}")

        # Initialize task queue worker
        try:
            from workers import TaskWorker
            task_worker = TaskWorker()
            await task_worker.start()
            logger.info("Persistent Task Queue Worker started")
            
            # Keep reference to prevent GC
            app.state.task_worker = task_worker
        except Exception as e:
            logger.warning(f"Task queue initialization warning: {e}")
        
        # Start Telegram Listener Service (Persistent)
        try:
            telegram_listener = get_telegram_listener()
            await telegram_listener.start()
            logger.info("Telegram Persistent Listener started")
        except Exception as e:
            logger.warning(f"Failed to start Telegram Listener: {e}")
        
        logger.info("Al-Mudeer backend initialized successfully")
        
        # Clean up stale presence counters from previous server runs
        try:
            ws_manager = get_websocket_manager()
            await ws_manager._ensure_pubsub()
            await ws_manager.cleanup_stale_presence()
        except Exception as e:
            logger.warning(f"Presence cleanup on startup: {e}")

        # Refresh APK cache on startup to ensure fresh hash/size after deployment
        try:
            from routes.version import _refresh_apk_cache
            _refresh_apk_cache(force=True)
            logger.info("APK cache refreshed on startup")
        except Exception as e:
            logger.warning(f"APK cache refresh on startup: {e}")

        # CRITICAL FIX #5: Start periodic rate limiter cleanup task
        # Prevents memory leak from stale rate limit entries
        async def cleanup_rate_limiter_periodically():
            """Clean up stale rate limiter entries every 5 minutes."""
            from routes.version import _rate_limiter
            while True:
                await asyncio.sleep(300)  # Every 5 minutes
                try:
                    _rate_limiter.cleanup_old_entries()
                    logger.debug("Rate limiter stale entries cleaned")
                except Exception as e:
                    logger.warning(f"Rate limiter cleanup failed: {e}")

        # CRITICAL FIX #1: Start periodic ETag cache refresh task
        # Ensures cache is refreshed proactively instead of on-demand
        async def refresh_etag_cache_periodically():
            """Refresh ETag cache every 5 minutes to keep it fresh."""
            from routes.version import _refresh_etag_cache
            while True:
                await asyncio.sleep(300)  # Every 5 minutes
                try:
                    await _refresh_etag_cache()
                    logger.debug("ETag cache refreshed proactively")
                except Exception as e:
                    logger.warning(f"ETag cache refresh failed: {e}")

        # CDN Health Check - Periodic monitoring of CDN availability
        async def check_cdn_health_periodically():
            """Check CDN health every 2 minutes and log warnings."""
            from routes.version import _CDN_HEALTH_CACHE, _verify_cdn_health, _APK_CDN_VARIANTS
            while True:
                await asyncio.sleep(120)  # Every 2 minutes
                try:
                    for arch, url in _APK_CDN_VARIANTS.items():
                        if url:
                            # Use longer timeout for large APK files behind Cloudflare
                            is_healthy = await _verify_cdn_health(url, timeout=10.0, retries=2)
                            _CDN_HEALTH_CACHE[arch] = {
                                "healthy": is_healthy,
                                "last_check": asyncio.get_event_loop().time()
                            }
                            if not is_healthy:
                                logger.warning(f"⚠️ CDN unhealthy for {arch}: {url[:50]}...")
                            else:
                                logger.debug(f"✅ CDN healthy for {arch}")
                except Exception as e:
                    logger.warning(f"CDN health check failed: {e}")

        # Start background cleanup tasks
        asyncio.create_task(cleanup_rate_limiter_periodically())
        asyncio.create_task(refresh_etag_cache_periodically())
        asyncio.create_task(check_cdn_health_periodically())
        logger.info("Background cleanup tasks started")

        print("Al-Mudeer Premium Backend Ready!")
        print("Customers & Notifications tables initialized")
        print("Background workers active for automatic message processing")
    except Exception as e:
        logger.error(f"Failed to initialize backend: {e}", exc_info=True)
        raise
    yield
    # Shutdown
    try:
        await stop_message_polling()
        logger.info("Message polling workers stopped")
    except Exception as e:
        logger.warning(f"Error stopping workers: {e}")
    try:
        await stop_subscription_reminders()
        logger.info("Subscription reminder worker stopped")
    except Exception as e:
        logger.warning(f"Error stopping subscription reminder: {e}")
    try:
        await stop_token_cleanup_worker()
        logger.info("FCM token cleanup worker stopped")
    except Exception as e:
        logger.warning(f"Error stopping token cleanup worker: {e}")
    try:
        await stop_library_trash_cleanup_worker()
        logger.info("Library Trash cleanup worker stopped")
    except Exception as e:
        logger.warning(f"Error stopping Library Trash cleanup: {e}")
    try:
        if hasattr(app.state, "task_worker"):
            await app.state.task_worker.stop()
            logger.info("Persistent Task Queue Worker stopped")
    except Exception as e:
        logger.warning(f"Error stopping task queue: {e}")
    try:
        telegram_listener = get_telegram_listener()
        await telegram_listener.stop()
        logger.info("Telegram Persistent Listener stopped")
    except Exception as e:
        logger.warning(f"Error stopping Telegram Listener: {e}")
    try:
        await db_pool.close()
        logger.info("Database pool closed")
    except Exception as e:
        logger.warning(f"Error closing database pool: {e}")
    logger.info("Shutting down Al-Mudeer backend...")


# ============ Create App ============

app = FastAPI(
    title="Al-Mudeer API",
    description="B2B AI Agent for Syrian and Arab Market",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_tags=[
        {"name": "System", "description": "System endpoints (health, etc.)"},
        {"name": "Authentication", "description": "License key validation"},
        {"name": "Admin", "description": "Admin operations (license management)"},
        {"name": "Analysis", "description": "Message analysis and processing"},
        {"name": "CRM", "description": "Customer relationship management"},
    ]
)

# Register structured error handlers
register_error_handlers(app)

# Root endpoint - Redirect to APK download
@app.get("/", tags=["System"])
async def root():
    """Root endpoint redirecting to APK download"""
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/apk")

# Metrics endpoint (monitoring dashboard)
@app.get("/metrics", tags=["System"])
async def metrics_endpoint():
    """
    System health and performance metrics.
    For monitoring dashboards and alerting systems.
    """
    from services.metrics_service import get_metrics_endpoint
    return await get_metrics_endpoint()

# Rate Limiting
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Gzip Compression (reduces bandwidth by 60-80% for JSON responses)
from starlette.middleware.gzip import GZipMiddleware
app.add_middleware(GZipMiddleware, minimum_size=500)  # Compress responses > 500 bytes

# Performance & Security Middleware (Order matters!)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(PerformanceMiddleware)

# CORS for frontend (optimized for Arab World)
frontend_urls = [
    "http://localhost:3000",
    "http://localhost:3001",
    "http://localhost:3100",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:3100",
    "https://almudeer.royaraqamia.com",
    "https://www.almudeer.royaraqamia.com",
    "https://almudeer.up.railway.app",
    os.getenv("FRONTEND_URL", "https://almudeer.royaraqamia.com")
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=frontend_urls,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    max_age=86400,  # Cache CORS preflight for 24 hours (better for Arab World latency)
)

# Include routes (legacy /api/ prefix for backward compatibility)
# Include modular routes
logger.info("Including modular routers")
app.include_router(system_router)
app.include_router(email_router)
app.include_router(telegram_router)
app.include_router(chat_router)
app.include_router(features_router)
app.include_router(whatsapp_router)

app.include_router(export_router)          # Export & Reports
app.include_router(notifications_router)   # Smart Notifications & Integrations
app.include_router(knowledge_router)       # Knowledge Base Documents & Uploads
app.include_router(library_router)         # Library of Everything
app.include_router(library_attachments_router)  # Library Attachments (P3-12)
app.include_router(devices_router)         # Device Pairing (P3-1/Nearby)
app.include_router(transfers_router)       # Transfer Management (P3-1/Nearby)
app.include_router(qr_codes_router)          # QR Code Generation & Verification
app.include_router(tasks_router)           # Task Management
app.include_router(subscription_router)    # Subscription Key Management
app.include_router(global_assets_router)   # Admin Global Assets
app.include_router(auth_router)             # Authentication (login, etc)


# Browser routes (scraper, link preview)
try:
    from routes.browser import router as browser_router
    app.include_router(browser_router)
except Exception as e:
    logger.warning(f"Browser router not loaded: {e}")

# Health check endpoints (no prefix, accessible at root level)
from health_check import router as health_router
app.include_router(health_router)

# Version check endpoint (public, for force-update system)
# Also includes /download/almudeer.apk endpoint for APK downloads
from routes.version import router as version_router

app.include_router(version_router)

# Sync routes for offline operation support
from routes.sync import router as sync_router
app.include_router(sync_router)

# Create specific mount for uploads (persistent volume on Railway)
UPLOAD_DIR = os.getenv("UPLOAD_DIR", os.path.join(os.getcwd(), "static", "uploads"))
if not os.path.exists(UPLOAD_DIR):
    os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/static/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

# General static mount for code-relative assets
static_dir = os.path.join(os.getcwd(), "static")
if not os.path.exists(static_dir):
    os.makedirs(static_dir, exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/debug/routes")
async def list_all_routes(x_admin_key: str = Header(None, alias="X-Admin-Key")):
    """List all registered routes for debugging (development only, or requires admin key)"""
    import logging
    
    # SECURITY: Only allow in development OR with admin key
    is_production = os.getenv("ENVIRONMENT", "development") == "production"
    
    if is_production:
        # In production, require admin key
        if not x_admin_key or x_admin_key != ADMIN_KEY:
            raise AuthorizationError(
                message="Debug endpoint not available in production without admin key",
                message_ar="عذراً، هذا الإجراء غير متاح في بيئة الإنتاج"
            )
    
    logger = logging.getLogger("debug")
    routes = []
    for route in app.routes:
        routes.append({
            "path": route.path,
            "name": route.name,
            "methods": list(route.methods) if hasattr(route, "methods") else None
        })
    logger.info(f"Listing {len(routes)} routes")
    return {"count": len(routes), "routes": routes}

# Style learning removed

# API Version 1 routes (new /api/v1/ prefix)
# These mirror the legacy routes but with versioned prefix for future compatibility
from fastapi import APIRouter
v1_router = APIRouter(prefix="/api/v1")
v1_router.include_router(system_router)
v1_router.include_router(email_router)
v1_router.include_router(telegram_router)
v1_router.include_router(chat_router)
v1_router.include_router(features_router)
v1_router.include_router(whatsapp_router)
v1_router.include_router(library_router)

v1_router.include_router(export_router.router if hasattr(export_router, 'router') else export_router, prefix="")
v1_router.include_router(notifications_router.router if hasattr(notifications_router, 'router') else notifications_router, prefix="")
v1_router.include_router(subscription_router, prefix="")
# Note: v1_router is prepared but routes already have /api/ prefix
# Future versions can modify prefixes as needed


# ============ License Key Middleware ============
from dependencies import get_license_from_header


from errors import (
    AuthenticationError, 
    NotFoundError, 
    AuthorizationError, 
    ValidationError
)

# ... (omitted imports)

# LEGACY: Use get_license_from_header from dependencies instead
async def verify_license(x_license_key: str = Header(None, alias="X-License-Key")) -> dict:
    """Dependency to verify license key from header"""
    if not x_license_key:
        logger.warning("License key missing in request header")
        raise AuthenticationError(
            message="License key required",
            message_ar="مفتاح الاشتراك مطلوب للمتابعة"
        )
    
    result = await validate_license_key(x_license_key)
    
    if not result["valid"]:
        logger.warning(f"Invalid license key attempt: {x_license_key[:10]}...")
        raise AuthenticationError(
            message=result["error"],
            message_ar="مفتاح الاشتراك غير صالح أو منتهي الصلاحية"
        )
    
    logger.debug(f"License validated for user: {result.get('full_name')}")
    return result

# ...

async def verify_admin(x_admin_key: str = Header(None, alias="X-Admin-Key")):
    """Verify admin key"""
    if not x_admin_key or x_admin_key != ADMIN_KEY:
        raise AuthorizationError(
            message="Admin access denied",
            message_ar="عذراً، هذا الإجراء مخصص للمسؤولين فقط"
        )


@app.post("/api/admin/license/create", tags=["Admin"])
async def create_license(data: LicenseKeyCreate, _: None = Depends(verify_admin)):
    """
    Create a new license key (admin only).
    
    Requires: X-Admin-Key header
    
    Args:
        data: License key creation request
        
    Returns:
        Generated license key
    """
    logger.info(f"Creating license for user: {data.full_name}")
    key = await generate_license_key(
        full_name=data.full_name,
        contact_email=data.contact_email,
        days_valid=data.days_valid
    )
    logger.info(f"License created: {key[:20]}...")
    return {"success": True, "license_key": key}


# ============ Protected Routes (Require License Key) ============

# AI analysis endpoints removed


# ============ WebSocket Real-time Updates ============

from fastapi import WebSocket, WebSocketDisconnect

async def handle_websocket_connection(websocket: WebSocket, credential: str):
    """
    Shared WebSocket connection handler supporting both license keys and JWT tokens.
    
    SECURITY FIX #11: WebSocket authentication now supports JWT tokens.
    License keys in URL/query params are still supported for backward compatibility.
    """
    from dependencies import resolve_license
    from services.jwt_auth import verify_token, TokenType
    
    license_id = None
    
    # Try to validate as JWT token first
    if credential.startswith("eyJ"):
        # Looks like a JWT token - validate it
        payload = verify_token(credential, TokenType.ACCESS)
        if payload and payload.get("license_id"):
            license_id = payload.get("license_id")
            logger.debug(f"WebSocket authenticated via JWT for license {license_id}")
        else:
            # Invalid JWT
            await websocket.accept()
            await websocket.close(code=4001, reason="Invalid or expired token")
            return
    else:
        # Treat as license key (legacy method)
        try:
            license_result = await resolve_license(credential)
            license_id = license_result["license_id"]
            logger.debug(f"WebSocket authenticated via license key for license {license_id}")
        except Exception:
            await websocket.accept()
            await websocket.close(code=4001, reason="Invalid credential")
            return

    manager = get_websocket_manager()

    try:
        await manager.connect(websocket, license_id)
        while True:
            # Keep connection alive, handle pings
            data = await websocket.receive_text()

            # Handle both simple "ping" string and JSON ping object
            is_ping = False

            if data == "ping":
                is_ping = True
            elif data.startswith("{") and '"ping"' in data:
                try:
                    import json
                    ping_data = json.loads(data)
                    if ping_data.get("event") == "ping":
                        is_ping = True
                except Exception:
                    pass

            if is_ping:
                await websocket.send_text('{"event":"pong"}')

                # Refresh presence for primary account
                await manager.refresh_last_seen(license_id)

                if manager.redis_enabled:
                    try:
                        key = f"almudeer:presence:count:{license_id}"
                        await manager.redis_client.expire(key, 120)
                    except Exception:
                        pass
    except WebSocketDisconnect:
        # Normal disconnect
        await manager.disconnect(websocket, license_id)
    except Exception as e:
        # Log unexpected errors but ensure we disconnect
        logger.error(f"Unexpected WebSocket error for license {license_id}: {e}", exc_info=True)
        try:
            await manager.disconnect(websocket, license_id)
        except Exception:
            # Do NOT re-raise, as that causes the "RuntimeError: WebSocket is not connected"
            pass
        # Do NOT re-raise, as that causes the "RuntimeError: WebSocket is not connected" 
        # when Starlette tries to send an error response to a closed/failed WS.


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint supporting multiple authentication methods:
    1. Authorization: Bearer <JWT_TOKEN> (preferred, most secure)
    2. X-License-Key: <LICENSE_KEY> (legacy)
    3. Query parameter: /ws?license=KEY (legacy, for backward compatibility)
    4. Path parameter: /ws/KEY (legacy, for backward compatibility)
    
    SECURITY FIX #11: JWT authentication is now the primary method.
    License keys are still supported for backward compatibility.
    """
    # Method 1: Try Authorization header with Bearer token (JWT)
    credential = None
    auth_header = websocket.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        credential = auth_header[7:].strip()
        logger.debug("WebSocket auth: Using Authorization header")

    # Method 2: Try X-License-Key header (legacy)
    if not credential:
        credential = websocket.headers.get("X-License-Key")
        if credential:
            logger.debug("WebSocket auth: Using X-License-Key header")

    # Method 3: Fallback to query parameter (legacy)
    if not credential:
        from urllib.parse import parse_qs, urlparse
        parsed = urlparse(str(websocket.url))
        query_params = parse_qs(parsed.query)
        credential = query_params.get("license", [None])[0]
        if credential:
            logger.debug("WebSocket auth: Using query parameter (legacy)")

    if not credential:
        await websocket.close(
            code=4003,
            reason="Authentication required (use Authorization: Bearer <token> header, X-License-Key header, or ?license=KEY query param)"
        )
        return

    await handle_websocket_connection(websocket, credential)


@app.websocket("/ws/{license_key}")
async def websocket_endpoint_path(websocket: WebSocket, license_key: str):
    """
    WebSocket endpoint supporting path parameter: /ws/KEY
    Legacy endpoint for backward compatibility.
    Note: Header-based auth is preferred for security.
    """
    # Check if header is provided (overrides path for security)
    header_license = websocket.headers.get("X-License-Key")
    if header_license:
        license_key = header_license
    
    await handle_websocket_connection(websocket, license_key)


# ============ Paginated Endpoints ============

@app.get("/api/inbox/paginated", tags=["CRM"])
async def get_inbox_paginated(
    page: int = 1,
    page_size: int = 20,
    channel: str = None,
    is_read: bool = None,
    license: dict = Depends(get_license_from_header)
):
    """
    Get inbox messages with pagination.
    
    Returns:
        - items: List of messages
        - pagination: {total, page, page_size, total_pages, has_next, has_prev}
    """
    return await paginate_inbox(
        license_id=license["license_id"],
        page=page,
        page_size=page_size,
        channel=channel,
        is_read=is_read,
    )


@app.get("/api/crm/paginated", tags=["CRM"])
async def get_crm_paginated(
    page: int = 1,
    page_size: int = 20,
    license: dict = Depends(get_license_from_header)
):
    """
    Get CRM entries with pagination.
    """
    return await paginate_crm(
        license_id=license["license_id"],
        page=page,
        page_size=page_size,
    )


@app.get("/api/customers/paginated", tags=["CRM"])
@app.get("/api/customers", tags=["CRM"])
async def get_customers_paginated(
    page: int = 1,
    page_size: int = 20,
    search: str = None,
    license: dict = Depends(get_license_from_header)
):
    """
    Get customers with pagination and optional search.
    Supports both /api/customers/paginated and legacy /api/customers
    """
    return await paginate_customers(
        license_id=license["license_id"],
        page=page,
        page_size=page_size,
        search=search,
    )

# Draft response endpoint removed (AI)


@app.post("/api/crm/save", tags=["CRM"])
async def save_to_crm(
    data: CRMEntryCreate,
    license: dict = Depends(get_license_from_header)
):
    """
    Save an entry to CRM.
    
    Requires: X-License-Key header
    
    Args:
        data: CRM entry data
        
    Returns:
        Success status and entry ID
    """
    await increment_usage(
        license["license_id"],
        "crm_save",
        data.original_message[:100] if data.original_message else None
    )
    
    entry_id = await save_crm_entry(
        license_id=license["license_id"],
        sender_name=data.sender_name,
        sender_contact=data.sender_contact,
        message_type=data.message_type,
        intent=data.intent,
        extracted_data=data.extracted_data,
        original_message=data.original_message,
        draft_response=data.draft_response
    )
    
    return {"success": True, "entry_id": entry_id, "message": "تم الحفظ بنجاح"}


# AI usage endpoint removed

@app.get("/api/crm/entries", response_model=CRMListResponse, tags=["CRM"])
async def list_crm_entries(
    limit: int = 50,
    license: dict = Depends(get_license_from_header)
):
    """
    List CRM entries.
    
    Requires: X-License-Key header
    
    Args:
        limit: Maximum number of entries to return (default: 50)
        
    Returns:
        List of CRM entries
    """
    entries = await get_crm_entries(license["license_id"], limit)
    
    return CRMListResponse(
        entries=[CRMEntry(**e) for e in entries],
        total=len(entries)
    )


@app.get("/api/crm/entries/{entry_id}", tags=["CRM"])
async def get_crm_entry(
    entry_id: int,
    license: dict = Depends(get_license_from_header)
):
    """
    Get a specific CRM entry by ID.
    
    Requires: X-License-Key header
    
    Args:
        entry_id: CRM entry ID
        
    Returns:
        CRM entry details
    """
    entry = await get_entry_by_id(entry_id, license["license_id"])
    
    if not entry:
        raise HTTPException(status_code=404, detail="السجل غير موجود")
    
    return {"success": True, "entry": CRMEntry(**entry)}


@app.get("/api/auth/me", tags=["Authentication"])
async def get_user_info(license: dict = Depends(get_license_from_header)):
    """
    Get current user/license information.
    
    Requires: X-License-Key header
    
    Returns:
        License details including company name, expiration, and remaining requests
    """
    return {
        "company_name": license.get("full_name", "Unknown"),
        "created_at": license.get("created_at"),
        "expires_at": license["expires_at"],
        "requests_remaining": license["requests_remaining"]
    }


# ============ Error Handlers ============

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    # Reduce noise: 404 errors are normal and shouldn't be Warnings
    if exc.status_code == 404:
        logger.info(
            f"HTTP 404 Not Found: {exc.detail}",
            extra={"extra_fields": {"path": request.url.path}}
        )
    else:
        logger.warning(
            f"HTTP {exc.status_code} error: {exc.detail}",
            extra={"extra_fields": {"path": request.url.path, "method": request.method}}
        )
        
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": exc.detail}
    )


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    logger.warning(
        f"Rate limit exceeded for {get_remote_address(request)}",
        extra={"extra_fields": {"path": request.url.path, "ip": get_remote_address(request)}}
    )
    return JSONResponse(
        status_code=429,
        content={"success": False, "error": "تم تجاوز الحد المسموح. يرجى المحاولة لاحقاً"}
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    logger.error(
        f"Unhandled exception: {exc}",
        exc_info=True,
        extra={"extra_fields": {"path": request.url.path, "method": request.method}}
    )
    payload = {"success": False, "error": "حدث خطأ في الخادم"}
    # When DEBUG_ERRORS=1 (set via env variable), include debug info in response
    if DEBUG_ERRORS:
        payload["debug"] = {
            "type": type(exc).__name__,
            "message": str(exc),
        }
    return JSONResponse(status_code=500, content=payload)


# ============ Run Server ============

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )

