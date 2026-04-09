"""
Al-Mudeer - Password Reset Service
Handles password reset flow with secure tokens

Features:
- Secure token generation (UUID-based)
- Token expiry (default 1 hour)
- One-time use tokens (invalidated after use)
- Password reset via email
"""

import os
import uuid
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

from db_helper import get_db, fetch_one, execute_sql, commit_db
from services.password_service import hash_password, validate_password_strength
from logging_config import get_logger

logger = get_logger(__name__)

# Password Reset Configuration
RESET_TOKEN_EXPIRY_HOURS = int(os.getenv("RESET_TOKEN_EXPIRY_HOURS", "1"))


class PasswordResetService:
    """
    Service for managing password reset flow.
    
    Usage:
        service = PasswordResetService()
        await service.initiate_reset("user@example.com")  # Sends email
        await service.reset_password(token, "newpassword")  # Resets password
    """
    
    def generate_reset_token(self) -> str:
        """
        Generate a cryptographically secure reset token.
        
        Returns:
            Secure random token string (URL-safe)
        """
        # Combine UUID with additional entropy for maximum security
        token_part1 = uuid.uuid4().hex
        token_part2 = secrets.token_urlsafe(32)
        return f"{token_part1}_{token_part2}"
    
    async def initiate_reset(self, email: str) -> Tuple[bool, str]:
        """
        Initiate password reset: generate token, store in DB, and send email.
        
        Note: Always returns success even if email doesn't exist
        (prevents email enumeration attacks).
        
        Args:
            email: User's email address
        
        Returns:
            Tuple of (success, error_message)
            - (True, "") if reset email was sent (or email doesn't exist)
            - (False, "error message") only on system errors
        """
        from services.email_service import get_email_service
        
        try:
            async with get_db() as db:
                # Check if user exists
                user = await fetch_one(
                    db,
                    "SELECT id, is_email_verified FROM user_accounts WHERE email = ?",
                    [email.lower()]
                )
                
                if not user:
                    # SECURITY: Don't reveal if email exists or not
                    # Still return success to prevent email enumeration
                    logger.info(f"Password reset requested for non-existent email: {email}")
                    return True, ""
                
                # Check if email is verified
                if not user.get("is_email_verified"):
                    return False, "يجب التحقق من البريد الإلكتروني أولاً"
                
                # Generate reset token
                reset_token = self.generate_reset_token()
                reset_token_expires_at = datetime.now(timezone.utc) + timedelta(hours=RESET_TOKEN_EXPIRY_HOURS)
                
                # Store token in database
                await execute_sql(
                    db,
                    """
                    UPDATE user_accounts 
                    SET reset_token = ?, reset_token_expires_at = ?, updated_at = NOW()
                    WHERE id = ?
                    """,
                    [reset_token, reset_token_expires_at, user["id"]]
                )
                await commit_db(db)
                
                # Send reset email
                email_service = get_email_service()
                email_sent = await email_service.send_password_reset_email(email, reset_token)
                
                if not email_sent:
                    logger.error(f"Failed to send password reset email to {email}")
                    # Note: Token is still valid in DB even if email fails
                
                logger.info(f"Password reset initiated for user {user['id']} (email: {email})")
                return True, ""
                
        except Exception as e:
            logger.error(f"Error in initiate_reset for {email}: {e}")
            return False, f"خطأ في بدء إعادة تعيين كلمة المرور: {str(e)}"
    
    async def reset_password(self, token: str, new_password: str) -> Tuple[bool, str]:
        """
        Reset password using valid reset token.
        
        Args:
            token: Reset token from email
            new_password: New password to set
        
        Returns:
            Tuple of (success, error_message)
            - (True, "") if password was reset successfully
            - (False, "error message") if token is invalid/expired or password is weak
        """
        try:
            # Validate password strength
            is_valid, error_msg = validate_password_strength(new_password)
            if not is_valid:
                return False, error_msg
            
            async with get_db() as db:
                # Find user with valid token
                user = await fetch_one(
                    db,
                    """
                    SELECT id, reset_token, reset_token_expires_at 
                    FROM user_accounts 
                    WHERE reset_token = ?
                    """,
                    [token]
                )
                
                if not user:
                    return False, "رمز إعادة تعيين غير صالح"
                
                # Check if token expired
                expires_at = user.get("reset_token_expires_at")
                if expires_at and expires_at < datetime.now(timezone.utc):
                    return False, "انتهت صلاحية رمز إعادة تعيين. يرجى طلب رمز جديد"
                
                # Hash new password
                password_hash = hash_password(new_password)
                
                # Update password and clear reset token
                await execute_sql(
                    db,
                    """
                    UPDATE user_accounts 
                    SET password_hash = ?, reset_token = NULL, reset_token_expires_at = NULL,
                        updated_at = NOW(), last_login = NOW()
                    WHERE id = ?
                    """,
                    [password_hash, user["id"]]
                )
                await commit_db(db)
                
                logger.info(f"Password reset successfully for user {user['id']}")
                return True, ""
                
        except Exception as e:
            logger.error(f"Error in reset_password: {e}")
            return False, f"خطأ في إعادة تعيين كلمة المرور: {str(e)}"
    
    async def invalidate_token(self, email: str) -> bool:
        """
        Invalidate any existing reset tokens for a user.
        Called after successful password reset or user request.
        
        Args:
            email: User's email address
        
        Returns:
            True if tokens were invalidated, False on error
        """
        try:
            async with get_db() as db:
                await execute_sql(
                    db,
                    """
                    UPDATE user_accounts 
                    SET reset_token = NULL, reset_token_expires_at = NULL, updated_at = NOW()
                    WHERE email = ?
                    """,
                    [email.lower()]
                )
                await commit_db(db)
                return True
        except Exception as e:
            logger.error(f"Error invalidating reset token for {email}: {e}")
            return False


# Singleton instance
_password_reset_service: Optional[PasswordResetService] = None


def get_password_reset_service() -> PasswordResetService:
    """Get the global password reset service instance"""
    global _password_reset_service
    if _password_reset_service is None:
        _password_reset_service = PasswordResetService()
    return _password_reset_service
