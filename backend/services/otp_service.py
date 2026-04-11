"""
Al-Mudeer - OTP (One-Time Password) Service
Handles generation, storage, and verification of OTP codes for email verification

Features:
- Cryptographically secure 6-digit OTP generation
- Expiry tracking (default 10 minutes)
- Attempt limiting (max 5 attempts)
- Rate limiting with cooldown period
- Constant-time comparison to prevent timing attacks

SECURITY FIX: OTPs are now hashed with HMAC-SHA256 using a server-side pepper
instead of plain SHA-256. This prevents brute-force attacks if the database is
compromised, since the attacker would also need the server pepper.
"""

import os
import secrets
import hashlib
import hmac
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

from logging_config import get_logger

logger = get_logger(__name__)

# OTP Configuration
OTP_LENGTH = 6
OTP_EXPIRY_MINUTES = int(os.getenv("OTP_EXPIRY_MINUTES", "10"))
OTP_MAX_ATTEMPTS = int(os.getenv("OTP_MAX_ATTEMPTS", "5"))
OTP_COOLDOWN_SECONDS = int(os.getenv("OTP_COOLDOWN_SECONDS", "60"))

# SECURITY FIX: Server-side pepper for OTP hashing
# This prevents attackers with DB read access from brute-forcing 6-digit OTPs
# because they would also need the server-side pepper
def _get_otp_pepper() -> str:
    """
    Get OTP HMAC pepper from environment. In production, fails if not set.
    """
    pepper = os.getenv("OTP_HMAC_PEPPER", os.getenv("LICENSE_KEY_PEPPER", ""))
    if not pepper:
        env = os.getenv("ENVIRONMENT", "development")
        if env == "production":
            raise ValueError(
                "OTP_HMAC_PEPPER must be set in production! "
                "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
        # Development fallback
        logger.warning("OTP_HMAC_PEPPER not set - using insecure dev pepper. NEVER use this in production!")
        return "default-dev-pepper"
    return pepper

_OTP_PEPPER = _get_otp_pepper()


def _hash_otp(otp_code: str) -> str:
    """
    Hash an OTP code using HMAC-SHA256 with a server-side pepper.

    This is significantly more secure than plain SHA-256 because:
    1. HMAC requires a secret key (the pepper) to compute
    2. An attacker with only DB access cannot brute-force OTPs
    3. Even with read access to both DB and code, they need runtime access to pepper
    """
    return hmac.new(
        _OTP_PEPPER.encode(),
        otp_code.encode(),
        hashlib.sha256
    ).hexdigest()


class OTPService:
    """
    Service for managing OTP codes for email verification.
    
    Usage:
        otp_service = OTPService()
        success = await otp_service.generate_and_send_otp("user@example.com")
        verified = await otp_service.verify_otp("user@example.com", "123456")
    """
    
    def generate_otp(self) -> str:
        """
        Generate a cryptographically secure 6-digit OTP code.
        
        Returns:
            6-digit numeric string (e.g., "123456")
        """
        # Use secrets.token_urlsafe for cryptographically secure random generation
        # Generate number between 0 and 999999, then zero-pad to 6 digits
        otp = secrets.randbelow(10 ** OTP_LENGTH)
        return f"{otp:0{OTP_LENGTH}d}"
    
    async def generate_and_send_otp(self, email: str) -> Tuple[bool, str]:
        """
        Generate OTP code and save to database, then send via email.
        
        Args:
            email: User's email address
        
        Returns:
            Tuple of (success, error_message)
            - (True, "") if OTP was generated and sent successfully
            - (False, "error message") if failed
        """
        from services.email_service import get_email_service
        from db_helper import get_db, fetch_one, execute_sql, commit_db
        
        try:
            # Check if user exists
            async with get_db() as db:
                user = await fetch_one(
                    db,
                    "SELECT id, is_email_verified FROM user_accounts WHERE email = ?",
                    [email.lower()]
                )
                
                if not user:
                    return False, "البريد الإلكتروني غير مسجل"
                
                # Check if already verified
                if user.get("is_email_verified"):
                    return False, "البريد الإلكتروني تم التحقق منه بالفعل"
                
                # Check cooldown period
                user_id = user["id"]
                last_otp_row = await fetch_one(
                    db,
                    "SELECT otp_expires_at FROM user_accounts WHERE id = ?",
                    [user_id]
                )

                if last_otp_row and last_otp_row.get("otp_expires_at"):
                    otp_expires = last_otp_row["otp_expires_at"]
                    # P1 FIX: Correct cooldown calculation
                    # otp_expires_at = generation_time + OTP_EXPIRY_MINUTES
                    # So generation_time = otp_expires_at - OTP_EXPIRY_MINUTES
                    now = datetime.now(timezone.utc)
                    generation_time = otp_expires - timedelta(minutes=OTP_EXPIRY_MINUTES)
                    time_since_generation = now - generation_time

                    if time_since_generation < timedelta(seconds=OTP_COOLDOWN_SECONDS):
                        return False, f"يرجى الانتظار {OTP_COOLDOWN_SECONDS} ثانية قبل طلب رمز جديد"
                
                # Generate OTP
                otp_code = self.generate_otp()
                otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=OTP_EXPIRY_MINUTES)

                # SECURITY FIX: Hash OTP with HMAC-SHA256 + server pepper
                otp_hash = _hash_otp(otp_code)
                
                # Update user record with OTP details
                await execute_sql(
                    db,
                    """
                    UPDATE user_accounts 
                    SET otp_code = ?, otp_expires_at = ?, otp_attempts = 0, updated_at = NOW()
                    WHERE id = ?
                    """,
                    [otp_hash, otp_expires_at, user_id]
                )
                await commit_db(db)
                
                # Send OTP via email
                email_service = get_email_service()
                logger.info(f"Attempting to send OTP email to {email} via {email_service.config.SMTP_HOST}")
                email_sent = email_service.send_otp_email(email, otp_code)

                if not email_sent:
                    logger.error(f"Failed to send OTP email to {email} - email service returned False")
                    logger.error(f"Email config: SMTP_HOST={email_service.config.SMTP_HOST}, SMTP_USERNAME={email_service.config.SMTP_USERNAME}, FROM_EMAIL={email_service.config.FROM_EMAIL}")
                    # Note: OTP is still valid in DB even if email fails
                    # This allows manual verification if needed
                else:
                    logger.info(f"OTP email sent successfully to {email}")
                
                logger.info(f"OTP generated for user {user_id} (email: {email})")
                return True, ""
                
        except Exception as e:
            logger.error(f"Error in generate_and_send_otp for {email}: {e}")
            return False, f"خطأ في إنشاء رمز التحقق: {str(e)}"
    
    async def verify_otp(self, email: str, otp_code: str) -> Tuple[bool, str]:
        """
        Verify OTP code for a user.
        
        Args:
            email: User's email address
            otp_code: 6-digit OTP code to verify
        
        Returns:
            Tuple of (success, error_message)
            - (True, "") if OTP is valid and email is now verified
            - (False, "error message") if OTP is invalid/expired/max attempts exceeded
        """
        from db_helper import get_db, fetch_one, execute_sql, commit_db
        
        try:
            # SECURITY FIX: Hash the input OTP with HMAC-SHA256 + server pepper
            otp_hash = _hash_otp(otp_code)
            
            async with get_db() as db:
                # Fetch user with OTP details
                user = await fetch_one(
                    db,
                    """
                    SELECT id, otp_code, otp_expires_at, otp_attempts, is_email_verified 
                    FROM user_accounts 
                    WHERE email = ?
                    """,
                    [email.lower()]
                )
                
                if not user:
                    return False, "البريد الإلكتروني غير مسجل"
                
                # Check if already verified
                if user.get("is_email_verified"):
                    return False, "البريد الإلكتروني تم التحقق منه بالفعل"
                
                # Check if OTP exists
                if not user.get("otp_code"):
                    return False, "لا يوجد رمز تحقق. يرجى طلب رمز جديد"
                
                # Check if OTP expired
                otp_expires_at = user.get("otp_expires_at")
                if otp_expires_at and otp_expires_at < datetime.now(timezone.utc):
                    return False, "انتهت صلاحية رمز التحقق. يرجى طلب رمز جديد"
                
                # Check attempt limit
                otp_attempts = user.get("otp_attempts", 0)
                if otp_attempts >= OTP_MAX_ATTEMPTS:
                    return False, f"تم تجاوز الحد الأقصى من المحاولات ({OTP_MAX_ATTEMPTS}). يرجى طلب رمز جديد"
                
                # Verify OTP using constant-time comparison
                # Use hashlib.compare_digest to prevent timing attacks
                stored_otp_hash = user.get("otp_code")
                if not stored_otp_hash or not hashlib.compare_digest(otp_hash, stored_otp_hash):
                    # Increment attempt counter
                    await execute_sql(
                        db,
                        "UPDATE user_accounts SET otp_attempts = otp_attempts + 1, updated_at = NOW() WHERE id = ?",
                        [user["id"]]
                    )
                    await commit_db(db)
                    
                    remaining_attempts = OTP_MAX_ATTEMPTS - otp_attempts - 1
                    if remaining_attempts <= 0:
                        return False, "تم تجاوز الحد الأقصى من المحاولات. يرجى طلب رمز جديد"
                    
                    return False, f"رمز التحقق غير صحيح. محاولات متبقية: {remaining_attempts}"
                
                # OTP is valid - mark email as verified
                await execute_sql(
                    db,
                    """
                    UPDATE user_accounts 
                    SET is_email_verified = TRUE, otp_code = NULL, otp_expires_at = NULL, 
                        otp_attempts = 0, updated_at = NOW()
                    WHERE id = ?
                    """,
                    [user["id"]]
                )
                await commit_db(db)
                
                logger.info(f"Email verified successfully for user {user['id']} (email: {email})")
                return True, ""
                
        except Exception as e:
            logger.error(f"Error in verify_otp for {email}: {e}")
            return False, f"خطأ في التحقق من رمز التحقق: {str(e)}"
    
    async def resend_otp(self, email: str) -> Tuple[bool, str]:
        """
        Resend OTP code (with cooldown enforcement).
        
        Args:
            email: User's email address
        
        Returns:
            Tuple of (success, error_message)
        """
        from db_helper import get_db, fetch_one
        
        try:
            async with get_db() as db:
                user = await fetch_one(
                    db,
                    "SELECT id, is_email_verified, otp_expires_at FROM user_accounts WHERE email = ?",
                    [email.lower()]
                )
                
                if not user:
                    return False, "البريد الإلكتروني غير مسجل"
                
                if user.get("is_email_verified"):
                    return False, "البريد الإلكتروني تم التحقق منه بالفعل"
                
                # Check cooldown
                otp_expires_at = user.get("otp_expires_at")
                if otp_expires_at:
                    now = datetime.now(timezone.utc)
                    # P1 FIX: Correct cooldown calculation
                    generation_time = otp_expires_at - timedelta(minutes=OTP_EXPIRY_MINUTES)
                    time_since_generation = now - generation_time

                    if time_since_generation < timedelta(seconds=OTP_COOLDOWN_SECONDS):
                        seconds_left = int(OTP_COOLDOWN_SECONDS - time_since_generation.total_seconds())
                        return False, f"يرجى الانتظار {seconds_left} ثانية قبل طلب رمز جديد"
                
                # Generate and send new OTP
                return await self.generate_and_send_otp(email)
                
        except Exception as e:
            logger.error(f"Error in resend_otp for {email}: {e}")
            return False, f"خطأ في إعادة إرسال رمز التحقق: {str(e)}"


# Singleton instance
_otp_service: Optional[OTPService] = None


def get_otp_service() -> OTPService:
    """Get the global OTP service instance"""
    global _otp_service
    if _otp_service is None:
        _otp_service = OTPService()
    return _otp_service
