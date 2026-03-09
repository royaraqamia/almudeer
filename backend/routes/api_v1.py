"""
Al-Mudeer - API Version 1 Router
All API endpoints with /api/v1/ prefix for proper versioning
"""

from fastapi import APIRouter

# Create versioned API router
router = APIRouter(prefix="/api/v1", tags=["API v1"])


# Re-export routes with versioning
# This allows gradual migration from /api/* to /api/v1/*

# Example usage in main.py:
# from routes.api_v1 import router as api_v1_router
# app.include_router(api_v1_router)

# Version info endpoint
@router.get("/version")
async def get_api_version():
    """Get API version information"""
    return {
        "version": "1.0.0",
        "api_prefix": "/api/v1",
        "deprecated_prefix": "/api",  # Old prefix still works
        "migration_status": "in_progress",
    }


# Note: Existing routes at /api/* continue to work
# New clients should use /api/v1/* for future compatibility
