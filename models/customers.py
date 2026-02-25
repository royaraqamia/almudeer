"""
Al-Mudeer - Customer Models
Customer profiles, lead scoring, analytics, preferences, notifications, and team management
"""

import os
from datetime import datetime, timedelta, date
from typing import Optional, List

from db_helper import (
    get_db,
    execute_sql,
    fetch_all,
    fetch_one,
    commit_db,
    DB_TYPE,
    DATABASE_PATH
)
if DB_TYPE != "postgresql":
    import aiosqlite


# ============ Customer Profiles ============

async def get_or_create_customer(
    license_id: int,
    name: str = None,
    phone: str = None,
    email: str = None,
    username: str = None,
    has_whatsapp: bool = False,
    has_telegram: bool = False,
    is_manual: bool = False
) -> dict:
    """Get existing customer or create new one (SQLite & PostgreSQL compatible)."""
    
    # Anti-Bot & Spam Guard
    if not is_manual:
        blocked_keywords = [
            "bot", "api", 
            "no-reply", "noreply", "donotreply",
            "newsletter", "bulletin", 
            "calendly", "submagic", "iconscout"
        ]
        if name and any(k in name.lower() for k in blocked_keywords):
            return {"id": None}
    
    async with get_db() as db:
        # Check existing by phone/email
        row = None
        if phone:
            row = await fetch_one(db, """
                SELECT *, (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = customers.username AND customers.username IS NOT NULL)) as is_almudeer_user
                FROM customers WHERE license_key_id = ? AND phone = ?
            """, [license_id, phone])
        if not row and email:
            row = await fetch_one(db, """
                SELECT *, (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = customers.username AND customers.username IS NOT NULL)) as is_almudeer_user
                FROM customers WHERE license_key_id = ? AND email = ?
            """, [license_id, email])
        
        if row:
            return dict(row)
        
        # Create new customer
        contact_val = phone or email
        if not contact_val:
            from datetime import datetime
            contact_val = f"unknown_{license_id}_{int(datetime.now().timestamp())}"

        if DB_TYPE == "postgresql":
            # PostgreSQL: use RETURNING to get ID atomicly
            try:
                sql = """
                    INSERT INTO customers (license_key_id, contact, name, username, phone, email, has_whatsapp, has_telegram)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    RETURNING id
                """
                # adapt_sql_for_db might need to be careful with RETURNING, but execute_sql handles it
                res = await fetch_one(db, sql, [license_id, contact_val, name, username, phone, email, has_whatsapp, has_telegram])
                inserted_id = res["id"] if res else None
            except Exception as e:
                # Handle potential conflicts or errors
                print(f"Postgres Insert Error: {e}")
                inserted_id = None
        else:
            # SQLite: use lastrowid
            res = await execute_sql(
                db,
                """
                INSERT INTO customers (license_key_id, contact, name, username, phone, email, has_whatsapp, has_telegram)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [license_id, contact_val, name, username, phone, email, has_whatsapp, has_telegram]
            )
            await commit_db(db)
            inserted_id = res.lastrowid

        if inserted_id:
            row = await fetch_one(db, """
                SELECT *, (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = customers.username AND customers.username IS NOT NULL)) as is_almudeer_user
                FROM customers WHERE id = ?
            """, [inserted_id])
            if row:
                return dict(row)
            
        return {
            "id": inserted_id,
            "license_key_id": license_id,
            "name": name,
            "username": username,
            "phone": phone,
            "email": email,
            "contact": contact_val,
            "is_vip": False,
            "has_whatsapp": has_whatsapp,
            "has_telegram": has_telegram
        }


async def get_customers(license_id: int, limit: int = 100) -> List[dict]:
    """Get all customers for a license (SQLite & PostgreSQL compatible)."""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT c.*, 
                   (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = c.username AND c.username IS NOT NULL)) as is_almudeer_user
            FROM customers c
            WHERE c.license_key_id = ? 
            ORDER BY c.last_contact_at DESC
            LIMIT ?
            """,
            [license_id, limit],
        )
        return rows


