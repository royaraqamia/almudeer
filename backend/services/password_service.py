"""
Al-Mudeer - Password Hashing Service
Secure password hashing and verification using bcrypt

Features:
- Bcrypt hashing with configurable rounds
- Constant-time comparison to prevent timing attacks
- Password strength validation
"""

import re
import bcrypt
from typing import Tuple

from logging_config import get_logger

logger = get_logger(__name__)

# Bcrypt configuration
BCRYPT_ROUNDS = 12  # Security: Higher = more secure but slower (12 is recommended for 2024+)


def hash_password(password: str) -> str:
    """
    Hash a password using bcrypt.
    
    Args:
        password: Plain text password to hash
    
    Returns:
        Bcrypt hashed password string
    
    Raises:
        ValueError: If password is empty or invalid
    """
    if not password or not isinstance(password, str):
        raise ValueError("Password must be a non-empty string")
    
    # Encode password to bytes
    password_bytes = password.encode('utf-8')
    
    # Generate salt with configured rounds
    salt = bcrypt.gensalt(rounds=BCRYPT_ROUNDS)
    
    # Hash the password
    hashed = bcrypt.hashpw(password_bytes, salt)
    
    # Return as string
    return hashed.decode('utf-8')


def verify_password(password: str, hashed_password: str) -> bool:
    """
    Verify a password against a bcrypt hash.
    Uses constant-time comparison to prevent timing attacks.
    
    Args:
        password: Plain text password to verify
        hashed_password: Bcrypt hashed password to check against
    
    Returns:
        True if password matches, False otherwise
    
    Raises:
        ValueError: If inputs are invalid
    """
    if not password or not hashed_password:
        return False
    
    try:
        password_bytes = password.encode('utf-8')
        hashed_bytes = hashed_password.encode('utf-8')
        
        # bcrypt.checkpw uses constant-time comparison internally
        return bcrypt.checkpw(password_bytes, hashed_bytes)
    except Exception as e:
        logger.error(f"Password verification error: {e}")
        return False


def validate_password_strength(password: str) -> Tuple[bool, str]:
    """
    Validate password meets security requirements.
    
    Requirements:
    - Minimum 8 characters
    - At least one uppercase letter
    - At least one lowercase letter
    - At least one digit
    - At least one special character
    
    Args:
        password: Password to validate
    
    Returns:
        Tuple of (is_valid, error_message)
        - (True, "") if password is strong
        - (False, "error message") if password is weak
    """
    if not password:
        return False, "كلمة المرور مطلوبة"
    
    if len(password) < 8:
        return False, "كلمة المرور يجب أن تكون 8 أحرف على الأقل"
    
    if not re.search(r'[A-Z]', password):
        return False, "كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل"
    
    if not re.search(r'[a-z]', password):
        return False, "كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل"
    
    if not re.search(r'\d', password):
        return False, "كلمة المرور يجب أن تحتوي على رقم واحد على الأقل"
    
    if not re.search(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;\'`~]', password):
        return False, "كلمة المرور يجب أن تحتوي على رمز خاص واحد على الأقل (!@#$%^&*)"
    
    return True, ""


def needs_rehash(hashed_password: str) -> bool:
    """
    Check if a password hash needs to be rehashed due to updated security settings.
    
    Args:
        hashed_password: Bcrypt hashed password
    
    Returns:
        True if password should be rehashed, False otherwise
    """
    try:
        hashed_bytes = hashed_password.encode('utf-8')
        return bcrypt.check_needs_rehash(hashed_bytes)
    except Exception:
        return False
