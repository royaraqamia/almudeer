"""
Resend HTTP API Client for Al-Mudeer
Uses Resend's REST API instead of SMTP for better reliability on Railway.

Documentation: https://resend.com/docs/api-reference/emails/send-email
"""

import os
import httpx
from typing import Optional
from logging_config import get_logger

logger = get_logger(__name__)


class ResendClient:
    """
    Resend HTTP API client for sending emails.
    
    This is the preferred method for Railway deployments as it avoids
    SMTP connection/timeout issues.
    """
    
    def __init__(self):
        self.api_key = os.getenv("RESEND_API_KEY", "")
        self.from_email = os.getenv("FROM_EMAIL", "noreply@almudeer.com")
        self.from_name = os.getenv("FROM_NAME", "Al-Mudeer | المدير")
        self.base_url = "https://api.resend.com/emails"
        
    def send_email(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        from_email: Optional[str] = None,
        from_name: Optional[str] = None,
    ) -> bool:
        """
        Send an email using Resend's HTTP API.
        
        Args:
            to_email: Recipient email address
            subject: Email subject
            html_content: HTML body content
            from_email: Sender email (optional, uses config default)
            from_name: Sender name (optional, uses config default)
            
        Returns:
            True if email was sent successfully, False otherwise
        """
        if not self.api_key:
            logger.error("Resend API key not configured")
            return False
        
        sender_email = from_email or self.from_email
        sender_name = from_name or self.from_name
        from_address = f"{sender_name} <{sender_email}>"
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        
        payload = {
            "from": from_address,
            "to": [to_email],
            "subject": subject,
            "html": html_content,
        }
        
        try:
            logger.info(f"Sending email to {to_email} via Resend API")
            
            with httpx.Client(timeout=30.0) as client:
                response = client.post(
                    self.base_url,
                    headers=headers,
                    json=payload,
                )
                
                if response.status_code == 200:
                    response_data = response.json()
                    email_id = response_data.get("id", "unknown")
                    logger.info(f"Email sent successfully to {to_email} (id: {email_id})")
                    return True
                else:
                    error_data = response.json()
                    error_message = error_data.get("message", "Unknown error")
                    error_code = error_data.get("code", "unknown")
                    logger.error(
                        f"Resend API error for {to_email}: "
                        f"status={response.status_code}, "
                        f"code={error_code}, "
                        f"message={error_message}"
                    )
                    return False
                    
        except httpx.TimeoutException:
            logger.error(f"Timeout sending email to {to_email} via Resend API")
            return False
        except httpx.ConnectError as e:
            logger.error(f"Connection error sending email to {to_email}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error sending email to {to_email}: {e}")
            return False