async def get_customers_delta(license_id: int, since: datetime, limit: int = 100) -> List[dict]:
    """Get customers updated/active since a specific timestamp."""
    # For SQLite compatibility with ISO strings
    ts_value = since if DB_TYPE == "postgresql" else since.isoformat()
    
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT c.*, 
                   (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = c.username AND c.username IS NOT NULL)) as is_almudeer_user
            FROM customers c
            WHERE c.license_key_id = ? 
            AND (c.last_contact_at > ? OR c.created_at > ?)
            ORDER BY c.last_contact_at DESC
            LIMIT ?
            """,
            [license_id, ts_value, ts_value, limit],
        )
        return rows


async def get_customer(license_id: int, customer_id: int) -> Optional[dict]:
    """Get a specific customer"""
    async with get_db() as db:
        row = await fetch_one(
            db,
            """
            SELECT c.*, 
                   (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = c.username AND c.username IS NOT NULL)) as is_almudeer_user
            FROM customers c
            WHERE c.id = ? AND c.license_key_id = ?
            """,
            [customer_id, license_id]
        )
        return dict(row) if row else None


async def update_customer(
    license_id: int,
    customer_id: int,
    **kwargs
) -> bool:
    """Update customer details"""
    allowed_fields = ['name', 'username', 'phone', 'email', 'company', 'notes', 'tags', 'is_vip', 'profile_pic_url', 'has_whatsapp', 'has_telegram']
    updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
    
    if not updates:
        return False
    
    set_clause = ", ".join(f"{k} = ?" for k in updates.keys())
    values = list(updates.values()) + [customer_id, license_id]

    async with get_db() as db:
        res = await execute_sql(
            db,
            f"""
            UPDATE customers SET {set_clause}
            WHERE id = ? AND license_key_id = ?
            """,
            values
        )
        await commit_db(db)
        
        if DB_TYPE == "postgresql":
            return "UPDATE 1" in str(res)
        else:
            return getattr(res, "rowcount", 0) > 0





async def get_recent_conversation(
    license_id: int,
    sender_contact: str,
    limit: int = 5,
) -> str:
    """
    Get recent messages for a given customer (by sender_contact) as conversation context.
    Returns a single concatenated string (most recent first).
    """
    if not sender_contact:
        return ""

    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT body, created_at, channel
            FROM inbox_messages
            WHERE license_key_id = ?
              AND sender_contact = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            [license_id, sender_contact, limit],
        )

    if not rows:
        return ""

    parts = []
    for row in rows:
        channel = row.get("channel") or ""
        ts = row.get("created_at") or ""
        body = row.get("body") or ""
        parts.append(f"[{channel} @ {ts}] {body}".strip())

    return "\n".join(parts)


async def get_customer_for_message(
    license_id: int,
    inbox_message_id: int,
) -> Optional[dict]:
    """
    Get the customer associated with a specific inbox message via customer_messages.
    """
    async with get_db() as db:
        row = await fetch_one(
            db,
            """
            SELECT c.*
            FROM customers c
            JOIN customer_messages cm
              ON cm.customer_id = c.id
            WHERE cm.inbox_message_id = ?
              AND c.license_key_id = ?
            LIMIT 1
            """,
            [inbox_message_id, license_id],
        )

    return dict(row) if row else None


async def update_last_contact(customer_id: int):
    """Update last contact time for a customer."""
    now = datetime.utcnow()
    
    if DB_TYPE == "postgresql":
        ts_value = now
    else:
        ts_value = now.isoformat()
    
    async with get_db() as db:
        await execute_sql(
            db,
            "UPDATE customers SET last_contact_at = ? WHERE id = ?",
            [ts_value, customer_id]
        )
        await commit_db(db)





def _parse_datetime(value) -> datetime:
    """Helper to parse datetime from various formats."""
    if isinstance(value, datetime):
        return value
    elif isinstance(value, date):
        return datetime.combine(value, datetime.min.time())
    elif isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace('Z', '+00:00'))
        except:
            return None
    return None





# ============ User Preferences ============


# Preferences logic moved to models/preferences.py


# ============ Notifications ============

async def create_notification(
    license_id: int,
    notification_type: str,
    title: str,
    message: str,
    priority: str = "normal",
    link: str = None
) -> int:
    """Create a new notification and send Web Push if subscribers exist."""
    notification_id = 0
    
    async with get_db() as db:
        try:
            await execute_sql(
                db,
                """
                INSERT INTO notifications (license_key_id, type, priority, title, message, link)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [license_id, notification_type, priority, title, message, link],
            )

            row = await fetch_one(
                db,
                """
                SELECT id FROM notifications
                WHERE license_key_id = ?
                ORDER BY id DESC
                LIMIT 1
                """,
                [license_id],
            )
            await commit_db(db)
            notification_id = row["id"] if row else 0
        except Exception as e:
            # Handle NotNullViolationError for missing SERIAL/AUTOINCREMENT on 'id'
            # This can happen on PostgreSQL if table was created without proper SERIAL type
            if "null value in column \"id\"" in str(e):
                # Manual ID generation fallback
                max_row = await fetch_one(db, "SELECT MAX(id) as max_id FROM notifications")
                next_id = (max_row.get("max_id") or 0) + 1
                
                await execute_sql(
                    db,
                    """
                    INSERT INTO notifications (id, license_key_id, type, priority, title, message, link)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [next_id, license_id, notification_type, priority, title, message, link],
                )
                await commit_db(db)
                notification_id = next_id
            else:
                raise e
    
    # Send Web Push notification in background (non-blocking)
    try:
        from services.push_service import send_push_to_license, WEBPUSH_AVAILABLE
        if WEBPUSH_AVAILABLE:
            import asyncio
            asyncio.create_task(
                send_push_to_license(
                    license_id=license_id,
                    title=title,
                    message=message,
                    link=link,
                    tag=f"notification-{notification_id}",
                    priority=priority
                )
            )
    except Exception:
        pass  # Web Push is optional, don't fail if it errors
    
    # Send FCM Mobile Push notification in background (non-blocking)
    try:
        from services.fcm_mobile_service import send_fcm_to_license
        import asyncio
        asyncio.create_task(
            send_fcm_to_license(
                license_id=license_id,
                title=title,
                body=message,
                data={
                    "type": notification_type,
                    "notification_id": str(notification_id),
                    "priority": priority
                },
                link=link
            )
        )
    except Exception:
        pass  # FCM is optional, don't fail if it errors
    
    return notification_id


async def get_notifications(license_id: int, unread_only: bool = False, limit: int = 50) -> List[dict]:
    """Get notifications for a user"""
    async with get_db() as db:
        query = "SELECT * FROM notifications WHERE license_key_id = ?"
        params = [license_id]

        if unread_only:
            query += " AND is_read = FALSE"

        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        rows = await fetch_all(db, query, params)
        return rows


async def get_unread_count(license_id: int) -> int:
    """Get count of unread notifications"""
    async with get_db() as db:
        row = await fetch_one(
            db,
            "SELECT COUNT(*) AS cnt FROM notifications WHERE license_key_id = ? AND is_read = FALSE",
            [license_id],
        )
        return int(row.get("cnt", 0)) if row else 0


async def mark_notification_read(license_id: int, notification_id: int) -> bool:
    """Mark a notification as read"""
    async with get_db() as db:
        await execute_sql(
            db,
            "UPDATE notifications SET is_read = TRUE WHERE id = ? AND license_key_id = ?",
            [notification_id, license_id],
        )
        await commit_db(db)
        return True


async def mark_all_notifications_read(license_id: int) -> bool:
    """Mark all notifications as read"""
    async with get_db() as db:
        await execute_sql(
            db,
            "UPDATE notifications SET is_read = TRUE WHERE license_key_id = ?",
            [license_id],
        )
        await commit_db(db)
        return True


async def delete_old_notifications(days: int = 30):
    """Delete notifications older than specified days"""
    async with get_db() as db:
        if DB_TYPE == "postgresql":
            sql = f"DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '{days} days'"
            await execute_sql(db, sql)
        else:
            await execute_sql(
                db,
                "DELETE FROM notifications WHERE created_at < datetime('now', ?)",
                [f"-{days} days"],
            )
        await commit_db(db)


# Smart notification triggers
async def create_smart_notification(
    license_id: int,
    event_type: str,
    data: dict = None
):
    """Create smart notifications based on events"""
    data = data or {}
    
    CHAT_MESSAGE_EVENTS = {"new_message", "urgent_message", "negative_sentiment", "vip_message"}
    if event_type in CHAT_MESSAGE_EVENTS:
        return None  # Chat notifications disabled

    
    notifications_map = {
        "new_message": {
            "type": "message",
            "priority": "normal",
            "title": "📨 رسالة جديدة",
            "message": f"رسالة جديدة من {data.get('sender', 'مرسل مجهول')}",
            "link": "/dashboard/inbox"
        },
        "urgent_message": {
            "type": "urgent",
            "priority": "high",
            "title": "🔴 رسالة عاجلة",
            "message": f"رسالة عاجلة تحتاج انتباهك من {data.get('sender', 'مرسل')}",
            "link": "/dashboard/inbox"
        },
        "negative_sentiment": {
            "type": "alert",
            "priority": "high",
            "title": "⚠️ عميل غاضب",
            "message": f"تم اكتشاف شكوى من {data.get('customer', 'عميل')}",
            "link": "/dashboard/inbox"
        },
        "vip_message": {
            "type": "vip",
            "priority": "high",
            "title": "⭐ رسالة من عميل VIP",
            "message": f"رسالة من عميل VIP: {data.get('customer', 'عميل مهم')}",
            "link": "/dashboard/inbox"
        },
        "milestone": {
            "type": "achievement",
            "priority": "normal",
            "title": "🎉 إنجاز جديد!",
            "message": data.get('message', 'لقد حققت إنجازاً جديداً!'),
            "link": "/dashboard/inbox"
        },
        "daily_summary": {
            "type": "summary",
            "priority": "low",
            "title": "📊 ملخص اليوم",
            "message": f"تمت معالجة {data.get('count', 0)} رسالة بنجاح",
            "link": "/dashboard/inbox"
        }
    }
    
    if event_type not in notifications_map:
        return None
    
    notif = notifications_map[event_type]
    
    return await create_notification(
        license_id=license_id,
        notification_type=notif["type"],
        title=notif["title"],
        message=notif["message"],
        priority=notif["priority"],
        link=notif.get("link")
    )


async def delete_customer(license_id: int, customer_id: int) -> bool:
    """
    Delete a customer and clean up related data:
    1. Inbox Messages: Links in customer_messages deleted
    3. Library Items: Soft deleted
    4. Orders: Unlinked (customer_contact set to NULL)
    """
    async with get_db() as db:
        # 0. Get customer contact before deletion
        row = await fetch_one(
            db,
            "SELECT contact FROM customers WHERE id = ? AND license_key_id = ?",
            [customer_id, license_id]
        )
        if not row:
            return False
        
        contact = row["contact"]
        from datetime import datetime
        now = datetime.utcnow()
        ts_value = now if DB_TYPE == "postgresql" else now.isoformat()

        # 1. Unlink orders
        await execute_sql(
            db,
            "UPDATE orders SET customer_contact = NULL WHERE customer_contact = ?",
            [contact]
        )

        # 2. Detach library items ONLY (keep visible in general lists)
        await execute_sql(
            db,
            "UPDATE library_items SET customer_id = NULL WHERE customer_id = ? AND license_key_id = ?",
            [customer_id, license_id]
        )

        # 3. Delete from customer_messages links (for integrity, original messages remain)
        await execute_sql(
            db,
            "DELETE FROM customer_messages WHERE customer_id = ?",
            [customer_id]
        )

        # 4. Finally delete the customer
        await execute_sql(
            db,
            "DELETE FROM customers WHERE id = ? AND license_key_id = ?",
            [customer_id, license_id]
        )
        
        await commit_db(db)
        return True


async def delete_customers(license_id: int, customer_ids: List[int]) -> bool:
    """
    Delete multiple customers and clean up related data efficiently.
    """
    if not customer_ids:
        return False
        
    async with get_db() as db:
        # Create placeholders for IN clause
        placeholders = ", ".join(["?"] * len(customer_ids))
        id_params = customer_ids
        
        # 0. Get customer contacts before deletion
        query = f"SELECT contact FROM customers WHERE license_key_id = ? AND id IN ({placeholders})"
        rows = await fetch_all(db, query, [license_id] + id_params)
        
        if not rows:
            return False
            
        contacts = [row["contact"] for row in rows]
        contact_placeholders = ", ".join(["?"] * len(contacts))
        
        # 1. Unlink orders
        if contacts:
            await execute_sql(
                db,
                f"UPDATE orders SET customer_contact = NULL WHERE customer_contact IN ({contact_placeholders})",
                contacts
            )
            
        # 2. Detach library items ONLY
        await execute_sql(
            db,
            f"UPDATE library_items SET customer_id = NULL WHERE license_key_id = ? AND customer_id IN ({placeholders})",
            [license_id] + id_params
        )
        
        # 3. Delete from customer_messages links
        await execute_sql(
            db,
            f"DELETE FROM customer_messages WHERE customer_id IN ({placeholders})",
            id_params
        )
        
        # 4. Finally delete the customers
        await execute_sql(
            db,
            f"DELETE FROM customers WHERE license_key_id = ? AND id IN ({placeholders})",
            [license_id] + id_params
        )
        
        await commit_db(db)
        return True
