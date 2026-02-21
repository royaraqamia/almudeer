"""
Al-Mudeer - Background Workers
Automatic message polling and processing for Email, WhatsApp, and Telegram
"""

import asyncio
import os
import random
import hashlib
import base64
import tempfile
import mimetypes
from services.file_storage_service import get_file_storage
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, List, Set, Any

from logging_config import get_logger
from models.task_queue import fetch_next_task, complete_task, fail_task
from db_helper import (
    get_db,
    fetch_one,
    fetch_all,
    execute_sql,
    commit_db,
    DB_TYPE,
    DATABASE_PATH,
    DATABASE_URL
)

logger = get_logger(__name__)

# Import appropriate database driver
if DB_TYPE == "postgresql":
    try:
        import asyncpg
        POSTGRES_AVAILABLE = True
        aiosqlite = None
    except ImportError:
        raise ImportError(
            "PostgreSQL selected but asyncpg not installed. "
            "Install with: pip install asyncpg"
        )
else:
    import aiosqlite
    POSTGRES_AVAILABLE = False

# Import services
from services.telegram_service import TelegramService
from services.whatsapp_service import WhatsAppService
from services.gmail_oauth_service import GmailOAuthService
from services.gmail_api_service import GmailAPIService, GmailRateLimitError
from services.telegram_phone_service import TelegramPhoneService
from services.backfill_service import get_backfill_service
from cache import cache

# Import models
from models import (
    get_email_config, get_email_oauth_tokens,
    get_telegram_config,
    get_whatsapp_config,
    save_inbox_message,
    update_inbox_status,
    get_preferences,
    get_inbox_messages,
    create_outbox_message,
    approve_outbox_message,
    mark_outbox_sent,
    mark_outbox_failed,
    get_telegram_phone_session_data,
    get_telegram_phone_session,
    get_or_create_customer,
    increment_customer_messages,
    update_telegram_phone_session_sync_time,
    deactivate_telegram_phone_session,
)
# from agent import process_message (AI removed)
from message_filters import apply_filters


