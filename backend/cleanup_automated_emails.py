"""
Al-Mudeer - Cleanup Automated Emails from Production
Removes marketing, OTP, ads, newsletters, and other automated emails from inbox_messages table.
Also cleans up automated entries from the customers table.

USAGE:
  # Dry run (preview only, no deletion):
  python cleanup_automated_emails.py --dry-run

  # Actually delete the emails:
  python cleanup_automated_emails.py --execute
"""

import asyncio
import os
import sys
import re
import argparse
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db, DB_TYPE


# ============ FILTER PATTERNS (same as message_filters.py) ============

AUTOMATED_SENDER_PATTERNS = [
    r"^noreply@", r"^no-reply@", r"^no\.reply@",
    r"^notifications?@", r"^newsletter@", r"^newsletters@",
    r"^marketing@", r"^promo@", r"^promotions?@",
    r"^ads?@", r"^advertising@", r"^campaign@",
    r"^info@", r"^support@.*noreply", r"^alerts?@",
    r"^security@", r"^account@", r"^billing@",
    r"^mailer-daemon@", r"^postmaster@", r"^bounce@",
    r"^updates?@", r"^news@", r"^digest@",
    r"^subscriptions?@", r"^automated@", r"^system@",
    r"^donotreply@", r"^do-not-reply@", r"^reply-.*@",
    r"^help@", r"^welcome@", r"^hello@", r"^team@",
    r"^account-security@", r"^account-security-noreply@",
    r"^elsa@", r"^support@", r"^sales@",
    r"@.*\.noreply\.", r"@bounce\.", r"@email\.",
    r"@mail\.", r"@mailer\.", r"@notifications?\.",
    r"@campaign\.", r"@newsletter\.", r"@promo\.",
    r"@help\.",
]

# Service provider noreply patterns (Google, Microsoft, Railway, etc.)
SERVICE_PROVIDER_PATTERNS = [
    r"googleone-noreply", r"google-noreply", r"@google\.com$",
    r"@notify\.railway\.app", r"@github\.com", r"@gitlab\.com",
    r"@microsoft\.com", r"clarity@microsoft", r"@azure\.com",
    r"@accountprotection\.microsoft\.com",
    r"@vercel\.com", r"@netlify\.com", r"@heroku\.com",
    r"@dropbox\.com", r"@slack\.com", r"@zoom\.us",
    r"@stripe\.com", r"@paypal\.com", r"@linkedin\.com",
    r"@twitter\.com", r"@x\.com", r"@facebook\.com",
    r"@meta\.com", r"@apple\.com", r"@amazon\.com",
    r"@openrouter\.ai", r"@elsanow\.io", r"@help\.elsanow\.io",
    r"@aws\.amazon\.com", r"@cloud\.google\.com",
]

OTP_PATTERNS = [
    r"code\s*is\s*\d+", r"code\s*:\s*\d+",
    r"verification\s*code", r"one-time\s*password",
    r"\botp\b", r"passcode", r"pin\s*code",
    r"رمز\s*التحقق", r"كود\s*التفعيل", r"كلمة\s*المرور\s*المؤقتة",
    r"رمز\s*الدخول", r"كود\s*التأكيد", r"رمز\s*التأكيد",
    r"\b\d{4,6}\b.*code", r"code.*\b\d{4,6}\b",
    r"رقم\s*سري", r"رمز\s*أمان",
]

MARKETING_KEYWORDS = [
    "unsubscribe", "opt-out", "stop to end", "manage preferences",
    "promotional", "limited time offer", "special offer", "discount",
    "click here", "click below", "exclusive deal", "act now",
    "advertisement", "sponsored", "promoted", "ad:", "[ad]",
    "flash sale", "today only", "sale ends", "hurry",
    "% off", "save now", "deal of the day", "best price",
    "clearance", "buy now", "shop now", "order now",
    "free shipping", "free trial", "free gift", "bonus",
    "coupon", "voucher", "promo code", "discount code",
    "you've been selected", "congratulations", "winner",
    "claim your", "redeem", "expires soon", "last chance",
    "إلغاء الاشتراك", "أرسل توقف", "عرض خاص", "لفترة محدودة",
    "تخفيضات", "خصم خاص", "اشترك الآن", "عرض حصري",
    "تسوق الآن", "اطلب الآن", "خصم", "عرض اليوم",
    "تنزيلات", "خصم حصري", "أسعار مخفضة", "فرصة لا تعوض",
    "احصل على", "مجاني", "هدية", "جائزة", "فائز", "فوز",
    "كوبون", "قسيمة", "رمز الخصم", "برعاية", "إعلان", "ترويجي",
]

