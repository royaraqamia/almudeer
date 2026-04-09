"""
Al-Mudeer - Email Service
Handles sending of transactional emails (OTP, password reset, notifications)

Uses SMTP with configurable settings from environment variables.
Supports HTML email templates with Arabic branding.
"""

import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional
from contextlib import contextmanager

from logging_config import get_logger

logger = get_logger(__name__)


class EmailConfig:
    """Email service configuration from environment variables"""
    
    # SMTP Configuration
    SMTP_HOST: str = os.getenv("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USERNAME: str = os.getenv("SMTP_USERNAME", "")
    SMTP_PASSWORD: str = os.getenv("SMTP_PASSWORD", "")
    SMTP_USE_TLS: bool = os.getenv("SMTP_USE_TLS", "true").lower() == "true"
    
    # Sender Information
    FROM_EMAIL: str = os.getenv("FROM_EMAIL", "noreply@almudeer.com")
    FROM_NAME: str = os.getenv("FROM_NAME", "Al-Mudeer | المدير")
    
    # Application URLs
    APP_BASE_URL: str = os.getenv("APP_BASE_URL", "https://almudeer.com")
    MOBILE_APP_SCHEME: str = os.getenv("MOBILE_APP_SCHEME", "almudeer")
    
    # OTP Settings
    OTP_EXPIRY_MINUTES: int = int(os.getenv("OTP_EXPIRY_MINUTES", "10"))
    OTP_COOLDOWN_SECONDS: int = int(os.getenv("OTP_COOLDOWN_SECONDS", "60"))


class EmailService:
    """
    Service for sending transactional emails.
    
    Usage:
        email_service = EmailService()
        email_service.send_otp_email("user@example.com", "123456")
    """
    
    def __init__(self):
        self.config = EmailConfig()
    
    @contextmanager
    def _get_smtp_connection(self):
        """
        Context manager for SMTP connection.
        Handles connection setup, TLS, and authentication.
        """
        server = None
        try:
            if self.config.SMTP_USE_TLS:
                server = smtplib.SMTP(self.config.SMTP_HOST, self.config.SMTP_PORT)
                server.starttls()
            else:
                server = smtplib.SMTP_SSL(self.config.SMTP_HOST, self.config.SMTP_PORT)
            
            if self.config.SMTP_USERNAME and self.config.SMTP_PASSWORD:
                server.login(self.config.SMTP_USERNAME, self.config.SMTP_PASSWORD)
            
            yield server
        except smtplib.SMTPException as e:
            logger.error(f"SMTP error: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error in SMTP connection: {e}")
            raise
        finally:
            if server:
                try:
                    server.quit()
                except Exception:
                    pass
    
    def _create_message(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        from_email: Optional[str] = None,
        from_name: Optional[str] = None,
    ) -> MIMEMultipart:
        """
        Create a MIME message with HTML content.
        
        Args:
            to_email: Recipient email address
            subject: Email subject
            html_content: HTML body content
            from_email: Sender email (defaults to config)
            from_name: Sender name (defaults to config)
        
        Returns:
            MIMEText message object
        """
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = f"{from_name or self.config.FROM_NAME} <{from_email or self.config.FROM_EMAIL}>"
        msg["To"] = to_email
        
        # Attach HTML content
        html_part = MIMEText(html_content, "html", "utf-8")
        msg.attach(html_part)
        
        return msg
    
    def send_email(
        self,
        to_email: str,
        subject: str,
        html_content: str,
    ) -> bool:
        """
        Send an HTML email.
        
        Args:
            to_email: Recipient email address
            subject: Email subject
            html_content: HTML body content
        
        Returns:
            True if email was sent successfully, False otherwise
        """
        try:
            if not self.config.SMTP_USERNAME or not self.config.SMTP_PASSWORD:
                logger.warning(
                    "Email not sent: SMTP credentials not configured. "
                    "Set SMTP_USERNAME and SMTP_PASSWORD environment variables."
                )
                return False
            
            msg = self._create_message(to_email, subject, html_content)
            
            with self._get_smtp_connection() as server:
                server.sendmail(
                    self.config.FROM_EMAIL,
                    to_email,
                    msg.as_string()
                )
            
            logger.info(f"Email sent successfully to {to_email}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send email to {to_email}: {e}")
            return False
    
    def send_otp_email(self, to_email: str, otp_code: str) -> bool:
        """
        Send OTP verification code.
        
        Args:
            to_email: Recipient email address
            otp_code: 6-digit OTP code
        
        Returns:
            True if email was sent successfully, False otherwise
        """
        subject = "رمز التحقق - Al-Mudeer"
        
        html_content = f"""
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    background-color: #f5f7fa;
                    margin: 0;
                    padding: 0;
                }}
                .container {{
                    max-width: 600px;
                    margin: 40px auto;
                    background: #ffffff;
                    border-radius: 16px;
                    box-shadow: 0 4px 24px rgba(0,0,0,0.08);
                    overflow: hidden;
                }}
                .header {{
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    padding: 32px;
                    text-align: center;
                }}
                .header h1 {{
                    color: #ffffff;
                    margin: 0;
                    font-size: 28px;
                }}
                .content {{
                    padding: 40px 32px;
                    text-align: center;
                }}
                .content h2 {{
                    color: #333333;
                    margin-bottom: 16px;
                }}
                .content p {{
                    color: #666666;
                    line-height: 1.6;
                    margin-bottom: 24px;
                }}
                .otp-code {{
                    display: inline-block;
                    background: #f0f4ff;
                    border: 2px dashed #667eea;
                    border-radius: 12px;
                    padding: 20px 40px;
                    margin: 24px 0;
                }}
                .otp-code span {{
                    font-size: 36px;
                    font-weight: bold;
                    letter-spacing: 8px;
                    color: #667eea;
                    font-family: 'Courier New', monospace;
                }}
                .footer {{
                    background: #f8f9fa;
                    padding: 24px 32px;
                    text-align: center;
                    color: #999999;
                    font-size: 14px;
                }}
                .warning {{
                    background: #fff3cd;
                    border: 1px solid #ffc107;
                    border-radius: 8px;
                    padding: 12px;
                    margin-top: 16px;
                    color: #856404;
                    font-size: 14px;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>المدير | Al-Mudeer</h1>
                </div>
                <div class="content">
                    <h2>رمز التحقق الخاص بك</h2>
                    <p>مرحباً بك في المدير! استخدم الرمز التالي للتحقق من بريدك الإلكتروني:</p>
                    
                    <div class="otp-code">
                        <span>{otp_code}</span>
                    </div>
                    
                    <p>هذا الرمز صالح لمدة {self.config.OTP_EXPIRY_MINUTES} دقائق فقط.</p>
                    
                    <div class="warning">
                        ⚠️ إذا لم تقم بطلب هذا الرمز، يرجى تجاهل هذه الرسالة.
                    </div>
                </div>
                <div class="footer">
                    <p>© 2026 المدير | Al-Mudeer. جميع الحقوق محفوظة.</p>
                    <p>هذا بريد إلكتروني تلقائي، يرجى عدم الرد عليه.</p>
                </div>
            </div>
        </body>
        </html>
        """
        
        return self.send_email(to_email, subject, html_content)
    
    def send_password_reset_email(self, to_email: str, reset_token: str) -> bool:
        """
        Send password reset email with reset link.
        
        Args:
            to_email: Recipient email address
            reset_token: Secure reset token
        
        Returns:
            True if email was sent successfully, False otherwise
        """
        reset_url = f"{self.config.APP_BASE_URL}/reset-password?token={reset_token}"
        subject = "إعادة تعيين كلمة المرور - Al-Mudeer"
        
        html_content = f"""
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    background-color: #f5f7fa;
                    margin: 0;
                    padding: 0;
                }}
                .container {{
                    max-width: 600px;
                    margin: 40px auto;
                    background: #ffffff;
                    border-radius: 16px;
                    box-shadow: 0 4px 24px rgba(0,0,0,0.08);
                    overflow: hidden;
                }}
                .header {{
                    background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
                    padding: 32px;
                    text-align: center;
                }}
                .header h1 {{
                    color: #ffffff;
                    margin: 0;
                    font-size: 28px;
                }}
                .content {{
                    padding: 40px 32px;
                    text-align: center;
                }}
                .content h2 {{
                    color: #333333;
                    margin-bottom: 16px;
                }}
                .content p {{
                    color: #666666;
                    line-height: 1.6;
                    margin-bottom: 24px;
                }}
                .reset-button {{
                    display: inline-block;
                    background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
                    color: #ffffff !important;
                    text-decoration: none;
                    padding: 16px 48px;
                    border-radius: 8px;
                    font-size: 18px;
                    font-weight: bold;
                    margin: 24px 0;
                }}
                .footer {{
                    background: #f8f9fa;
                    padding: 24px 32px;
                    text-align: center;
                    color: #999999;
                    font-size: 14px;
                }}
                .warning {{
                    background: #fff3cd;
                    border: 1px solid #ffc107;
                    border-radius: 8px;
                    padding: 12px;
                    margin-top: 16px;
                    color: #856404;
                    font-size: 14px;
                }}
                .link-fallback {{
                    background: #f0f4ff;
                    border: 1px solid #667eea;
                    border-radius: 8px;
                    padding: 12px;
                    margin-top: 16px;
                    word-break: break-all;
                    font-size: 12px;
                    color: #667eea;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>المدير | Al-Mudeer</h1>
                </div>
                <div class="content">
                    <h2>إعادة تعيين كلمة المرور</h2>
                    <p>لقد تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بك. اضغط على الزر أدناه لإنشاء كلمة مرور جديدة:</p>
                    
                    <a href="{reset_url}" class="reset-button">إعادة تعيين كلمة المرور</a>
                    
                    <p>هذا الرابط صالح لمدة ساعة واحدة فقط.</p>
                    
                    <div class="warning">
                        ⚠️ إذا لم تقم بطلب إعادة تعيين كلمة المرور، يرجى تجاهل هذه الرسالة.
                    </div>
                    
                    <div class="link-fallback">
                        أو انسخ هذا الرابط يدوياً:<br>
                        {reset_url}
                    </div>
                </div>
                <div class="footer">
                    <p>© 2026 المدير | Al-Mudeer. جميع الحقوق محفوظة.</p>
                    <p>هذا بريد إلكتروني تلقائي، يرجى عدم الرد عليه.</p>
                </div>
            </div>
        </body>
        </html>
        """
        
        return self.send_email(to_email, subject, html_content)
    
    def send_approval_notification_email(self, to_email: str, full_name: str) -> bool:
        """
        Send account approval notification email.
        
        Args:
            to_email: Recipient email address
            full_name: User's full name
        
        Returns:
            True if email was sent successfully, False otherwise
        """
        subject = "تمت الموافقة على حسابك - Al-Mudeer"
        
        html_content = f"""
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    background-color: #f5f7fa;
                    margin: 0;
                    padding: 0;
                }}
                .container {{
                    max-width: 600px;
                    margin: 40px auto;
                    background: #ffffff;
                    border-radius: 16px;
                    box-shadow: 0 4px 24px rgba(0,0,0,0.08);
                    overflow: hidden;
                }}
                .header {{
                    background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
                    padding: 32px;
                    text-align: center;
                }}
                .header h1 {{
                    color: #ffffff;
                    margin: 0;
                    font-size: 28px;
                }}
                .content {{
                    padding: 40px 32px;
                    text-align: center;
                }}
                .content h2 {{
                    color: #333333;
                    margin-bottom: 16px;
                }}
                .content p {{
                    color: #666666;
                    line-height: 1.6;
                    margin-bottom: 24px;
                }}
                .success-icon {{
                    font-size: 64px;
                    margin-bottom: 16px;
                }}
                .footer {{
                    background: #f8f9fa;
                    padding: 24px 32px;
                    text-align: center;
                    color: #999999;
                    font-size: 14px;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>المدير | Al-Mudeer</h1>
                </div>
                <div class="content">
                    <div class="success-icon">✅</div>
                    <h2>تمت الموافقة على حسابك!</h2>
                    <p>مرحباً {full_name},</p>
                    <p>يسعدنا إعلامك بأنه تمت الموافقة على حسابك. يمكنك الآن تسجيل الدخول والوصول إلى جميع الميزات.</p>
                    <p>نتمنى لك تجربة موفقة!</p>
                </div>
                <div class="footer">
                    <p>© 2026 المدير | Al-Mudeer. جميع الحقوق محفوظة.</p>
                    <p>هذا بريد إلكتروني تلقائي، يرجى عدم الرد عليه.</p>
                </div>
            </div>
        </body>
        </html>
        """
        
        return self.send_email(to_email, subject, html_content)


# Singleton instance
_email_service: Optional[EmailService] = None


def get_email_service() -> EmailService:
    """Get the global email service instance"""
    global _email_service
    if _email_service is None:
        _email_service = EmailService()
    return _email_service