class MessagePoller:
    """Background worker for polling messages from all channels"""
    
    def __init__(self):
        self.running = False
        self.tasks: Dict[int, asyncio.Task] = {}
        # Track recently processed message hashes to avoid duplicate AI calls
        self._processed_hashes: Set[str] = set()
        self._hash_cache_max_size = 1000  # Limit memory usage
        # Lightweight in‑memory status used by /api/integrations/workers/status
        self.status: Dict[str, Dict[str, Optional[str]]] = {
            "email_polling": {
                "last_check": None,
                "status": "stopped",
                "next_check": None,
            },
            "telegram_polling": {
                "last_check": None,
                "status": "stopped",
            },
        }
        
        # Keep references to background tasks to prevent garbage collection
        self.background_tasks: Set[asyncio.Task] = set()
        
        # Track message retry counts to prevent infinite retry loops
        # Structure: {message_id: retry_count}
        self._retry_counts: Dict[int, int] = {}
        
        # Track recent message hashes for duplicate detection
        self._recent_message_hashes: Set[str] = set()
        
        # Track messages retried this poll cycle (cleared each cycle)
        # Prevents rapid retry loops within the same 5-minute cycle
        self._retried_this_cycle: Set[int] = set()
        
        # Per-user rate limiting is now handled via Redis/CacheManager
    
    async def start(self):
        """Start all polling workers"""
        self.running = True
        self.status["email_polling"]["status"] = "running"
        self.status["telegram_polling"]["status"] = "running"
        logger.info("Starting message polling workers...")
        
        # Start polling loop
        # Start polling loop
        task = asyncio.create_task(self._polling_loop())
        self.background_tasks.add(task)
        task.add_done_callback(self.background_tasks.discard)
    
    async def stop(self):
        """Stop all polling workers"""
        self.running = False
        for task in self.background_tasks:
            task.cancel()
        self.background_tasks.clear()
        self.status["email_polling"]["status"] = "stopped"
        self.status["telegram_polling"]["status"] = "stopped"
        logger.info("Stopped message polling workers")
    
    async def _polling_loop(self):
        """Main polling loop - runs every minute"""
        while self.running:
            try:
                # Clear retry tracking at the start of each cycle
                # This allows messages to be retried in this new 5-min window
                self._retried_this_cycle.clear()
                
                # Get all active licenses with integrations
                active_licenses = await self._get_active_licenses()
                now_iso = datetime.now(timezone.utc).isoformat()
                self.status["email_polling"]["last_check"] = now_iso
                self.status["telegram_polling"]["last_check"] = now_iso
                
                for license_id in active_licenses:
                    # Stagger polling: increased delay between licenses to spread AI load
                    # 10-15s gap ensures we stay under Gemini's 15 RPM limit across users
                    await asyncio.sleep(random.uniform(10.0, 15.0))
                    # Poll each integration type
                    t1 = asyncio.create_task(self._poll_email(license_id))
                    self.background_tasks.add(t1)
                    t1.add_done_callback(self.background_tasks.discard)
                    
                    t2 = asyncio.create_task(self._poll_telegram(license_id))
                    self.background_tasks.add(t2)
                    t2.add_done_callback(self.background_tasks.discard)
                    # WhatsApp uses webhooks, so no polling needed
                    
                    await self._retry_approved_outbox(license_id)
                    
                    # Poll Telegram delivery statuses (read receipts)
                    # We run this less frequently or just part of the loop
                    # Using create_task to run concurrently
                    t3 = asyncio.create_task(self._poll_telegram_outbox_status(license_id))
                    self.background_tasks.add(t3)
                    t3.add_done_callback(self.background_tasks.discard)
                
                # Wait 300 seconds (5 minutes) before next poll - optimized for Gemini free tier
                # This ensures we stay well within 15 RPM limit even with 10 users
                next_ts = (datetime.now(timezone.utc) + timedelta(seconds=300)).isoformat()
                self.status["email_polling"]["next_check"] = next_ts
                await asyncio.sleep(300)
                
            except Exception as e:
                logger.error(f"Error in polling loop: {e}", exc_info=True)
                self.status["email_polling"]["status"] = "error"
                self.status["telegram_polling"]["status"] = "error"
                await asyncio.sleep(300)  # Wait before retry
    
    async def _get_active_licenses(self) -> List[int]:
        """Get list of license IDs with active integrations"""
        licenses = []
        
        try:
            if DB_TYPE == "postgresql" and POSTGRES_AVAILABLE:
                if not DATABASE_URL:
                    logger.warning("DATABASE_URL not set for PostgreSQL")
                    return []
                conn = await asyncpg.connect(DATABASE_URL)
                try:
                    # Get licenses with email configs
                    rows = await conn.fetch("""
                        SELECT DISTINCT license_key_id 
                        FROM email_configs 
                        WHERE is_active = TRUE
                    """)
                    licenses.extend([row['license_key_id'] for row in rows])
                    
                    # Get licenses with telegram configs
                    rows = await conn.fetch("""
                        SELECT DISTINCT license_key_id 
                        FROM telegram_configs 
                        WHERE is_active = TRUE
                    """)
                    licenses.extend([row['license_key_id'] for row in rows])
                finally:
                    await conn.close()
            else:
                async with aiosqlite.connect(DATABASE_PATH) as db:
                    # Get licenses with email configs
                    async with db.execute("""
                        SELECT DISTINCT license_key_id 
                        FROM email_configs 
                        WHERE is_active = 1
                    """) as cursor:
                        rows = await cursor.fetchall()
                        licenses.extend([row[0] for row in rows])
                    
                    # Get licenses with telegram bot configs
                    async with db.execute("""
                        SELECT DISTINCT license_key_id 
                        FROM telegram_configs 
                        WHERE is_active = 1
                    """) as cursor:
                        rows = await cursor.fetchall()
                        licenses.extend([row[0] for row in rows])
                    
                    # Get licenses with telegram phone sessions
                    async with db.execute("""
                        SELECT DISTINCT license_key_id 
                        FROM telegram_phone_sessions 
                        WHERE is_active = 1
                    """) as cursor:
                        rows = await cursor.fetchall()
                        licenses.extend([row[0] for row in rows])
        
        except Exception as e:
            logger.error(f"Error getting active licenses: {e}")
        
        return list(set(licenses))  # Remove duplicates
    
    async def _retry_pending_messages(self, license_id: int):
        """AI analysis retry is now removed."""
        pass

    async def _retry_approved_outbox(self, license_id: int):
        """Retry sending messages that are approved but not yet sent"""
        try:
            async with get_db() as db:
                if DB_TYPE == "postgresql":
                    query = """
                        SELECT id, channel 
                        FROM outbox_messages 
                        WHERE license_key_id = $1 
                          AND status = 'approved' 
                          AND created_at > NOW() - INTERVAL '24 hours'
                        ORDER BY created_at ASC
                        LIMIT 10
                    """
                else:
                    query = """
                        SELECT id, channel 
                        FROM outbox_messages 
                        WHERE license_key_id = ? 
                          AND status = 'approved' 
                          AND created_at > datetime('now', '-24 hours')
                        ORDER BY created_at ASC
                        LIMIT 10
                    """
                
                rows = await fetch_all(db, query, [license_id])
            
            if not rows:
                return
            
            logger.info(f"License {license_id}: Retrying {len(rows)} approved outbox messages")
            
            # Use a semaphore to limit concurrent sends (e.g., 5 at a time) to avoid flooding and memory spikes
            sem = asyncio.Semaphore(5)
            
            async def process_outbox_item(msg):
                outbox_id = msg["id"]
                channel = msg["channel"]
                
                async with sem:
                    try:
                        # Use a distributed lock or local memory lock to avoid duplicate sends 
                        # if processing takes longer than the polling interval
                        lock_key = f"outbox_send_{outbox_id}"
                        if cache.get(lock_key):
                            return
                        
                        # Set lock for 5 minutes
                        cache.set(lock_key, True, expire=300)
                        
                        # Send the message
                        await self._send_message(outbox_id, license_id, channel)
                        
                    except Exception as e:
                        logger.error(f"Error processing outbox {outbox_id}: {e}")

            # Process all approved messages in parallel (honoring the semaphore)
            await asyncio.gather(*(process_outbox_item(msg) for msg in rows))
                    
        except Exception as e:
            logger.error(f"Error retrying approved outbox for license {license_id}: {e}")
    
    async def _poll_email(self, license_id: int):
        """Poll email for new messages using Gmail API"""
        try:
            config = await get_email_config(license_id)
            if not config or not config.get("is_active"):
                return
            
            # Check if it's time to poll (based on check_interval_minutes)
            last_checked = config.get("last_checked_at")
            check_interval = config.get("check_interval_minutes", 5)
            
            if last_checked:
                # Support both string (SQLite) and datetime (PostgreSQL) values
                if isinstance(last_checked, str):
                    try:
                        last_checked_dt = datetime.fromisoformat(last_checked.replace("Z", "+00:00"))
                    except ValueError:
                        # Fallback: try parsing generic string representation
                        last_checked_dt = datetime.fromisoformat(str(last_checked))
                elif hasattr(last_checked, "isoformat"):
                    # Already a datetime-like object
                    last_checked_dt = last_checked
                else:
                    last_checked_dt = datetime.fromisoformat(str(last_checked))

                if datetime.utcnow() - last_checked_dt < timedelta(minutes=check_interval):
                    return  # Too soon to check again
            
            # Get OAuth tokens
            tokens = await get_email_oauth_tokens(license_id)
            if not tokens or not tokens.get("access_token"):
                logger.warning(f"No OAuth tokens found for license {license_id}")
                return
            
            # Initialize Gmail API service
            oauth_service = GmailOAuthService()
            gmail_service = GmailAPIService(
                tokens["access_token"],
                tokens.get("refresh_token"),
                oauth_service
            )
            
            # Get our own email address to filter out self-messages
            # This prevents AI from processing emails WE sent
            our_email_address = config.get("email_address", "").lower()
            
            # Check for backfill trigger (first time loading)
            backfill_service = get_backfill_service()
            is_backfill = await backfill_service.should_trigger_backfill(license_id, "email")
            
            # Calculate since_hours based on when the channel was connected
            config_created_at = config.get("created_at")
            
            if is_backfill:
                # Fetch 30 days history for backfill
                logger.info(f"Triggering historical backfill for license {license_id} (email)")
                since_hours = backfill_service.backfill_days * 24
            elif config_created_at:
                # Standard polling: calculate hours since connected
                try:
                    if isinstance(config_created_at, str):
                        created_dt = datetime.fromisoformat(config_created_at.replace('Z', '+00:00'))
                    elif isinstance(config_created_at, datetime):
                        created_dt = config_created_at
                    else:
                        # Fallback if unknown type
                        created_dt = datetime.now(timezone.utc) - timedelta(hours=24)

                    # Handle offset-naive vs offset-aware
                    if created_dt.tzinfo is None:
                        created_dt = created_dt.replace(tzinfo=timezone.utc)
                    
                    now = datetime.now(timezone.utc)
                    hours_since_connected = (now - created_dt).total_seconds() / 3600
                    
                    # Fetch messages since connection (plus 1 hour buffer)
                    # But cap at 24 hours for regular polling to avoid huge fetches if system was down
                    since_hours = min(int(hours_since_connected) + 1, 720) # cap at 30 days anyway
                except Exception as e:
                    logger.warning(f"Error parsing created_at: {e}")
                    since_hours = 24
            else:
                since_hours = 1
                
            # Update last checked timestamp
            self.status["email_polling"]["last_check"] = datetime.now(timezone.utc).isoformat()
            
            # Fetch emails
            # If backfill, fetch more (e.g. 500), otherwise standard limit
            limit = 500 if is_backfill else 200
            # Fetch messages
            # Fetch messages
            try:
                if is_backfill:
                    # Smart Backfill: Fetch threads that are UNREPLIED (last message not from us)
                    # This ensures we don't import old conversations we already finished
                    backfill_days = int(os.getenv("BACKFILL_DAYS", "30"))
                    emails = await gmail_service.fetch_unreplied_threads(days=backfill_days, limit=100)
                    logger.info(f"Backfill: Fetched {len(emails)} unreplied emails")
                else:
                    emails = await gmail_service.fetch_new_emails(since_hours=since_hours, limit=limit)
            except GmailRateLimitError as e:
                logger.warning(f"Rate limit hit for license {license_id}, skipping email poll cycle: {e}")
                return

            
            if not emails:
                return

            # If backfill is active, queue ALL fetched messages and skip standard processing
            if is_backfill:
                backfill_messages = []
                for email_data in emails:
                    # Apply filters (Spam, Promo, Bot, etc.)
                    # We skip duplicate check for backfill (pass empty list)
                    filter_msg = {
                        "body": email_data.get("body", "") or email_data.get("snippet", ""),
                        "sender_contact": email_data.get("sender"),
                        "sender_name": email_data.get("sender_name"),
                        "subject": email_data.get("subject"),
                        "channel": "email",
                        "attachments": email_data.get("attachments", []),
                    }
                    should_process, reason = await apply_filters(filter_msg, license_id, [])
                    if not should_process:
                        logger.debug(f"Skipping backfill email from {filter_msg['sender_contact']}: {reason}")
                        continue

                    # Extract attachments if present (Gmail service returns simplified attachment objects)
                    attachments = []
                    if "attachments" in email_data and email_data["attachments"]:
                        # Ensure attachments are JSON serializable
                        attachments = email_data["attachments"]
                    
                    backfill_messages.append({
                        "body": email_data.get("body", "") or email_data.get("snippet", ""),
                        "channel_message_id": email_data.get("id"),
                        "sender_contact": email_data.get("sender"),
                        "sender_name": email_data.get("sender_name"),
                        "subject": email_data.get("subject"),
                        "received_at": datetime.fromtimestamp(email_data.get("internalDate", 0)/1000) if email_data.get("internalDate") else None,
                        "attachments": attachments
                    })
                
                queued = await backfill_service.schedule_historical_messages(
                    license_id=license_id,
                    channel="email",
                    messages=backfill_messages
                )
                
                if queued > 0:
                    logger.info(f"Queued {queued} email messages for backfill. Skipping immediate processing.")
                    return

            # Process standard emails (non-backfill)
            processed_count = 0
            
            # Get recent messages for duplicate detection
            # Use higher limit to avoid missing duplicates when inbox is large
            recent_messages = await get_inbox_messages(license_id, limit=500)
            
            # Process emails in parallel with a concurrency limit
            sem = asyncio.Semaphore(10) # 10 parallel processes for Gmail
            
            async def process_one_email(email_data):
                async with sem:
                    try:
                        # CRITICAL: Skip emails sent BY US to prevent AI loop
                        sender_email = (email_data.get("sender_contact") or "").lower()
                        if our_email_address and sender_email == our_email_address:
                            # Sync outgoing emails to outbox
                            to_header = email_data.get("to", "")
                            recipient_email = ""
                            recipient_name = ""
                            if to_header:
                                recipient_name, recipient_email = gmail_service._extract_email_address(to_header)
                            
                            if not recipient_email:
                                recipient_email = "Unknown"

                            from models.inbox import save_synced_outbox_message
                            await save_synced_outbox_message(
                                license_id=license_id,
                                channel="email",
                                body=email_data["body"] or "",
                                recipient_email=recipient_email,
                                recipient_name=recipient_name,
                                subject=email_data.get("subject"),
                                attachments=email_data.get("attachments", []),
                                sent_at=email_data.get("received_at"),
                                platform_message_id=email_data.get("channel_message_id")
                            )
                            return

                        # Check if we already have this message
                        existing = await self._check_existing_message(
                            license_id, "email", email_data.get("channel_message_id")
                        )
                        if existing:
                            return
                        
                        # Apply filters
                        message_dict = {
                            "body": email_data["body"],
                            "sender_contact": email_data.get("sender_contact"),
                            "sender_name": email_data.get("sender_name"),
                            "subject": email_data.get("subject"),
                            "channel": "email",
                            "attachments": email_data.get("attachments", []),
                        }
                        
                        should_process, filter_reason = await apply_filters(
                            message_dict, license_id, recent_messages
                        )
                        if not should_process:
                            return
                        
                        # Save to inbox
                        msg_id = await save_inbox_message(
                            license_id=license_id,
                            channel="email",
                            body=email_data["body"],
                            sender_name=email_data["sender_name"],
                            sender_contact=email_data["sender_contact"],
                            sender_id=None,
                            subject=email_data.get("subject"),
                            channel_message_id=email_data.get("channel_message_id"),
                            received_at=email_data.get("received_at"),
                            attachments=email_data.get("attachments", [])
                        )
                        
                        await self._analyze_and_process_message(
                            message_id=msg_id,
                            body=email_data["body"],
                            license_id=license_id,
                            channel="email",
                            recipient=email_data.get("sender_contact"),
                            sender_name=email_data.get("sender_name"),
                            channel_message_id=email_data.get("channel_message_id"),
                            attachments=email_data.get("attachments", [])
                        )
                    except Exception as email_e:
                        logger.error(f"Error processing single email: {email_e}")

            # Execute all email tasks
            await asyncio.gather(*(process_one_email(e) for e in emails))
            
            # Update last_checked_at
            await self._update_email_last_checked(license_id)
            
        except Exception as e:
            logger.error(f"Error polling email for license {license_id}: {e}", exc_info=True)
    
    async def _poll_telegram(self, license_id: int):
        """Poll Telegram for new messages for phone-number sessions (MTProto)."""
        try:
            # Get Telegram phone session string (if any)
            session_string = await get_telegram_phone_session_data(license_id)
            if not session_string:
                # No phone session configured for this license
                return

            # Get session info for created_at timestamp
            session_info = await get_telegram_phone_session(license_id)
            
            # Calculate since_hours based on when the channel was connected
            # This ensures we ONLY fetch messages received after the channel was connected
            session_created_at = session_info.get("created_at") if session_info else None
            
            if session_created_at:
                # Parse created_at to datetime
                if isinstance(session_created_at, str):
                    try:
                        created_dt = datetime.fromisoformat(session_created_at.replace("Z", "+00:00"))
                        if created_dt.tzinfo:
                            created_dt = created_dt.replace(tzinfo=None)
                    except ValueError:
                        created_dt = None
                elif hasattr(session_created_at, "isoformat"):
                    created_dt = session_created_at
                    if hasattr(created_dt, 'tzinfo') and created_dt.tzinfo:
                        created_dt = created_dt.replace(tzinfo=None)
                else:
                    created_dt = None
                
                if created_dt:
                    hours_since_connected = (datetime.utcnow() - created_dt).total_seconds() / 3600
                    # Add 1 hour buffer to catch any edge cases
                    since_hours = int(hours_since_connected) + 1
                else:
                    # Fallback: if no created_at, only fetch last 1 hour
                    since_hours = 1
            else:
                # No created_at means new config, only fetch last 1 hour
                since_hours = 1
            
            # Check for backfill trigger (first time loading)
            backfill_service = get_backfill_service()
            is_backfill = await backfill_service.should_trigger_backfill(license_id, "telegram")
            
            if is_backfill:
                logger.info(f"Triggering historical backfill for license {license_id} (telegram)")
                since_hours = backfill_service.backfill_days * 24

            phone_service = TelegramPhoneService()

            # Get recent inbox messages for duplicate detection
            # Use higher limit to avoid missing duplicates when inbox is large
            recent_limit = 200
            recent_messages = await get_inbox_messages(license_id, limit=recent_limit)

            # Extract exclude_ids for optimization
            exclude_ids = [msg["channel_message_id"] for msg in recent_messages if msg.get("channel_message_id")]

            # Get active client from listener service - centralized management
            active_client = None
            try:
                from services.telegram_listener_service import get_telegram_listener
                listener = get_telegram_listener()
                
                # This will verify connection or try to start it if missing
                # Crucial: This PREVENTS the "session used under two IP addresses" error
                # by ensuring we only ever use the SINGLE managed client instance
                active_client = await listener.ensure_client_active(license_id)
                
            except Exception as e:
                logger.error(f"Error getting Telegram client from listener: {e}")

            if not active_client:
                # If we can't get the managed client, we should NOT try to create our own
                # independent one, as that triggers the session conflict.
                # Just log and skip this poll cycle.
                logger.info(f"Skipping Telegram poll for {license_id}: Process in Standby Mode")
                return

            # Fetch messages using the managed client
            try:
                # If backfill, use larger limit
                limit = 500 if is_backfill else 200
                messages = await phone_service.get_recent_messages(
                    session_string=session_string,
                    since_hours=since_hours,
                    limit=limit,
                    exclude_ids=exclude_ids,
                    skip_replied=is_backfill,
                    client=active_client # MUST use the reused client
                )
            except Exception as e:
                # If the underlying Telethon client or session is invalid...
                msg = str(e)
                logger.error(f"Error fetching telegram messages for {license_id}: {msg}")
                # We don't deactivate immediately here unless it's a specific auth error,
                # letting the listener service handle connection lifecycle.
                return

            if not messages:
                return

            # If backfill is active, queue ALL fetched messages and skip standard processing
            if is_backfill:
                backfill_messages = []
                for msg in messages:
                    # Apply filters (Spam, Bot, etc.)
                    filter_msg = {
                        "body": msg.get("body", ""),
                        "sender_contact": msg.get("sender_contact"),
                        "sender_name": msg.get("sender_name"),
                        "subject": msg.get("subject"),
                        "attachments": msg.get("attachments", []),
                    }
                    should_process, reason = await apply_filters(filter_msg, license_id, [])
                    if not should_process:
                        logger.debug(f"Skipping backfill telegram from {filter_msg['sender_contact']}: {reason}")
                        continue

                    # Map to backfill format (keys are mostly same)
                    backfill_messages.append({
                        "body": msg.get("body", ""),
                        "channel_message_id": msg.get("channel_message_id"),
                        "sender_contact": msg.get("sender_contact"),
                        "sender_name": msg.get("sender_name"),
                        "sender_id": msg.get("sender_id"),
                        "subject": msg.get("subject"),
                        "received_at": msg.get("received_at"),
                        "attachments": msg.get("attachments")
                    })
                
                queued = await backfill_service.schedule_historical_messages(
                    license_id=license_id,
                    channel="telegram",
                    messages=backfill_messages
                )
                
                if queued > 0:
                    logger.info(f"Queued {queued} telegram messages for backfill. Skipping immediate processing.")
                    return

            # Group messages by sender for burst handling
            # Structure: {sender_contact: [msg_data, ...]}
            grouped_messages: Dict[str, List[Dict]] = {}
            saved_messages_map: Dict[str, int] = {}  # channel_message_id -> db_id
            
            # Parallel Processing for Telegram Messages (Senior Concurrency Fix)
            sem = asyncio.Semaphore(10)
            
            async def process_one_tg_msg(msg):
                async with sem:
                    try:
                        # 1. Check existence
                        existing = await self._check_existing_message(license_id, "telegram", msg.get("channel_message_id"))
                        if existing: return

                        # 2. Handle OUTGOING Sync
                        if msg.get("direction") == "outgoing":
                            existing_outbox = await self._check_existing_outbox_message(license_id, "telegram", msg.get("channel_message_id"))
                            if existing_outbox: return
                            
                            from models.inbox import save_synced_outbox_message
                            await save_synced_outbox_message(
                                license_id=license_id, channel="telegram", body=msg.get("body", ""),
                                recipient_id=msg.get("sender_id"), recipient_name=msg.get("sender_name"),
                                attachments=msg.get("attachments", []), sent_at=msg.get("received_at"),
                                platform_message_id=msg.get("channel_message_id")
                            )
                            return

                        # 3. Apply Filters
                        message_dict = {
                            "body": msg["body"], "sender_contact": msg.get("sender_contact"),
                            "sender_name": msg.get("sender_name"), "sender_id": msg.get("sender_id"),
                            "subject": msg.get("subject"), "channel": "telegram",
                            "attachments": msg.get("attachments", []), "is_group": msg.get("is_group"),
                            "is_channel": msg.get("is_channel")
                        }
                        should_process, reason = await apply_filters(message_dict, license_id, recent_messages)
                        if not should_process: return

                        # 4. Save to Inbox
                        msg_id = await save_inbox_message(
                            license_id=license_id, channel="telegram", body=msg["body"],
                            sender_name=msg.get("sender_name"), sender_contact=msg.get("sender_contact"),
                            sender_id=msg.get("sender_id"), subject=msg.get("subject"),
                            channel_message_id=msg.get("channel_message_id"),
                            received_at=msg.get("received_at"), attachments=msg.get("attachments")
                        )
                        
                        # 5. Store for Burst Processing
                        msg["db_id"] = msg_id
                        sender_key = msg.get("sender_contact") or "unknown"
                        if sender_key not in grouped_messages:
                            grouped_messages[sender_key] = []
                        grouped_messages[sender_key].append(msg)
                        saved_messages_map[msg["channel_message_id"]] = msg_id
                    except Exception as tg_e:
                        logger.error(f"Error processing single Telegram msg: {tg_e}")

            await asyncio.gather(*(process_one_tg_msg(m) for m in messages))


            # Process groups (Burst Handling)
            for sender_key, group in grouped_messages.items():
                if not group:
                    continue
                
                # Sort by time (oldest first) to reconstruct conversation
                group.sort(key=lambda x: x.get("received_at", datetime.min))
                
                if len(group) == 1:
                    # Single message case
                    msg = group[0]
                    await self._analyze_and_process_message(
                        msg["db_id"],
                        msg["body"],
                        license_id,
                        "telegram",
                        msg.get("sender_contact"),
                        msg.get("sender_name"),
                        msg.get("channel_message_id"),
                        attachments=msg.get("attachments")
                    )
                else:
                    # Burst case - merge messages
                    # We process only the LATEST message, but include context from others
                    latest_msg = group[-1]
                    
                    # Combine bodies
                    combined_body = ""
                    for m in group:
                        timestamp = m.get("received_at").strftime("%H:%M") if m.get("received_at") else ""
                        body_text = m['body'] or "[ملف مرفق]"
                        combined_body += f"[{timestamp}] {body_text}\n"
                    
                    combined_body = combined_body.strip()
                    logger.info(f"Burst detected for {sender_key}: merged {len(group)} messages")
                    
                    # Mark previous messages as 'analyzed' with special note
                    for m in group[:-1]:
                        # Update status to 'analyzed' (handled) for merged messages
                        try:
                            await update_inbox_status(m["db_id"], "analyzed")
                        except Exception as e:
                            logger.error(f"Failed to mark merged message {m['db_id']}: {e}")

                    # Process the latest message with combined context
                    # Pass original attachments from ALL messages
                    all_attachments = []
                    for m in group:
                        if m.get("attachments"): 
                            all_attachments.extend(m["attachments"])
                    
                    await self._analyze_and_process_message(
                        latest_msg["db_id"],
                        combined_body, # Use combined body for AI understanding
                        license_id,
                        "telegram",
                        latest_msg.get("sender_contact"),
                        latest_msg.get("sender_name"),
                        latest_msg.get("channel_message_id"),
                        attachments=all_attachments
                    )

            # Update last sync time
            await update_telegram_phone_session_sync_time(license_id)

        except Exception as e:
            logger.error(f"Error polling Telegram phone for license {license_id}: {e}", exc_info=True)
    
    async def _check_existing_message(self, license_id: int, channel: str, channel_message_id: Optional[str]) -> bool:
        """Check if a message already exists in inbox"""
        if not channel_message_id:
            return False
        
        try:
            async with get_db() as db:
                row = await fetch_one(
                    db,
                    "SELECT id FROM inbox_messages WHERE license_key_id = ? AND channel = ? AND channel_message_id = ?",
                    [license_id, channel, channel_message_id],
                )
                return row is not None
        except Exception as e:
            logger.error(f"Error checking existing message: {e}")
            return False
    
    async def _check_existing_outbox_message(self, license_id: int, channel: str, platform_message_id: Optional[str]) -> bool:
        """
        Check if an outgoing message already exists in outbox (synced messages).
        Note: outbox_messages table doesn't have platform_message_id column,
        so we check inbox_messages first (where synced outgoing messages are also stored)
        and use in-memory cache for polling cycles.
        """
        if not platform_message_id:
            return False
        
        # Check in-memory cache first (to avoid duplicate inserts within same polling cycle)
        cache_key = f"outbox_{license_id}_{channel}_{platform_message_id}"
        if hasattr(self, '_outbox_sync_cache') and cache_key in self._outbox_sync_cache:
            return True
        
        # Initialize cache if needed
        if not hasattr(self, '_outbox_sync_cache'):
            self._outbox_sync_cache = set()
        
        # Also check inbox_messages table since outgoing messages from Telegram listener
        # may already be stored there via the live handler
        try:
            async with get_db() as db:
                row = await fetch_one(
                    db,
                    "SELECT id FROM inbox_messages WHERE license_key_id = ? AND channel = ? AND channel_message_id = ?",
                    [license_id, channel, platform_message_id],
                )
                if row:
                    return True
                    
                # For outbox, check by timestamp window and body to avoid re-syncing same message
                # This is a best-effort check since outbox lacks exact message ID
                return False
        except Exception as e:
            logger.error(f"Error checking existing outbox message: {e}")
            return False

    
    async def _analyze_and_process_message(
        self,
        message_id: int,
        body: str,
        license_id: int,
        channel: str,
        recipient: str,
        sender_name: Optional[str] = None,
        channel_message_id: Optional[str] = None,
        attachments: Optional[List[dict]] = None
    ):
        """
        Only handles notifications and basic message housekeeping.
        """
        try:
            from services.analysis_service import process_inbox_message_logic
            
            # Delegate to standard processing logic
            await process_inbox_message_logic(
                message_id=message_id,
                body=body,
                license_id=license_id,
                attachments=attachments
            )
        except Exception as e:
            logger.error(f"Error processing message {message_id}: {e}")

    

    
    async def _send_message(self, outbox_id: int, license_id: int, channel: str):
        """Send an approved message (Text, Attachments, Audio) with Caption support"""
        from services.delivery_status import save_platform_message_id
        import base64
        import tempfile
        import mimetypes
        import os
        import json

        try:
            # Get outbox message (works for both SQLite and PostgreSQL)
            async with get_db() as db:
                rows = await fetch_all(
                    db,
                    """
                    SELECT o.*, i.sender_name, i.body as original_message, i.sender_contact, i.sender_id
                    FROM outbox_messages o
                    LEFT JOIN inbox_messages i ON o.inbox_message_id = i.id
                    WHERE o.id = ? AND o.license_key_id = ?
                    """,
                    [outbox_id, license_id],
                )

            if not rows:
                logger.error(f"Unified Send: Outbox message {outbox_id} not found for license {license_id}")
                await mark_outbox_failed(outbox_id, "Outbox message record not found in database")
                return
            message = rows[0]
            
            # Extract Audio Tag
            import re
            body = (message["body"] or "").strip()
            audio_path = None
            audio_match = re.search(r'\[AUDIO: (.*?)\]', body)
            if audio_match:
                audio_path = audio_match.group(1).strip()
                body = body.replace(audio_match.group(0), "").strip()
            
            # Parse attachments
            attachments_list = []
            if message.get("attachments"):
                if isinstance(message["attachments"], str):
                    try: attachments_list = json.loads(message["attachments"])
                    except: pass
                elif isinstance(message["attachments"], list):
                    attachments_list = message["attachments"]

            sent_anything = False
            last_platform_id = None

            # CRITICAL: Channel-specific unified sending
            # If we have media AND text, we should send them together as a caption where supported
            
            # --- INTERNAL CHANNELS ---
            if channel == "saved":
                # Special case: self-chat
                sent_anything = True
                last_platform_id = f"saved_{message['id']}"
                # Ensure conversation state updated for Saved Messages
                from models.inbox import upsert_conversation_state
                await upsert_conversation_state(license_id, "__saved_messages__", channel="saved")
            
            elif channel == "almudeer":
                # Almudeer Internal Channel: Peer-to-Peer delivery between license holders
                # recipient_email stores the target username
                recipient_username = message.get("recipient_email")
                if recipient_username:
                    async with get_db() as db:
                        # 1. Find target license holder
                        target_license = await fetch_one(db, "SELECT id, full_name as company_name FROM license_keys WHERE username = ?", [recipient_username])
                        if target_license:
                            # 2. Resolve sender info for recipient view
                            sender_license = await fetch_one(db, "SELECT username, full_name as company_name FROM license_keys WHERE id = ?", [license_id])
                            sender_username = (sender_license["username"] if sender_license else None) or "mudeer_user"
                            sender_company = (sender_license["company_name"] if sender_license else "Al-Mudeer User")
                            
                            # 3. Deliver to Target Inbox
                            from models.inbox import save_inbox_message
                            internal_platform_id = f"alm_{message['id']}"
                            new_inbox_id = await save_inbox_message(
                                license_id=target_license["id"],
                                channel="almudeer",
                                body=body,
                                sender_contact=sender_username,
                                sender_name=sender_company,
                                sender_id=sender_username,
                                received_at=datetime.utcnow(),
                                attachments=attachments_list,
                                platform_message_id=internal_platform_id,
                                status='analyzed'
                            )
                            # 4. Broadcast to Recipient
                            if new_inbox_id:
                                from services.websocket_manager import broadcast_new_message
                                await broadcast_new_message(target_license["id"], {
                                    "id": new_inbox_id,
                                    "license_key_id": target_license["id"],
                                    "channel": "almudeer",
                                    "sender_contact": sender_username,
                                    "sender_name": sender_company,
                                    "body": body,
                                    "attachments": attachments_list,
                                    "received_at": datetime.utcnow().isoformat(),
                                    "status": "analyzed",
                                    "direction": "incoming"
                                })
                            
                            # 5. Broadcast "Sent" status back to SOURCE (Real-time UI update for the sender)
                            from services.websocket_manager import broadcast_message_status_update
                            await broadcast_message_status_update(license_id, {
                                "outbox_id": outbox_id,
                                "sender_contact": recipient_username,
                                "status": "sent",
                                "timestamp": datetime.utcnow().isoformat()
                            })
                            
                            # 6. Update Conversation State for both sides
                            from models.inbox import upsert_conversation_state
                            await upsert_conversation_state(target_license["id"], sender_username, channel="almudeer")
                            await upsert_conversation_state(license_id, recipient_username, channel="almudeer")

                            sent_anything = True
                            last_platform_id = internal_platform_id
                        else:
                            from logging_config import get_logger
                            get_logger(__name__).error(f"Internal delivery failed: Recipient license holder '{recipient_username}' not found.")

            # --- EXTERNAL CHANNELS ---
            elif channel == "email":
                from services.gmail_api_service import GmailAPIService
                from services.gmail_oauth_service import GmailOAuthService
                from models.email_config import get_email_oauth_tokens
                tokens = await get_email_oauth_tokens(license_id)
                if tokens and tokens.get("access_token"):
                    gs = GmailAPIService(tokens["access_token"], tokens.get("refresh_token"), GmailOAuthService())
                    res = await gs.send_message(
                        to_email=message["recipient_email"],
                        subject=message.get("subject", "رد على رسالتك"),
                        body=body,
                        reply_to_message_id=message.get("reply_to_platform_id"),
                        attachments=attachments_list 
                    )
                    if res:
                        sent_anything = True
                        last_platform_id = str(res.get("id"))

            elif channel in ["whatsapp", "telegram", "telegram_bot"]:
                # Optimization for Telegram: Group media into an album if possible
                media_for_album = []
                other_attachments = []
                
                if channel in ["telegram", "telegram_bot"] and len(attachments_list) > 1:
                    for att in attachments_list:
                        mime = att.get("mime_type") or mimetypes.guess_type(att["filename"])[0] or ""
                        if mime.startswith("image/") or mime.startswith("video/"):
                            media_for_album.append(att)
                        else:
                            other_attachments.append(att)
                    
                    # Albums in Telegram require at least 2 items
                    if len(media_for_album) < 2:
                        other_attachments = attachments_list
                        media_for_album = []
                else:
                    other_attachments = attachments_list

                # Case 1: Send as Text-only (if no attachments and no audio)
                if not attachments_list and not audio_path:
                    if body:
                        try:
                            if channel == "whatsapp":
                                config = await get_whatsapp_config(license_id)
                                if config:
                                    ws = WhatsAppService(config["phone_number_id"], config["access_token"])
                                    recipient = message.get("recipient_id") or message.get("recipient_email")
                                    if not recipient: raise ValueError("No recipient specified")
                                    res = await ws.send_message(to=recipient, message=body, reply_to_message_id=message.get("reply_to_platform_id"))
                                    if res["success"]:
                                        sent_anything = True
                                        last_platform_id = res.get("message_id")
                            elif channel == "telegram_bot":
                                async with get_db() as db:
                                    row = await fetch_one(db, "SELECT bot_token FROM telegram_configs WHERE license_key_id = ?", [license_id])
                                    if row and row.get("bot_token"):
                                        ts = TelegramService(row["bot_token"])
                                        recipient = message.get("recipient_id") or message.get("recipient_email")
                                        if not recipient: raise ValueError("No recipient specified")
                                        res = await ts.send_message(chat_id=recipient, text=body, reply_to_message_id=message.get("reply_to_id"))
                                        sent_anything = True
                                        if res: last_platform_id = str(res.get("message_id"))
                            elif channel == "telegram":
                                session = await get_telegram_phone_session_data(license_id)
                                if session:
                                    from services.telegram_listener_service import get_telegram_listener
                                    listener = get_telegram_listener()
                                    active_client = await listener.ensure_client_active(license_id)
                                    ps = TelegramPhoneService()
                                    recipient = message.get("recipient_id") or message.get("recipient_email") or message.get("sender_id")
                                    if recipient:
                                        res = await ps.send_message(session_string=session, recipient_id=str(recipient), text=body, reply_to_message_id=message.get("reply_to_id"), client=active_client)
                                        sent_anything = True
                                        if res: last_platform_id = str(res.get("id"))
                        except Exception as text_e:
                            logger.error(f"Error sending text via {channel}: {text_e}")

                # Case 2: Send Album (Telegram Only)
                if media_for_album:
                    try:
                        tmp_paths = []
                        album_payload = []
                        caption = body if body else None
                        
                        for att in media_for_album:
                            file_data = base64.b64decode(att["base64"])
                            suffix = os.path.splitext(att["filename"])[1]
                            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                                tmp.write(file_data)
                                tpath = tmp.name
                                tmp_paths.append(tpath)
                                
                            mime = att.get("mime_type") or mimetypes.guess_type(att["filename"])[0] or "image/jpeg"
                            item_type = "video" if mime.startswith("video/") else "photo"
                            album_payload.append({"type": item_type, "path": tpath})
                        
                        # Add caption to the first item for Bot, or pass separate for Phone
                        if album_payload and caption:
                            album_payload[0]["caption"] = caption

                        try:
                            if channel == "telegram_bot":
                                async with get_db() as db:
                                    row = await fetch_one(db, "SELECT bot_token FROM telegram_configs WHERE license_key_id = ?", [license_id])
                                    if row and row.get("bot_token"):
                                        ts = TelegramService(row["bot_token"])
                                        recipient = message.get("recipient_id") or message.get("recipient_email")
                                        res = await ts.send_media_group(chat_id=recipient, media_items=album_payload, reply_to_message_id=message.get("reply_to_id"))
                                        if res:
                                            sent_anything = True
                                            last_platform_id = str(res[0].get("message_id"))
                            elif channel == "telegram":
                                session = await get_telegram_phone_session_data(license_id)
                                if session:
                                    from services.telegram_listener_service import get_telegram_listener
                                    listener = get_telegram_listener()
                                    active_client = await listener.ensure_client_active(license_id)
                                    ps = TelegramPhoneService()
                                    recipient = message.get("recipient_id") or message.get("recipient_email") or message.get("sender_id")
                                    res = await ps.send_album(session_string=session, recipient_id=str(recipient), file_paths=tmp_paths, caption=caption, reply_to_message_id=message.get("reply_to_id"), client=active_client)
                                    if res:
                                        sent_anything = True
                                        last_platform_id = str(res[0].get("id"))
                        finally:
                            for p in tmp_paths:
                                try: os.remove(p)
                                except: pass
                    except Exception as album_e:
                        logger.error(f"Error sending album: {album_e}")
                        # Fallback: add items back to other_attachments to send one by one
                        other_attachments = media_for_album + other_attachments

                # Case 3: Send Remaining Attachments (or first if no album)
                for i, att in enumerate(other_attachments):
                    if not att.get("base64") or not att.get("filename"): continue
                    try:
                        file_data = base64.b64decode(att["base64"])
                        suffix = os.path.splitext(att["filename"])[1]
                        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                            tmp.write(file_data)
                            tmp_path = tmp.name
                        
                        try:
                            mime_type = att.get("mime_type") or mimetypes.guess_type(att["filename"])[0] or "application/octet-stream"
                            # Use body as caption if this is the first thing sent
                            caption = body if (body and not sent_anything and i == 0) else None
                            
                            if channel == "whatsapp":
                                config = await get_whatsapp_config(license_id)
                                if config:
                                    ws = WhatsAppService(config["phone_number_id"], config["access_token"])
                                    mid = await ws.upload_media(tmp_path, mime_type=mime_type)
                                    if mid:
                                        recipient = message.get("recipient_id") or message.get("recipient_email")
                                        if recipient:
                                            res = None
                                            if mime_type.startswith("image/"): res = await ws.send_image_message(recipient, mid, caption=caption, reply_to_message_id=message.get("reply_to_platform_id"))
                                            elif mime_type.startswith("video/"): res = await ws.send_video_message(recipient, mid, caption=caption, reply_to_message_id=message.get("reply_to_platform_id"))
                                            else: res = await ws.send_document_message(recipient, mid, att["filename"], caption=caption, reply_to_message_id=message.get("reply_to_platform_id"))
                                            if res and res.get("success"):
                                                sent_anything = True
                                                last_platform_id = res.get("message_id")
                            elif channel == "telegram_bot":
                                async with get_db() as db:
                                    row = await fetch_one(db, "SELECT bot_token FROM telegram_configs WHERE license_key_id = ?", [license_id])
                                    if row and row.get("bot_token"):
                                        ts = TelegramService(row["bot_token"])
                                        recipient = message.get("recipient_id") or message.get("recipient_email")
                                        if recipient:
                                            res = None
                                            if mime_type.startswith("image/"): res = await ts.send_photo(chat_id=recipient, photo_path=tmp_path, caption=caption, reply_to_message_id=message.get("reply_to_id"))
                                            elif mime_type.startswith("video/"): res = await ts.send_video(chat_id=recipient, video_path=tmp_path, caption=caption, reply_to_message_id=message.get("reply_to_id"))
                                            elif mime_type.startswith("audio/"): res = await ts.send_audio(chat_id=recipient, audio_path=tmp_path, title=caption, reply_to_message_id=message.get("reply_to_id"))
                                            else: res = await ts.send_document(chat_id=recipient, document_path=tmp_path, caption=caption, reply_to_message_id=message.get("reply_to_id"))
                                            if res:
                                                sent_anything = True
                                                last_platform_id = str(res.get("message_id"))
                            elif channel == "telegram":
                                session = await get_telegram_phone_session_data(license_id)
                                if session:
                                    from services.telegram_listener_service import get_telegram_listener
                                    listener = get_telegram_listener()
                                    active_client = await listener.ensure_client_active(license_id)
                                    ps = TelegramPhoneService()
                                    recipient = message.get("recipient_id") or message.get("recipient_email") or message.get("sender_id")
                                    if recipient:
                                        res = await ps.send_file(session_string=session, recipient_id=str(recipient), file_path=tmp_path, caption=caption, reply_to_message_id=message.get("reply_to_id"), client=active_client)
                                        sent_anything = True
                                        if res: last_platform_id = str(res.get("id"))
                        finally:
                            try: os.remove(tmp_path)
                            except: pass
                    except Exception as att_e:
                        logger.error(f"Error sending attachment: {att_e}")

                # Case 4: Send Audio (Voice)
                if audio_path:
                    try:
                        if channel == "whatsapp":
                            config = await get_whatsapp_config(license_id)
                            if config:
                                ws = WhatsAppService(config["phone_number_id"], config["access_token"])
                                mid = await ws.upload_media(audio_path)
                                if mid:
                                    await asyncio.sleep(1) # Extra buffer for audio processing
                                    res = await ws.send_audio_message(
                                        to=recipient, 
                                        media_id=mid,
                                        reply_to_message_id=message.get("reply_to_platform_id")
                                    )
                                    if res and res.get("success"):
                                        sent_anything = True
                                        last_platform_id = res.get("message_id")
                        
                        elif channel == "telegram_bot":
                            async with get_db() as db:
                                row = await fetch_one(db, "SELECT bot_token FROM telegram_configs WHERE license_key_id = ?", [license_id])
                                if row and row.get("bot_token"):
                                    ts = TelegramService(row["bot_token"])
                                    await asyncio.sleep(1)
                                    recipient = message.get("recipient_id") or message.get("recipient_email")
                                    res = await ts.send_voice(
                                        chat_id=recipient, 
                                        audio_path=audio_path,
                                        reply_to_message_id=message.get("reply_to_id")
                                    )
                                    if res:
                                        sent_anything = True
                                        last_platform_id = str(res.get("message_id"))

                        elif channel == "telegram":
                            session = await get_telegram_phone_session_data(license_id)
                            if session:
                                from services.telegram_listener_service import get_telegram_listener
                                listener = get_telegram_listener()
                                active_client = await listener.ensure_client_active(license_id)
                                ps = TelegramPhoneService()
                                recipient = message.get("recipient_id") or message.get("recipient_email") or message.get("sender_id")
                                if recipient:
                                    await asyncio.sleep(1)
                                    # Forward original body as caption if it's not a standalone text msg
                                    caption = body if body and not sent_anything else None
                                    res = await ps.send_voice(
                                        session_string=session, 
                                        recipient_id=str(recipient), 
                                        audio_path=audio_path, 
                                        caption=caption, 
                                        reply_to_message_id=message.get("reply_to_id"),
                                        client=active_client
                                    )
                                    if res:
                                        sent_anything = True
                                        last_platform_id = str(res.get("id"))
                    except Exception as audio_e:
                        logger.error(f"Error sending audio: {audio_e}")

            # Final Status Update
            if sent_anything:
                await mark_outbox_sent(outbox_id)
                if last_platform_id:
                    await save_platform_message_id(outbox_id, last_platform_id)
            else:
                await mark_outbox_failed(outbox_id, "Failed to send message via any method")        
        except Exception as e:
            logger.error(f"Critical error sending outbox {outbox_id}: {e}", exc_info=True)
            await mark_outbox_failed(outbox_id, f"Internal Worker Error: {str(e)}")
    
    async def _poll_telegram_outbox_status(self, license_id: int):
        """Poll Telegram Phone outbox messages for read receipts"""
        try:
            # Get Telegram phone session string
            session_string = await get_telegram_phone_session_data(license_id)
            if not session_string:
                return

            # Find outbox messages that are 'sent' or 'delivered' (not 'read' or 'failed')
            # and imply 'telegram' channel
            # Calculate 24h cutoff in Python for DB compatibility
            cutoff = datetime.utcnow() - timedelta(hours=24)
            cutoff_value = cutoff if DB_TYPE == "postgresql" else cutoff.isoformat()

            async with get_db() as db:
                rows = await fetch_all(
                    db,
                    """
                    SELECT id, platform_message_id, delivery_status, created_at
                    FROM outbox_messages
                    WHERE license_key_id = ? 
                      AND channel = 'telegram'
                      AND delivery_status IN ('sent', 'delivered')
                      AND platform_message_id IS NOT NULL
                      AND created_at > ?
                    """,
                    [license_id, cutoff_value]
                )
            
            if not rows:
                return

            platform_ids = [row["platform_message_id"] for row in rows]
            
             # [FIX] Use Centralized Client
            from services.telegram_listener_service import get_telegram_listener
            listener = get_telegram_listener()
            active_client = await listener.ensure_client_active(license_id)
            
            phone_service = TelegramPhoneService()
            
            # Identify status
            statuses = await phone_service.get_messages_read_status(
                session_string=session_string,
                channel_message_ids=platform_ids,
                client=active_client # Might be None
            )
            
            # Update statuses
            from services.delivery_status import update_delivery_status
            
            count = 0
            for platform_id, status in statuses.items():
                if status == "read":
                    updated = await update_delivery_status(platform_id, "read")
                    if updated:
                        count += 1
            
            if count > 0:
                logger.info(f"Updated {count} Telegram messages to READ for license {license_id}")

        except Exception as e:
            logger.error(f"Error polling Telegram outbox status: {e}")

    async def _update_email_last_checked(self, license_id: int):
        """Update last_checked_at timestamp for email config"""
        try:
            # For PostgreSQL we should store a real datetime object.
            # For SQLite we keep using ISO strings for backward compatibility.
            from db_helper import DB_TYPE  # Local import to avoid circulars
            now_value = datetime.utcnow() if DB_TYPE == "postgresql" else datetime.utcnow().isoformat()

            async with get_db() as db:
                await execute_sql(
                    db,
                    """
                    UPDATE email_configs 
                    SET last_checked_at = ? 
                    WHERE license_key_id = ?
                    """,
                    [now_value, license_id],
                )
                await commit_db(db)
        except Exception as e:
            logger.error(f"Error updating last_checked_at: {e}")