INFO_KEYWORDS = [
    "do not reply", "auto-generated", "system message",
    "no-reply", "noreply", "automated message", "this is an automated",
    "order confirmation", "shipping update", "delivery update",
    "tracking number", "your order has", "has been shipped",
    "payment received", "payment confirmed", "receipt",
    "invoice", "statement", "transaction", "purchase confirmation",
    "لا ترد", "رسالة تلقائية", "تمت العملية بنجاح",
    "عزيزي العميل، تم", "تم سحب", "تم إيداع",
    "تأكيد الطلب", "تحديث الشحن", "رقم التتبع",
    "تم شحن", "إيصال", "فاتورة", "كشف حساب",
    "تم الدفع", "تأكيد الدفع", "عملية ناجحة",
]

ACCOUNT_KEYWORDS = [
    "password reset", "reset your password", "forgot password",
    "account update", "account created", "account activated",
    "login attempt", "new sign-in", "new device", "new login",
    "verify your email", "confirm your email", "email verification",
    "two-factor", "2fa", "mfa", "authenticator",
    "security code", "access code", "account security",
    "profile update", "settings changed", "preferences updated",
    "تحديث الحساب", "تسجيل دخول جديد", "جهاز جديد",
    "إعادة تعيين كلمة المرور", "استعادة كلمة المرور",
    "تفعيل الحساب", "تأكيد البريد", "التحقق من البريد",
    "رمز الأمان", "رمز الوصول", "أمان الحساب",
    "تم تحديث الملف", "تم تغيير الإعدادات",
]

SECURITY_KEYWORDS = [
    "security alert", "security notice", "security warning",
    "suspicious activity", "unusual activity", "unauthorized",
    "breach", "compromised", "hacked", "fraud alert",
    "action required", "immediate action", "urgent action",
    "your account may", "we noticed", "we detected",
    "blocked", "restricted", "suspended", "locked",
    "تنبيه أمني", "تحذير أمني", "إشعار أمني",
    "نشاط مشبوه", "نشاط غير عادي", "غير مصرح به",
    "اختراق", "تم حظر", "تم تعليق", "تم تقييد",
    "إجراء مطلوب", "إجراء فوري", "إجراء عاجل",
]

NEWSLETTER_KEYWORDS = [
    "newsletter", "weekly digest", "daily digest", "monthly digest",
    "weekly update", "daily update", "monthly update",
    "news roundup", "news summary", "this week in",
    "top stories", "headlines", "what's new",
    "edition", "issue #", "issue no",
    "curator", "curated", "editorial",
    "النشرة الإخبارية", "ملخص أسبوعي", "ملخص يومي",
    "تحديث أسبوعي", "تحديث يومي", "أخبار الأسبوع",
    "أهم الأخبار", "عناوين اليوم", "ما الجديد",
]

# NEW: Terms/Policy update keywords
POLICY_KEYWORDS = [
    "terms of use", "terms of service", "privacy policy",
    "policy update", "terms update", "legal update",
    "we've updated", "we have updated", "changes to our",
    "updated our terms", "updated our policy", "updated our privacy",
    "service agreement", "user agreement", "license agreement",
    "effective date", "these changes will take effect",
    "by continuing to use", "data protection", "gdpr",
    "شروط الاستخدام", "سياسة الخصوصية", "تحديث الشروط",
    "تغييرات على", "تم تحديث", "الاتفاقية",
]

# NEW: Welcome/Onboarding keywords
WELCOME_KEYWORDS = [
    "welcome to", "thanks for signing up", "thank you for signing up",
    "thanks for joining", "thank you for joining", "get started",
    "getting started", "welcome aboard", "you're in", "you are in",
    "account is ready", "account has been created",
    "first steps", "next steps", "start using",
    "activate your", "complete your profile", "set up your",
    "explore our", "discover our", "learn how to",
    "مرحبا بك في", "أهلا بك في", "شكرا للتسجيل",
    "شكرا للانضمام", "ابدأ الآن", "حسابك جاهز",
    "الخطوات الأولى", "أكمل ملفك الشخصي",
]

# NEW: CI/CD/DevOps keywords
DEVOPS_KEYWORDS = [
    "build failed", "build succeeded", "build passed", "build completed",
    "deployment failed", "deployment succeeded", "deploy failed",
    "pipeline failed", "pipeline succeeded", "pipeline completed",
    "workflow failed", "workflow succeeded", "workflow completed",
    "pull request", "merge request", "push notification",
    "code review", "repository",
    "github actions", "gitlab ci", "jenkins", "travis ci",
    "circleci", "azure devops", "bitbucket pipelines",
    "railway", "vercel", "netlify", "heroku", "aws codebuild",
    "server alert", "server down", "server error", "uptime",
    "monitoring alert", "health check", "crash report",
    "cpu usage", "memory usage", "disk space",
    "error rate", "latency alert",
]


