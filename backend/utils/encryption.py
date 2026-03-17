"""
Encryption utilities for Al-Mudeer.
Provides symmetric encryption for sensitive data like cookies.
"""

import os
import base64
import logging
from typing import Optional
from cryptography.fernet import Fernet, InvalidToken

logger = logging.getLogger(__name__)


class CookieEncryption:
    """
    Encrypts and decrypts cookie values using Fernet symmetric encryption.
    
    Usage:
        from utils.encryption import cookie_encryptor
        
        # Encrypt
        encrypted = cookie_encryptor.encrypt("cookie-value")
        
        # Decrypt
        decrypted = cookie_encryptor.decrypt(encrypted)
    """
    
    def __init__(self, key: Optional[str] = None):
        """
        Initialize with encryption key.
        
        Args:
            key: Base64-encoded 32-byte key. If None, encryption is disabled.
        """
        self._key = key or os.getenv("COOKIE_ENCRYPTION_KEY", "")
        self._cipher = None
        
        if self._key:
            try:
                # Validate key format
                key_bytes = base64.urlsafe_b64decode(self._key)
                if len(key_bytes) != 32:
                    logger.error("Invalid encryption key length (must be 32 bytes)")
                    return
                self._cipher = Fernet(self._key)
                logger.info("Cookie encryption initialized successfully")
            except Exception as e:
                logger.error(f"Failed to initialize cookie encryption: {e}")
                self._cipher = None
        else:
            logger.warning("Cookie encryption disabled (no key provided)")
    
    @property
    def is_enabled(self) -> bool:
        """Check if encryption is enabled"""
        return self._cipher is not None
    
    def encrypt(self, value: str) -> str:
        """
        Encrypt a string value.
        
        Args:
            value: Plain text value to encrypt
            
        Returns:
            Encrypted value (base64-encoded), or original value if encryption disabled
        """
        if not self._cipher:
            return value
        
        try:
            encrypted = self._cipher.encrypt(value.encode('utf-8'))
            return encrypted.decode('utf-8')
        except Exception as e:
            logger.error(f"Encryption failed: {e}")
            return value
    
    def decrypt(self, encrypted_value: str) -> str:
        """
        Decrypt an encrypted value.
        
        Args:
            encrypted_value: Encrypted value to decrypt
            
        Returns:
            Decrypted plain text, or original value if decryption fails
        """
        if not self._cipher:
            return encrypted_value
        
        try:
            decrypted = self._cipher.decrypt(encrypted_value.encode('utf-8'))
            return decrypted.decode('utf-8')
        except InvalidToken:
            logger.error("Invalid encryption token")
            return encrypted_value
        except Exception as e:
            logger.error(f"Decryption failed: {e}")
            return encrypted_value


# Global instance
cookie_encryptor = CookieEncryption()


def generate_encryption_key() -> str:
    """
    Generate a new encryption key.
    Store this in COOKIE_ENCRYPTION_KEY environment variable.
    
    Returns:
        Base64-encoded 32-byte key
    """
    return Fernet.generate_key().decode('utf-8')