# Global poller instance
_poller: Optional[MessagePoller] = None


async def start_message_polling():
    """Start the message polling service"""
    global _poller
    if _poller is None:
        _poller = MessagePoller()
        await _poller.start()
    return _poller


async def stop_message_polling():
    """Stop the message polling service"""
    global _poller
    if _poller:
        await _poller.stop()
        _poller = None


def get_worker_status() -> Dict[str, Dict[str, Optional[str]]]:
    """
    Lightweight status snapshot for background workers.

    This is intentionally simple and read-only so the frontend dashboard can
    show whether polling is running without depending on internal details.
    """
    status = "running" if _poller is not None and _poller.running else "stopped"
    now = datetime.utcnow().isoformat() + "Z"

    # Shape is aligned with frontend WorkerStatus type (email_polling, telegram_polling)
    return {
        "email_polling": {
            "last_check": now,
            "status": status,
            "next_check": None,
        },
        "telegram_polling": {
            "last_check": now,
            "status": status,
        },
    }


# ============ Subscription Reminder Worker ============

_subscription_reminder_task: Optional[asyncio.Task] = None


async def check_subscription_reminders():
    """
    Check for subscriptions expiring in 3 days and send notifications.
    Runs once per day.
    """
    from models import create_notification
    
    try:
        async with get_db() as db:
            # Find subscriptions expiring in exactly 3 days
            if DB_TYPE == "postgresql":
                # PostgreSQL: use CURRENT_DATE + INTERVAL
                rows = await fetch_all(
                    db,
                    """
                    SELECT id, full_name as company_name, expires_at, contact_email
                    FROM license_keys 
                    WHERE is_active = TRUE 
                    AND DATE(expires_at) = CURRENT_DATE + INTERVAL '3 days'
                    """,
                    []
                )
            else:
                # SQLite: use date arithmetic
                rows = await fetch_all(
                    db,
                    """
                    SELECT id, full_name as company_name, expires_at, contact_email
                    FROM license_keys 
                    WHERE is_active = 1 
                    AND DATE(expires_at) = DATE('now', '+3 days')
                    """,
                    []
                )
            
            if not rows:
                logger.info("No subscriptions expiring in 3 days")
                return
            
            # Send reminder notifications
            for row in rows:
                license_id = row["id"]
                company_name = row.get("company_name", "Unknown")
                
                try:
                    await create_notification(
                        license_id=license_id,
                        notification_type="subscription_expiring",
                        title="⚠️ اشتراكك ينتهي قريباً",
                        message=f"اشتراكك في المدير ينتهي خلال 3 أيام. يرجى تجديد الاشتراك لضمان استمرار الخدمة.",
                        priority="high",
                        link="/dashboard/settings"
                    )
                    logger.info(f"Sent subscription reminder to license {license_id} ({company_name})")
                except Exception as e:
                    logger.warning(f"Failed to send reminder to license {license_id}: {e}")
                    
    except Exception as e:
        logger.error(f"Error checking subscription reminders: {e}", exc_info=True)