def is_automated_email(row: dict) -> tuple[bool, str]:
    """
    Check if an inbox message is automated/marketing.
    Returns (is_automated, reason).
    """
    body = (row.get("body") or "").lower()
    sender_contact = (row.get("sender_contact") or "").lower()
    sender_name = (row.get("sender_name") or "").lower()
    subject = (row.get("subject") or "").lower()
    
    full_text = f"{body} {subject} {sender_name}"
    
    # 1. Sender-based filtering
    for pattern in AUTOMATED_SENDER_PATTERNS:
        if re.search(pattern, sender_contact):
            return True, "Sender pattern"
    
    # 2. Service provider patterns
    for pattern in SERVICE_PROVIDER_PATTERNS:
        if re.search(pattern, sender_contact):
            return True, "Service Provider"
    
    # 3. OTP patterns
    for pattern in OTP_PATTERNS:
        if re.search(pattern, full_text):
            return True, "OTP/Verification"
    
    # 4. Marketing keywords
    if any(k in full_text for k in MARKETING_KEYWORDS):
        return True, "Marketing/Ad"
    
    # 5. System/transactional keywords
    if any(k in full_text for k in INFO_KEYWORDS):
        return True, "System/Transactional"
    
    # 6. Account notifications
    if any(k in full_text for k in ACCOUNT_KEYWORDS):
        return True, "Account Notification"
    
    # 7. Security keywords
    if any(k in full_text for k in SECURITY_KEYWORDS):
        return True, "Security Alert"
    
    # 8. Newsletter keywords
    if any(k in full_text for k in NEWSLETTER_KEYWORDS):
        return True, "Newsletter"
    
    # 9. Terms/Policy keywords
    if any(k in full_text for k in POLICY_KEYWORDS):
        return True, "Terms/Policy"
    
    # 10. Welcome/Onboarding keywords
    if any(k in full_text for k in WELCOME_KEYWORDS):
        return True, "Welcome/Onboarding"
    
    # 11. CI/CD/DevOps keywords
    if any(k in full_text for k in DEVOPS_KEYWORDS):
        return True, "CI/CD/DevOps"
    
    return False, ""


def is_automated_customer(customer: dict) -> tuple[bool, str]:
    """
    Check if a customer entry is automated (service provider email).
    Returns (is_automated, reason).
    """
    email = (customer.get("email") or "").lower()
    phone = (customer.get("phone") or "").lower()
    name = (customer.get("name") or "").lower()
    
    contact = email or phone
    
    # Check sender patterns
    for pattern in AUTOMATED_SENDER_PATTERNS:
        if re.search(pattern, contact):
            return True, "Sender pattern"
    
    # Check service provider patterns
    for pattern in SERVICE_PROVIDER_PATTERNS:
        if re.search(pattern, contact):
            return True, "Service Provider"
    
    return False, ""


async def get_all_inbox_messages():
    """Fetch all inbox messages from all users."""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            "SELECT id, license_key_id, sender_contact, sender_name, subject, body, channel FROM inbox_messages ORDER BY license_key_id, id",
            None
        )
        return rows


async def get_all_customers():
    """Fetch all customers from all users."""
    async with get_db() as db:
        rows = await fetch_all(
            db,
            "SELECT id, license_key_id, name, email, phone FROM customers ORDER BY license_key_id, id",
            None
        )
        return rows


async def delete_messages(message_ids: list):
    """Delete messages by ID list."""
    if not message_ids:
        return 0
    
    async with get_db() as db:
        batch_size = 100
        deleted = 0
        
        for i in range(0, len(message_ids), batch_size):
            batch = message_ids[i:i+batch_size]
            placeholders = ", ".join(["?"] * len(batch))
            
            # Delete from customer_messages (FK constraint)
            await execute_sql(
                db,
                f"DELETE FROM customer_messages WHERE inbox_message_id IN ({placeholders})",
                batch
            )
            
            # Delete related outbox messages (FK constraint)
            await execute_sql(
                db,
                f"DELETE FROM outbox_messages WHERE inbox_message_id IN ({placeholders})",
                batch
            )
            
            # Delete inbox messages
            await execute_sql(
                db,
                f"DELETE FROM inbox_messages WHERE id IN ({placeholders})",
                batch
            )
            deleted += len(batch)
        
        await commit_db(db)
        return deleted


async def delete_customers(customer_ids: list):
    """Delete customers by ID list."""
    if not customer_ids:
        return 0
    
    async with get_db() as db:
        batch_size = 100
        deleted = 0
        
        for i in range(0, len(customer_ids), batch_size):
            batch = customer_ids[i:i+batch_size]
            placeholders = ", ".join(["?"] * len(batch))
            
            # Delete from customer_messages first (FK constraint)
            await execute_sql(
                db,
                f"DELETE FROM customer_messages WHERE customer_id IN ({placeholders})",
                batch
            )
            
            # Delete customers
            await execute_sql(
                db,
                f"DELETE FROM customers WHERE id IN ({placeholders})",
                batch
            )
            deleted += len(batch)
        
        await commit_db(db)
        return deleted


