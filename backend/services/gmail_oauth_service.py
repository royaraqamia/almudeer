"""
Al-Mudeer - Gmail OAuth 2.0 Service
Handles OAuth 2.0 authentication flow for Gmail integration
"""

import os
import httpx
from typing import Optional, Dict, Tuple
from datetime import datetime, timedelta
import urllib.parse
import base64
import json


class GmailOAuthService:
    """Service for Gmail OAuth 2.0 authentication"""
    
    # Gmail OAuth 2.0 endpoints
    AUTHORIZATION_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    TOKEN_INFO_URL = "https://www.googleapis.com/oauth2/v1/tokeninfo"
    
    # Required scopes for Gmail access
    # NOTE:
    # - gmail.readonly / gmail.send are used for reading & sending mail
    # - userinfo.email is required so that the token info endpoint returns the
    #   authenticated user's email address (used in the OAuth callback).
    #   Without this scope, token_info.get("email") will be None and the
    #   backend will fail with "تعذر الحصول على عنوان البريد الإلكتروني".
    SCOPES = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/userinfo.email",
    ]
    
    def __init__(
        self,
        client_id: str = None,
        client_secret: str = None,
        redirect_uri: str = None
    ):
        """
        Initialize Gmail OAuth service
        
        Args:
            client_id: Google OAuth client ID (from env or param)
            client_secret: Google OAuth client secret (from env or param)
            redirect_uri: OAuth redirect URI (from env or param)
        """
        self.client_id = client_id or os.getenv("GMAIL_OAUTH_CLIENT_ID")
        self.client_secret = client_secret or os.getenv("GMAIL_OAUTH_CLIENT_SECRET")
        self.redirect_uri = redirect_uri or os.getenv("GMAIL_OAUTH_REDIRECT_URI")
        
        if not all([self.client_id, self.client_secret, self.redirect_uri]):
            raise ValueError(
                "Gmail OAuth credentials not configured. "
                "Set GMAIL_OAUTH_CLIENT_ID, GMAIL_OAUTH_CLIENT_SECRET, and GMAIL_OAUTH_REDIRECT_URI environment variables."
            )
    
    def get_authorization_url(self, state: str) -> str:
        """
        Generate OAuth 2.0 authorization URL
        
        Args:
            state: State parameter for CSRF protection (should include license_id)
        
        Returns:
            Authorization URL string
        """
        params = {
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "scope": " ".join(self.SCOPES),
            "response_type": "code",
            "access_type": "offline",  # Request refresh token
            "prompt": "consent",  # Force consent to get refresh token
            "state": state,
        }
        
        query_string = urllib.parse.urlencode(params)
        return f"{self.AUTHORIZATION_URL}?{query_string}"
    
    async def exchange_code_for_tokens(self, code: str) -> Dict:
        """
        Exchange authorization code for access and refresh tokens
        
        Args:
            code: Authorization code from OAuth callback
        
        Returns:
            Dictionary with access_token, refresh_token, expires_in, etc.
        """
        data = {
            "code": code,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "redirect_uri": self.redirect_uri,
            "grant_type": "authorization_code",
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.TOKEN_URL,
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=30.0
            )
            
            if response.status_code != 200:
                error_data = response.json() if response.content else {}
                error_msg = error_data.get("error_description", response.text)
                raise Exception(f"Failed to exchange code for tokens: {error_msg}")
            
            return response.json()
    
    async def refresh_access_token(self, refresh_token: str) -> Dict:
        """
        Refresh access token using refresh token
        
        Args:
            refresh_token: Refresh token from previous authorization
        
        Returns:
            Dictionary with new access_token, expires_in, etc.
        """
        data = {
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.TOKEN_URL,
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=30.0
            )
            
            if response.status_code != 200:
                error_data = response.json() if response.content else {}
                error_msg = error_data.get("error_description", response.text)
                raise Exception(f"Failed to refresh token: {error_msg}")
            
            return response.json()
    
    async def get_token_info(self, access_token: str) -> Dict:
        """
        Get information about an access token (user email, scopes, etc.)
        
        Args:
            access_token: OAuth access token
        
        Returns:
            Dictionary with token information including email
        """
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.TOKEN_INFO_URL}?access_token={access_token}",
                timeout=30.0
            )
            
            if response.status_code != 200:
                raise Exception(f"Failed to get token info: {response.text}")
            
            return response.json()
    
    async def validate_token(self, access_token: str) -> Tuple[bool, Optional[str]]:
        """
        Validate if access token is still valid
        
        Args:
            access_token: OAuth access token to validate
        
        Returns:
            Tuple of (is_valid, email_or_error_message)
        """
        try:
            token_info = await self.get_token_info(access_token)
            
            # Check if token has expired
            expires_in = token_info.get("expires_in", 0)
            if expires_in <= 0:
                return False, "Token expired"
            
            # Get user email
            email = token_info.get("email")
            if not email:
                return False, "Email not found in token"
            
            return True, email
            
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def encode_state(license_id: int) -> str:
        """Encode license_id into state parameter"""
        state_data = {"license_id": license_id}
        state_json = json.dumps(state_data)
        return base64.urlsafe_b64encode(state_json.encode()).decode()
    
    @staticmethod
    def decode_state(state: str) -> Dict:
        """Decode state parameter to get license_id"""
        try:
            state_json = base64.urlsafe_b64decode(state.encode()).decode()
            return json.loads(state_json)
        except:
            return {}