async def _subscription_reminder_loop():
    """Background loop that runs once per day to check subscription reminders."""
    while True:
        try:
            await check_subscription_reminders()
        except Exception as e:
            logger.error(f"Error in subscription reminder loop: {e}", exc_info=True)
        
        # Wait 24 hours before next check
        await asyncio.sleep(24 * 60 * 60)


async def start_subscription_reminders():
    """Start the subscription reminder background task."""
    global _subscription_reminder_task
    if _subscription_reminder_task is None:
        _subscription_reminder_task = asyncio.create_task(_subscription_reminder_loop())
        logger.info("Started subscription reminder worker")


async def stop_subscription_reminders():
    """Stop the subscription reminder background task."""
    global _subscription_reminder_task
    if _subscription_reminder_task:
        _subscription_reminder_task.cancel()
        _subscription_reminder_task = None
        logger.info("Stopped subscription reminder worker")


# ============ FCM Token Cleanup Worker ============

_token_cleanup_task: Optional[asyncio.Task] = None


async def _token_cleanup_loop():
    """Background loop that runs once per day to clean up expired FCM tokens."""
    while True:
        try:
            from services.fcm_mobile_service import cleanup_expired_tokens
            # Cleanup tokens inactive for > 30 days
            cleaned = await cleanup_expired_tokens(days_inactive=30)
            if cleaned > 0:
                logger.info(f"Daily Cleanup: Removed {cleaned} expired FCM tokens")
        except Exception as e:
            logger.error(f"Error in token cleanup loop: {e}", exc_info=True)
        
        # Wait 24 hours before next check
        # Add random jitter to avoid thundering herd if we had multiple instances
        await asyncio.sleep(24 * 60 * 60 + random.randint(0, 3600))


