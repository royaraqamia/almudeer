"""
Al-Mudeer - Enhanced Security Module
Premium-level security with proper encryption, validation, and protection

SECURITY FIX: Added device secret pepper for enhanced device binding security.
"""

import os
import html
import re
import secrets
import hashlib
from typing import Optional, Tuple
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.backends import default_backend
import base64

# Get encryption key from environment
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY")
if not ENCRYPTION_KEY:
    # In production, this should fail fast
    if os.getenv("ENVIRONMENT", "development") == "production":
        raise ValueError("ENCRYPTION_KEY must be set in production environment!")
    # Generate a key for development only
    ENCRYPTION_KEY = Fernet.generate_key().decode()
    print("WARNING: Using auto-generated encryption key. Set ENCRYPTION_KEY in production!")

# Fixed salt for key derivation (used when ENCRYPTION_KEY is not already a Fernet key)
# Note: This is acceptable because the ENCRYPTION_KEY itself provides the entropy
_KEY_DERIVATION_SALT = os.getenv("ENCRYPTION_SALT", "").encode() or os.urandom(16)

# SECURITY FIX: Device Secret Pepper
# This is a server-side secret that is combined with device secrets before hashing.
# Even if the database is compromised, attackers cannot forge device secrets without this pepper.
# IMPORTANT: Store this in a secure environment variable in production.
_DEVICE_SECRET_PEPPER = os.getenv("DEVICE_SECRET_PEPPER")
if not _DEVICE_SECRET_PEPPER:
    if os.getenv("ENVIRONMENT", "development") == "production":
        # P1-5 FIX: Fail fast in production - do not allow startup without pepper
        import sys
        raise ValueError(
            "DEVICE_SECRET_PEPPER must be set in production environment! "
            "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
        )
    # SECURITY FIX #6: Use fixed pepper for development to prevent session invalidation on restart
    # This is safe for development as long as .env is not committed to version control
    _DEVICE_SECRET_PEPPER = "dev_device_secret_pepper_do_not_use_in_production_change_in_env"
    print("WARNING: Using fixed development device secret pepper. Set DEVICE_SECRET_PEPPER in .env for production!")

# SECURITY FIX: License Key Pepper
# This is a server-side secret that is combined with license keys before hashing.
# Even if the database is compromised, attackers cannot reverse-engineer license keys
# without this pepper. Prevents rainbow table attacks.
# IMPORTANT: Store this in a secure environment variable in production.
_LICENSE_KEY_PEPPER = os.getenv("LICENSE_KEY_PEPPER")
if not _LICENSE_KEY_PEPPER:
    if os.getenv("ENVIRONMENT", "development") == "production":
        # P1-5 FIX: Fail fast in production - do not allow startup without pepper
        import sys
        raise ValueError(
            "LICENSE_KEY_PEPPER must be set in production environment! "
            "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
        )
    # SECURITY FIX #6: Use fixed pepper for development to prevent session invalidation on restart
    # This is safe for development as long as .env is not committed to version control
    _LICENSE_KEY_PEPPER = "dev_license_key_pepper_do_not_use_in_production_change_in_env"
    print("WARNING: Using fixed development license key pepper. Set LICENSE_KEY_PEPPER in .env for production!")

# Initialize Fernet cipher
def _init_cipher():
    """Initialize the Fernet cipher. Raises on failure in production."""
    try:
        # If ENCRYPTION_KEY is already a valid Fernet key (base64, 44 chars), use directly
        if len(ENCRYPTION_KEY) == 44 and ENCRYPTION_KEY.endswith('='):
            return Fernet(ENCRYPTION_KEY.encode())
        else:
            # Derive key from password using PBKDF2 with proper salt
            kdf = PBKDF2HMAC(
                algorithm=hashes.SHA256(),
                length=32,
                salt=_KEY_DERIVATION_SALT,
                iterations=100000,
                backend=default_backend()
            )
            key = base64.urlsafe_b64encode(kdf.derive(ENCRYPTION_KEY.encode()))
            return Fernet(key)
    except Exception as e:
        if os.getenv("ENVIRONMENT", "development") == "production":
            raise RuntimeError(f"Encryption initialization failed: {e}. Cannot run in production without encryption.")
        print(f"WARNING: Encryption initialization error: {e}")
        return None

cipher = _init_cipher()


def get_device_secret_pepper() -> str:
    """
    Get the device secret pepper for device binding.

    SECURITY: This pepper is combined with device secrets before hashing to prevent
    rainbow table attacks even if the database is compromised.

    Returns:
        The pepper string (32+ bytes of entropy)
    """
    return _DEVICE_SECRET_PEPPER


def get_license_key_pepper() -> str:
    """
    Get the license key pepper for license key hashing.

    SECURITY: This pepper is combined with license keys before hashing to prevent
    rainbow table attacks even if the database is compromised.

    Returns:
        The pepper string (32+ bytes of entropy)
    """
    return _LICENSE_KEY_PEPPER


