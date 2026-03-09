"""
Al-Mudeer - Account Lifecycle Service
Handles high-level account actions like triggering real-time logout.
"""

from typing import Optional
from services.websocket_manager import get_websocket_manager, WebSocketMessage
from services.fcm_mobile_service import send_fcm_to_license
from logging_config import get_logger

logger = get_logger(__name__)

async def trigger_account_logout(license_id: int):
    """
    Trigger a real-time logout for all devices associated with a license.
    Broadcasts via WebSocket and sends a high-priority FCM notification.
    """
    logger.info(f"Triggering account logout for license {license_id}")
    
    # 1. Increment token_version in DB to invalidate all current JWTs server-side
    from database import get_db, execute_sql, commit_db
    try:
        async with get_db() as db:
            await execute_sql(db, "UPDATE license_keys SET token_version = token_version + 1 WHERE id = ?", [license_id])
            await commit_db(db)
            logger.info(f"Incremented token_version for license {license_id}")
    except Exception as e:
        logger.error(f"Failed to increment token_version for license {license_id}: {e}")
    
    # 1. Send WebSocket Signal
    try:
        # We send a specific event type that the mobile app will listen for
        message = WebSocketMessage(
            event="account_disabled",
            data={
                "license_id": license_id,
                "reason": "account_status_changed"
            }
        )
        manager = get_websocket_manager()
        await manager.send_to_license(license_id, message)
        logger.debug(f"WS logout signal published for license {license_id}")
    except Exception as e:
        logger.warning(f"Failed to send WS logout signal: {e}")

    # 2. Send FCM Push Notification
    try:
        # High priority notification to wake up the app if it's in background
        await send_fcm_to_license(
            license_id=license_id,
            title="تنبيه أمني", # Security Alert
            body="تم تسجيل الخروج من حسابك لسبب أمني أو انتهاء الاشتراك", # Logged out due to security or subscription expiry
            data={
                "type": "account_disabled",
                "priority": "high"
            }
        )
        logger.debug(f"FCM logout notification sent for license {license_id}")
    except Exception as e:
        logger.warning(f"Failed to send FCM logout notification: {e}")