async def start_token_cleanup_worker():
    """Start the token cleanup background task."""
    global _token_cleanup_task
    if _token_cleanup_task is None:
        _token_cleanup_task = asyncio.create_task(_token_cleanup_loop())
        logger.info("Started FCM token cleanup worker")


async def stop_token_cleanup_worker():
    """Stop the token cleanup background task."""
    global _token_cleanup_task
    if _token_cleanup_task:
        _token_cleanup_task.cancel()
        _token_cleanup_task = None
        logger.info("Stopped FCM token cleanup worker")


# ============ Stories Cleanup Worker ============

_story_cleanup_task: Optional[asyncio.Task] = None


async def _story_cleanup_loop():
    """Background loop that runs once every hour to clean up expired stories."""
    while True:
        try:
            from models.stories import cleanup_expired_stories
            await cleanup_expired_stories()
            logger.info("Hourly Cleanup: Removed expired stories and media references")
        except Exception as e:
            logger.error(f"Error in story cleanup loop: {e}", exc_info=True)
        
        # Wait 1 hour before next check
        await asyncio.sleep(60 * 60)


async def start_story_cleanup_worker():
    """Start the story cleanup background task."""
    global _story_cleanup_task
    if _story_cleanup_task is None:
        _story_cleanup_task = asyncio.create_task(_story_cleanup_loop())
        logger.info("Started Stories cleanup worker")


