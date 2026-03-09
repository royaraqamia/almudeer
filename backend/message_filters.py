"""
Al-Mudeer - Message Filtering System
Advanced filtering rules for messages before processing
"""

from typing import Dict, List, Optional, Callable
from datetime import datetime
import re
from logging_config import get_logger

logger = get_logger(__name__)


class MessageFilter:
    """Filter messages based on configurable rules"""
    
    def __init__(self):
        self.rules: List[Callable] = []
    
    def add_rule(self, rule_func: Callable):
        """Add a filtering rule"""
        self.rules.append(rule_func)
    
    def should_process(self, message: Dict) -> tuple[bool, Optional[str]]:
        """
        Check if message should be processed.
        
        Returns:
            Tuple of (should_process, reason_if_rejected)
        """
        for rule in self.rules:
            result = rule(message)
            if isinstance(result, tuple):
                should_process, reason = result
                if not should_process:
                    return False, reason
            elif not result:
                return False, "Filtered by rule"
        
        return True, None


def filter_spam(message: Dict) -> tuple[bool, Optional[str]]:
    """Filter spam messages based on patterns"""
    body = message.get("body", "")
    original_body = body
    body = body.lower()
    
    # Check for excessive links
    link_count = len(re.findall(r'http[s]?://', body))
    if link_count >= 3:
        return False, "Spam: Excessive links detected"
    
    # Check for excessive caps
    if len(original_body) > 10:
        caps_count = sum(1 for c in original_body if c.isupper())
        caps_ratio = caps_count / len(original_body)
        if caps_ratio > 0.7:
            return False, "Spam: Too many CAPS"
    
    return True, None


def filter_empty(message: Dict) -> tuple[bool, Optional[str]]:
    """Filter empty messages"""
    body = message.get("body", "").strip()
    attachments = message.get("attachments", [])
    
    # Allow messages with attachments even if body is empty
    if attachments and len(attachments) > 0:
        return True, None
    
    # Allow any non-empty message
    if len(body) < 1:
        return False, "Message is empty"
    
    return True, None


def filter_duplicate(message: Dict, recent_messages: List[Dict], time_window_minutes: int = 5) -> tuple[bool, Optional[str]]:
    """Filter duplicate messages from same sender within a time window"""
    sender = message.get("sender_contact") or message.get("sender_id")
    body = message.get("body", "").strip()[:100]  # First 100 chars
    
    if not sender or not recent_messages:
        return True, None
    
    now = datetime.now()
    for recent in recent_messages:
        recent_sender = recent.get("sender_contact") or recent.get("sender_id")
        if recent_sender == sender:
            recent_body = recent.get("body", "").strip()[:100]
            
            if recent_body == body:
                raw_received = recent.get("received_at")
                if isinstance(raw_received, str):
                    try:
                        recent_time = datetime.fromisoformat(raw_received)
                    except ValueError:
                        recent_time = now
                elif isinstance(raw_received, datetime):
                    recent_time = raw_received
                else:
                    recent_time = now
                
                time_diff = (now - recent_time).total_seconds() / 60
                if time_diff < time_window_minutes:
                    return False, "Duplicate message"
    
    return True, None


def filter_blocked_senders(message: Dict, blocked_list: List[str]) -> tuple[bool, Optional[str]]:
    """Filter messages from blocked senders"""
    sender = message.get("sender_contact") or message.get("sender_id", "")
    if sender in blocked_list:
        return False, "Sender is blocked"
    return True, None