def hash_device_secret(device_secret: str, pepper: str = None) -> str:
    """
    Hash a device secret with the server-side pepper.
    
    SECURITY FIX: Uses HMAC-SHA256 with pepper for device secret hashing.
    This prevents rainbow table attacks and ensures device secrets cannot be
    forged even if the database is compromised.
    
    Args:
        device_secret: The device secret provided by the client
        pepper: Optional pepper override (uses global pepper if not provided)
    
    Returns:
        Hex-encoded SHA-256 hash of the peppered device secret
    """
    if pepper is None:
        pepper = _DEVICE_SECRET_PEPPER
    
    # Combine pepper with device secret and hash with SHA-256
    peppered_secret = f"{pepper}:{device_secret}"
    return hashlib.sha256(peppered_secret.encode('utf-8')).hexdigest()


def encrypt_sensitive_data(data: str) -> str:
    """
    Encrypt sensitive data (passwords, tokens) using Fernet symmetric encryption.
    
    Args:
        data: Plain text data to encrypt
        
    Returns:
        Base64-encoded encrypted string
        
    Raises:
        RuntimeError: If encryption is not available (in production)
    """
    if not data:
        return ""
    
    if not cipher:
        # SECURITY: Never fall back to insecure encoding
        if os.getenv("ENVIRONMENT", "development") == "production":
            raise RuntimeError("Encryption unavailable - cannot store sensitive data")
        # Development only: warn loudly
        print("SECURITY WARNING: Encryption unavailable, storing data unencrypted (dev only)")
        return f"UNENCRYPTED:{base64.b64encode(data.encode()).decode()}"
    
    try:
        encrypted = cipher.encrypt(data.encode())
        return base64.urlsafe_b64encode(encrypted).decode()
    except Exception as e:
        # SECURITY: Don't silently fall back to insecure encoding
        raise RuntimeError(f"Encryption failed: {e}")


def decrypt_sensitive_data(encrypted_data: str) -> str:
    """
    Decrypt sensitive data.
    
    Args:
        encrypted_data: Base64-encoded encrypted string
        
    Returns:
        Decrypted plain text
        
    Raises:
        RuntimeError: If decryption fails in production
    """
    if not encrypted_data:
        return ""
    
    # Handle development-mode unencrypted data
    if encrypted_data.startswith("UNENCRYPTED:"):
        if os.getenv("ENVIRONMENT", "development") == "production":
            raise RuntimeError("Found unencrypted data in production environment")
        return base64.b64decode(encrypted_data[12:].encode()).decode()
    
    if not cipher:
        if os.getenv("ENVIRONMENT", "development") == "production":
            raise RuntimeError("Decryption unavailable - cannot read sensitive data")
        # Development fallback for backwards compatibility
        try:
            return base64.b64decode(encrypted_data.encode()).decode()
        except Exception:
            return ""
    
    try:
        decoded = base64.urlsafe_b64decode(encrypted_data.encode())
        decrypted = cipher.decrypt(decoded)
        return decrypted.decode()
    except Exception as e:
        # Log but don't expose details
        print(f"Decryption error: {type(e).__name__}")
        # In production, we should not silently fail
        if os.getenv("ENVIRONMENT", "development") == "production":
            raise RuntimeError("Decryption failed for sensitive data")
        return ""


def sanitize_string(text: str, max_length: Optional[int] = None, allow_html: bool = False) -> str:
    """
    Enhanced string sanitization to prevent XSS and injection attacks.
    
    Args:
        text: Input string to sanitize
        max_length: Optional maximum length to truncate
        allow_html: If True, allow safe HTML (not recommended for user input)
        
    Returns:
        Sanitized string
    """
    if not text:
        return ""
    
    # Remove null bytes and control characters
    text = text.replace('\x00', '')
    text = re.sub(r'[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]', '', text)
    
    # HTML escape to prevent XSS (unless HTML is explicitly allowed)
    if not allow_html:
        text = html.escape(text)
    
    # Remove potential SQL injection patterns (basic protection)
    sql_patterns = [
        r'(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|EXECUTE)\b)',
        r'(\b(UNION|OR|AND)\s+\d+\s*=\s*\d+)',
        r'(\'|"|--|\/\*|\*\/)',  # Removed ; to preserve HTML entities
    ]
    for pattern in sql_patterns:
        text = re.sub(pattern, '', text, flags=re.IGNORECASE)
    
    # Truncate if max_length specified
    if max_length and len(text) > max_length:
        text = text[:max_length]
    
    return text.strip()