async def stop_story_cleanup_worker():
    """Stop the story cleanup background task."""
    global _story_cleanup_task
    if _story_cleanup_task:
        _story_cleanup_task.cancel()
        _story_cleanup_task = None
        logger.info("Stopped Stories cleanup worker")

# ============ Task Queue Worker ============

class TaskWorker:
     """
     Persistent Worker for DB-backed Task Queue.
     """
     def __init__(self, worker_id: str = "worker-main"):
         self.worker_id = worker_id
         self.running = False
         self._loop_task = None
         
     async def start(self):
         self.running = True
         logger.info(f"TaskWorker {self.worker_id} started")
         self._loop_task = asyncio.create_task(self._process_loop())
         
     async def stop(self):
         self.running = False
         if self._loop_task:
             self._loop_task.cancel()
             try:
                 await self._loop_task
             except: pass
         logger.info(f"TaskWorker {self.worker_id} stopped")
 
     async def _process_loop(self):
         while self.running:
             try:
                 # 1. Fetch Task
                 task = await fetch_next_task(self.worker_id)
                 
                 if not task:
                     await asyncio.sleep(1.0 + random.uniform(0.1, 0.5)) # Idle wait with jitter
                     continue
                 
                 task_id = task["id"]
                 task_type = task["task_type"]
                 payload = task["payload"]
                 
                 logger.info(f"Processing task {task.get('id')}: {task_type}")
                 
                 # 2. Execute Logic
                 try:
                     result = None
                     if task_type == "analyze_message":
                          # Process and analyze using centralized service
                        from services.analysis_service import process_inbox_message_logic
                        
                        await process_inbox_message_logic(
                            message_id=payload.get("message_id"),
                            body=payload.get("body"),
                            license_id=payload.get("license_id"),
                            telegram_chat_id=payload.get("telegram_chat_id"),
                            attachments=payload.get("attachments")
                        )
                     elif task_type == "analyze":
                          # Generic analyze from main.py endpoint - DISABLED (agent.py removed)
                          # from agent import process_message
                          # result = await process_message(
                          #     message=payload.get("message"),
                          #     message_type=payload.get("message_type"),
                          #     sender_name=payload.get("sender_name"),
                          #     sender_contact=payload.get("sender_contact"),
                          # )
                          pass
                     
                     # 3. Complete
                     await complete_task(task_id)
                     logger.info(f"Task {task_id} completed")
                     
                 except Exception as e:
                     logger.error(f"Task {task_id} failed: {e}", exc_info=True)
                     await fail_task(task_id, str(e))
                     
             except Exception as outer_e:
                 import traceback
                 logger.error(f"Worker loop CRITICAL error (will restart in 5s): {outer_e}\n{traceback.format_exc()}")
                 await asyncio.sleep(5.0)
