"""
Al-Mudeer - Security Event Logger
Logs security-relevant events for monitoring and forensics
"""

import os
import json
from datetime import datetime
from typing import Optional, Any
from enum import Enum

from logging_config import get_logger

logger = get_logger(__name__)


class SecurityEventType(Enum):
    """Types of security events to log."""
    LOGIN_SUCCESS = "login_success"
    LOGIN_FAILED = "login_failed"
    LOGOUT = "logout"
    ACCOUNT_LOCKED = "account_locked"
    TOKEN_BLACKLISTED = "token_blacklisted"
    INVALID_TOKEN = "invalid_token"
    UNAUTHORIZED_ACCESS = "unauthorized_access"
    ADMIN_ACTION = "admin_action"
    SUSPICIOUS_ACTIVITY = "suspicious_activity"
    PASSWORD_CHANGED = "password_changed"
    RATE_LIMIT_EXCEEDED = "rate_limit_exceeded"
    WEBHOOK_REJECTED = "webhook_rejected"


class SecurityLogger:
    """
    Centralized security event logging.
    Writes to both application logs and optionally to a dedicated security log file.
    """
    
    def __init__(self):
        self._security_log_path = os.getenv("SECURITY_LOG_PATH", "security_events.log")
        self._log_to_file = os.getenv("SECURITY_LOG_TO_FILE", "true").lower() == "true"
    
    def log_event(
        self,
        event_type: SecurityEventType,
        identifier: Optional[str] = None,
        ip_address: Optional[str] = None,
        details: Optional[dict] = None,
        severity: str = "INFO"
    ):
        """
        Log a security event.
        
        Args:
            event_type: Type of security event
            identifier: User identifier (email, license key, etc.)
            ip_address: Client IP address
            details: Additional event details
            severity: Log level (INFO, WARNING, ERROR, CRITICAL)
        """
        event = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "event_type": event_type.value,
            "identifier": self._mask_identifier(identifier),
            "ip_address": ip_address,
            "details": details or {},
            "severity": severity
        }
        
        # Log to application logger
        log_message = f"SECURITY: {event_type.value}"
        if identifier:
            log_message += f" | user={self._mask_identifier(identifier)}"
        if ip_address:
            log_message += f" | ip={ip_address}"
        if details:
            log_message += f" | {json.dumps(details)}"
        
        if severity == "CRITICAL":
            logger.critical(log_message)
        elif severity == "ERROR":
            logger.error(log_message)
        elif severity == "WARNING":
            logger.warning(log_message)
        else:
            logger.info(log_message)
        
        # Also write to dedicated security log file
        if self._log_to_file:
            self._write_to_file(event)
    
    def _mask_identifier(self, identifier: Optional[str]) -> Optional[str]:
        """Mask sensitive parts of identifiers for logging."""
        if not identifier:
            return None
        
        if "@" in identifier:
            # Email: show first 2 chars + domain
            parts = identifier.split("@")
            if len(parts[0]) > 2:
                return f"{parts[0][:2]}***@{parts[1]}"
            return f"***@{parts[1]}"
        elif len(identifier) > 8:
            # License key or other: show first 4 and last 4
            return f"{identifier[:4]}...{identifier[-4:]}"
        else:
            return "***"
    
    def _write_to_file(self, event: dict):
        """Write event to security log file."""
        try:
            with open(self._security_log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(event) + "\n")
        except Exception as e:
            logger.error(f"Failed to write security log: {e}")
    
    # Convenience methods for common events
    
    def log_login_success(self, identifier: str, ip_address: str = None):
        """Log successful login."""
        self.log_event(
            SecurityEventType.LOGIN_SUCCESS,
            identifier=identifier,
            ip_address=ip_address
        )
    
    def log_login_failed(self, identifier: str, ip_address: str = None, reason: str = None):
        """Log failed login attempt."""
        self.log_event(
            SecurityEventType.LOGIN_FAILED,
            identifier=identifier,
            ip_address=ip_address,
            details={"reason": reason} if reason else None,
            severity="WARNING"
        )
    
    def log_account_locked(self, identifier: str, ip_address: str = None, attempts: int = None):
        """Log account lockout."""
        self.log_event(
            SecurityEventType.ACCOUNT_LOCKED,
            identifier=identifier,
            ip_address=ip_address,
            details={"failed_attempts": attempts} if attempts else None,
            severity="WARNING"
        )
    
    def log_logout(self, identifier: str, ip_address: str = None):
        """Log user logout."""
        self.log_event(
            SecurityEventType.LOGOUT,
            identifier=identifier,
            ip_address=ip_address
        )
    
    def log_token_blacklisted(self, identifier: str, jti: str = None):
        """Log token blacklisting."""
        self.log_event(
            SecurityEventType.TOKEN_BLACKLISTED,
            identifier=identifier,
            details={"jti": jti[:8] + "..." if jti else None}
        )
    
    def log_invalid_token(self, ip_address: str = None, reason: str = None):
        """Log invalid token usage attempt."""
        self.log_event(
            SecurityEventType.INVALID_TOKEN,
            ip_address=ip_address,
            details={"reason": reason} if reason else None,
            severity="WARNING"
        )
    
    def log_unauthorized_access(self, identifier: str = None, ip_address: str = None, resource: str = None):
        """Log unauthorized access attempt."""
        self.log_event(
            SecurityEventType.UNAUTHORIZED_ACCESS,
            identifier=identifier,
            ip_address=ip_address,
            details={"resource": resource} if resource else None,
            severity="WARNING"
        )
    
    def log_admin_action(self, admin_id: str, action: str, target: str = None):
        """Log admin action."""
        self.log_event(
            SecurityEventType.ADMIN_ACTION,
            identifier=admin_id,
            details={"action": action, "target": target}
        )
    
    def log_suspicious_activity(self, identifier: str = None, ip_address: str = None, description: str = None):
        """Log suspicious activity."""
        self.log_event(
            SecurityEventType.SUSPICIOUS_ACTIVITY,
            identifier=identifier,
            ip_address=ip_address,
            details={"description": description} if description else None,
            severity="ERROR"
        )
    
    def log_rate_limit_exceeded(self, identifier: str = None, ip_address: str = None, endpoint: str = None):
        """Log rate limit exceeded."""
        self.log_event(
            SecurityEventType.RATE_LIMIT_EXCEEDED,
            identifier=identifier,
            ip_address=ip_address,
            details={"endpoint": endpoint} if endpoint else None,
            severity="WARNING"
        )


# Singleton instance
_security_logger: Optional[SecurityLogger] = None


def get_security_logger() -> SecurityLogger:
    """Get the global security logger instance."""
    global _security_logger
    if _security_logger is None:
        _security_logger = SecurityLogger()
    return _security_logger


# Convenience exports
def log_security_event(event_type: SecurityEventType, **kwargs):
    """Log a security event."""
    get_security_logger().log_event(event_type, **kwargs)