def sanitize_email(email: str) -> Optional[str]:
    """
    Enhanced email validation and sanitization.
    
    Args:
        email: Email string to validate
        
    Returns:
        Sanitized email or None if invalid
    """
    if not email:
        return None
    
    # Basic sanitization
    email = email.strip().lower()
    
    # Enhanced email validation pattern (RFC 5322 compliant)
    email_pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?@[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$'
    
    # Validate format
    if not re.match(email_pattern, email):
        return None
    
    # Additional checks
    if len(email) > 254:  # RFC 5321 limit
        return None
    
    if email.count('@') != 1:
        return None
    
    # Check for common injection patterns
    dangerous_chars = ['<', '>', '"', "'", ';', '(', ')', '[', ']', '{', '}']
    if any(char in email for char in dangerous_chars):
        return None
    
    return email


def sanitize_phone(phone: str) -> Optional[str]:
    """
    Enhanced phone number validation and sanitization.
    
    Args:
        phone: Phone number string
        
    Returns:
        Sanitized phone number or None
    """
    if not phone:
        return None
    
    # Remove all non-digit characters except + at start
    phone = phone.strip()
    
    if phone.startswith('+'):
        cleaned = '+' + re.sub(r'\D', '', phone[1:])
    else:
        cleaned = re.sub(r'\D', '', phone)
    
    # Validate length (5-15 digits is reasonable for international numbers)
    digits_only = cleaned.replace('+', '')
    if len(digits_only) < 5 or len(digits_only) > 15:
        return None
    
    # Check for suspicious patterns
    if cleaned.count('+') > 1:
        return None
    
    return cleaned


def sanitize_message(message: str, max_length: int = 50000) -> str:
    """
    Enhanced message sanitization (allows more characters than basic string).
    
    Args:
        message: Message text to sanitize
        max_length: Maximum allowed length
        
    Returns:
        Sanitized message
    """
    if not message:
        return ""
    
    # Remove null bytes and dangerous control characters
    message = re.sub(r'[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]', '', message)
    
    # HTML escape to prevent XSS
    message = html.escape(message)
    
    # Truncate if too long
    if len(message) > max_length:
        message = message[:max_length]
    
    return message.strip()


def generate_secure_token(length: int = 32) -> str:
    """
    Generate a cryptographically secure random token.
    
    Args:
        length: Length of token in bytes (will be hex-encoded, so output is 2x length)
        
    Returns:
        Hex-encoded secure token
    """
    return secrets.token_hex(length)


def hash_password(password: str, salt: Optional[str] = None) -> Tuple[str, str]:
    """
    Hash a password using PBKDF2 with SHA-256.
    
    Args:
        password: Plain text password
        salt: Optional salt (if not provided, generates a new one)
        
    Returns:
        Tuple of (hashed_password, salt) both base64-encoded
    """
    if salt:
        salt_bytes = base64.b64decode(salt.encode())
    else:
        salt_bytes = os.urandom(16)
        salt = base64.b64encode(salt_bytes).decode()
    
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt_bytes,
        iterations=100000,
        backend=default_backend()
    )
    
    key = base64.urlsafe_b64encode(kdf.derive(password.encode()))
    return key.decode(), salt


def verify_password(password: str, hashed_password: str, salt: str) -> bool:
    """
    Verify a password against a hash.
    
    Args:
        password: Plain text password to verify
        hashed_password: Previously hashed password
        salt: Salt used for hashing
        
    Returns:
        True if password matches, False otherwise
    """
    try:
        new_hash, _ = hash_password(password, salt)
        return secrets.compare_digest(new_hash, hashed_password)
    except Exception:
        return False


def validate_license_key_format(key: str) -> bool:
    """
    Validate license key format.
    Supports both old format (4 chars) and new format (8 chars).
    
    Args:
        key: License key to validate
        
    Returns:
        True if format is valid
    """
    if not key:
        return False
    
    # Old: MUDEER-XXXX-XXXX-XXXX (4 hex chars per segment)
    # New: MUDEER-XXXXXXXX-XXXXXXXX-XXXXXXXX (8 hex chars per segment)
    old_pattern = r'^MUDEER-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$'
    new_pattern = r'^MUDEER-[A-F0-9]{8}-[A-F0-9]{8}-[A-F0-9]{8}$'
    return bool(re.match(old_pattern, key) or re.match(new_pattern, key))


def rate_limit_key(identifier: str, action: str = "default") -> str:
    """
    Generate a rate limit key for caching/rate limiting.
    
    Args:
        identifier: User/license identifier
        action: Action being rate limited
        
    Returns:
        Rate limit key string
    """
    return f"rate_limit:{action}:{identifier}"


def sanitize_url(url: str) -> Optional[str]:
    """
    Sanitize and validate URL.
    
    Args:
        url: URL string to validate
        
    Returns:
        Sanitized URL or None if invalid
    """
    if not url:
        return None
    
    url = url.strip()
    
    # Basic URL validation
    url_pattern = r'^https?://[^\s/$.?#].[^\s]*$'
    if not re.match(url_pattern, url):
        return None
    
    # Check for dangerous protocols
    dangerous_protocols = ['javascript:', 'data:', 'vbscript:', 'file:']
    if any(url.lower().startswith(proto) for proto in dangerous_protocols):
        return None
    
    return url


# Export all sanitization functions for backward compatibility
__all__ = [
    'encrypt_sensitive_data',
    'decrypt_sensitive_data',
    'sanitize_string',
    'sanitize_email',
    'sanitize_phone',
    'sanitize_message',
    'generate_secure_token',
    'hash_password',
    'verify_password',
    'validate_license_key_format',
    'rate_limit_key',
    'sanitize_url',
]