def filter_automated_messages(message: Dict) -> tuple[bool, Optional[str]]:
    """Filter automated/marketing messages"""
    body = message.get("body", "").lower()
    sender_contact = (message.get("sender_contact") or "").lower()
    sender_name = (message.get("sender_name") or "").lower()
    
    if not body: body = (message.get("text") or "").lower()
    
    subject = message.get("subject", "").lower()
    full_text = f"{body} {subject} {sender_name} {sender_contact}"

    # Automated sender patterns
    automated_sender_patterns = [
        r"^noreply@", r"^no-reply@", r"^no\.reply@",
        r"^notifications?@", r"^newsletter@", r"^marketing@",
        r"@.*\.noreply\.", r"@bounce\."
    ]
    for pattern in automated_sender_patterns:
        if re.search(pattern, sender_contact):
            return False, "Automated: Sender pattern detected"

    # Marketing patterns
    marketing_patterns = [r"خصم", r"عرض", r"اشتراك", r"مجانا", r"discount", r"offer", r"subscribe", r"free", r"sale", r"deals", r"unsubscribe"]
    for pattern in marketing_patterns:
        if re.search(pattern, full_text):
            return False, "Marketing message detected"
            
    # OTP patterns
    otp_patterns = [r"verification code", r"رمز التحقق", r"كود التفعيل"]
    for pattern in otp_patterns:
        if re.search(pattern, full_text):
            return False, "OTP message detected"
            
    # Transactional patterns
    transactional_patterns = [r"order confirmation", r"تأكيد الطلب", r"automated message", r"do not reply"]
    for pattern in transactional_patterns:
        if re.search(pattern, full_text):
            return False, "Transactional message detected"
            
    # Account & Security patterns
    account_patterns = [r"password reset", r"new login", r"security alert", r"fraud alert", r"suspicious activity", r"unauthorized access"]
    for pattern in account_patterns:
        if re.search(pattern, full_text):
            if "security" in pattern or "fraud" in pattern or "suspicious" in pattern or "unauthorized" in pattern:
                return False, "Security alert detected"
            return False, "Account notification detected"
            
    # Newsletter patterns
    newsletter_patterns = [r"newsletter", r"weekly digest", r"daily digest", r"roundup"]
    for pattern in newsletter_patterns:
        if re.search(pattern, full_text):
            return False, "Newsletter detected"

    return True, None


def filter_keywords(message: Dict, keywords: List[str], mode: str = "block") -> tuple[bool, Optional[str]]:
    """Filter messages based on keywords"""
    body = message.get("body", "").lower()
    has_keyword = any(keyword.lower() in body for keyword in keywords)
    
    if mode == "block" and has_keyword:
        return False, "Contains blocked keyword"
    if mode == "allow" and not has_keyword:
        return False, "Does not contain required keyword"
    return True, None


def filter_chat_types(message: Dict) -> tuple[bool, Optional[str]]:
    """Filter messages from groups/channels (only allow private)"""
    if message.get("is_group", False):
        return False, "Source is a Group"
    if message.get("is_channel", False):
        return False, "Source is a Channel"
    
    chat_type = message.get("chat_type")
    if chat_type and chat_type not in ["private", "sender"]:
        return False, f"Chat type '{chat_type}' is not private"
    
    return True, None


def filter_telegram_bots(message: Dict) -> tuple[bool, Optional[str]]:
    """Filter messages from Telegram Bots"""
    if message.get("channel") not in ["telegram", "telegram_bot"]:
        return True, None
    if message.get("is_bot", False):
        return False, "Sender is a Bot"
    
    sender_contact = (message.get("sender_contact") or "").lower()
    if sender_contact.endswith('bot'):
        return False, "Username indicates a Bot"
    
    return True, None


class FilterManager:
    """Manage message filters for a license"""
    
    def __init__(self, license_id: int):
        self.license_id = license_id
        self.filter = MessageFilter()
        self._setup_default_filters()
    
    def _setup_default_filters(self):
        """Setup default filter rules"""
        self.filter.add_rule(filter_spam)
        self.filter.add_rule(filter_empty)
        self.filter.add_rule(filter_automated_messages)
        self.filter.add_rule(filter_chat_types)
        self.filter.add_rule(filter_telegram_bots)
    
    def add_custom_rule(self, rule_func: Callable):
        """Add a custom filter rule"""
        self.filter.add_rule(rule_func)
    
    def should_process(self, message: Dict, recent_messages: List[Dict] = None) -> tuple[bool, Optional[str]]:
        """Check if message should be processed"""
        if recent_messages:
            # We wrap it to pass the recent_messages list
            dup_rule = lambda msg: filter_duplicate(msg, recent_messages)
            self.filter.add_rule(dup_rule)
        
        return self.filter.should_process(message)


# ============ Integration with Agent ============

async def apply_filters(message: Dict, license_id: int, recent_messages: List[Dict] = None) -> tuple[bool, Optional[str]]:
    """
    Apply all filters to a message.
    """
    filter_manager = FilterManager(license_id)
    return filter_manager.should_process(message, recent_messages)