async def main(dry_run: bool = True):
    """Main cleanup function."""
    print("=" * 60)
    print("Al-Mudeer - Automated Email & Customer Cleanup")
    print("=" * 60)
    print(f"Database Type: {DB_TYPE}")
    print(f"Mode: {'DRY RUN (preview only)' if dry_run else 'EXECUTE (will delete)'}")
    print("-" * 60)
    
    # ============ INBOX MESSAGES CLEANUP ============
    print("\n📧 INBOX MESSAGES CLEANUP")
    print("-" * 40)
    
    print("Fetching all inbox messages...")
    messages = await get_all_inbox_messages()
    print(f"Total messages in database: {len(messages)}")
    
    to_delete_msgs = []
    by_reason = {}
    by_license = {}
    
    for msg in messages:
        is_auto, reason = is_automated_email(msg)
        if is_auto:
            to_delete_msgs.append(msg)
            by_reason[reason] = by_reason.get(reason, 0) + 1
            license_id = msg.get("license_key_id")
            by_license[license_id] = by_license.get(license_id, 0) + 1
    
    print(f"\n🗑️  Automated emails to delete: {len(to_delete_msgs)}")
    print(f"✅ Legitimate emails to keep: {len(messages) - len(to_delete_msgs)}")
    
    if to_delete_msgs:
        print("\n📊 Breakdown by reason:")
        for reason, count in sorted(by_reason.items(), key=lambda x: -x[1]):
            print(f"   - {reason}: {count}")
        
        print("\n👥 Breakdown by license/user:")
        for license_id, count in sorted(by_license.items(), key=lambda x: -x[1]):
            print(f"   - License {license_id}: {count} emails")
    
    # ============ CUSTOMERS CLEANUP ============
    print("\n\n👤 CUSTOMERS CLEANUP")
    print("-" * 40)
    
    print("Fetching all customers...")
    customers = await get_all_customers()
    print(f"Total customers in database: {len(customers)}")
    
    to_delete_customers = []
    customer_by_reason = {}
    customer_by_license = {}
    
    for customer in customers:
        is_auto, reason = is_automated_customer(customer)
        if is_auto:
            to_delete_customers.append(customer)
            customer_by_reason[reason] = customer_by_reason.get(reason, 0) + 1
            license_id = customer.get("license_key_id")
            customer_by_license[license_id] = customer_by_license.get(license_id, 0) + 1
    
    print(f"\n🗑️  Automated customers to delete: {len(to_delete_customers)}")
    print(f"✅ Legitimate customers to keep: {len(customers) - len(to_delete_customers)}")
    
    if to_delete_customers:
        print("\n📊 Breakdown by reason:")
        for reason, count in sorted(customer_by_reason.items(), key=lambda x: -x[1]):
            print(f"   - {reason}: {count}")
        
        print("\n👤 Sample automated customers (first 10):")
        for i, cust in enumerate(to_delete_customers[:10]):
            contact = cust.get("email") or cust.get("phone") or "Unknown"
            name = cust.get("name") or "No name"
            is_auto, reason = is_automated_customer(cust)
            print(f"   {i+1}. [{reason}] {name} - {contact}")
        
        if len(to_delete_customers) > 10:
            print(f"   ... and {len(to_delete_customers) - 10} more")
    
    # ============ EXECUTE DELETION ============
    if not dry_run and (to_delete_msgs or to_delete_customers):
        print("\n" + "=" * 60)
        confirm = input("⚠️  Are you sure you want to DELETE all automated items? (yes/no): ")
        if confirm.lower() == "yes":
            if to_delete_msgs:
                print("\n🗑️  Deleting automated emails...")
                message_ids = [msg["id"] for msg in to_delete_msgs]
                deleted = await delete_messages(message_ids)
                print(f"✅ Successfully deleted {deleted} automated emails!")
            
            if to_delete_customers:
                print("\n🗑️  Deleting automated customers...")
                customer_ids = [c["id"] for c in to_delete_customers]
                deleted = await delete_customers(customer_ids)
                print(f"✅ Successfully deleted {deleted} automated customers!")
        else:
            print("❌ Operation cancelled.")
    elif dry_run:
        print("\n" + "-" * 60)
        print("ℹ️  This was a DRY RUN. Nothing was deleted.")
        print("    To actually delete, run: python cleanup_automated_emails.py --execute")
    
    print("\n" + "=" * 60)
    print("Cleanup complete!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Cleanup automated emails and customers from Al-Mudeer")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=True,
        help="Preview only, don't delete (default)"
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Actually delete the items"
    )
    
    args = parser.parse_args()
    dry_run = not args.execute
    
    asyncio.run(main(dry_run=dry_run))
