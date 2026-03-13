"""
Al-Mudeer - Inbox/Outbox Schema Verification Script

This script verifies that all required columns exist in the inbox_messages
and outbox_messages tables. Useful for debugging after schema changes.
"""

import asyncio
import sys
import os
from db_helper import get_db, fetch_all

# Expected columns for inbox_messages
EXPECTED_INBOX_COLUMNS = [
    "id",
    "license_key_id",
    "sender_contact",
    "sender_id",
    "sender_name",
    "channel",
    "subject",
    "body",
    "attachments",
    "intent",
    "urgency",
    "sentiment",
    "language",
    "dialect",
    "ai_summary",
    "ai_draft_response",
    "status",
    "created_at",
    "received_at",
    "reply_to_id",
    "reply_to_platform_id",
    "reply_to_body_preview",
    "reply_to_sender_name",
    "reply_count",
    "is_forwarded",
    "sender_username",
    "channel_message_id",
    "platform_message_id",
    "direction",
    "edited_at",
    "edit_count",
    "deleted_at",
    "is_pinned",
    "pinned_at",
    "archived_at",
    "delivery_status",
    "sent_at",
    "retry_count",
    "max_retries",
    "last_retry_at",
    "failed_at",
    "voice_note_url",
    "voice_note_duration",
    "is_voice_note",
    "forwarded_from_license_id",
    # Additional columns from previous migrations
    "processed_at",
    "audio_url",
    "audio_duration",
    "audio_transcript",
    "forwarded_from",
    "is_read",
    "search_vector",
    "platform_status",
    "original_sender",
    "forwarded_message_id",
]

# Expected columns for outbox_messages
EXPECTED_OUTBOX_COLUMNS = [
    "id",
    "license_key_id",
    "inbox_message_id",
    "channel",
    "recipient_id",
    "subject",
    "body",
    "attachments",
    "status",
    "created_at",
    "approved_at",
    "sent_at",
    "failed_at",
    "failure_reason",
    "reply_to_platform_id",
    "reply_to_body_preview",
    "reply_to_id",
    "reply_to_sender_name",
    "reply_count",
    "is_forwarded",
    "channel_message_id",
    "platform_message_id",
    "delivery_status",
    "edited_at",
    "edit_count",
    "deleted_at",
    "retry_count",
    "max_retries",
    "last_retry_at",
    "voice_note_url",
    "voice_note_duration",
    "is_voice_note",
    # Additional columns from previous migrations
    "recipient_email",
    "error_message",
    "delivered_at",
    "read_at",
    "search_vector",
    "original_sender",
    "original_body",
    "next_retry_at",
    "retry_error",
    "edited_by",
]


async def verify_schema():
    """Verify inbox and outbox schema."""
    print("=" * 80)
    print("Al-Mudeer - Inbox/Outbox Schema Verification")
    print("=" * 80)
    
    # Detect database type
    import os
    db_type = os.environ.get("DB_TYPE", "sqlite")
    is_postgresql = db_type.lower() == "postgresql"
    
    async with get_db() as db:
        # Get actual columns for inbox_messages
        print(f"\n📥 Checking inbox_messages table (DB: {db_type})...")
        
        if is_postgresql:
            inbox_result = await fetch_all(
                db,
                """
                SELECT column_name, data_type, is_nullable
                FROM information_schema.columns
                WHERE table_name = 'inbox_messages'
                ORDER BY ordinal_position
                """
            )
        else:
            # SQLite uses PRAGMA table_info
            inbox_result_raw = await fetch_all(
                db,
                "PRAGMA table_info(inbox_messages)"
            )
            # SQLite returns: cid, name, type, notnull, dflt_value, pk
            inbox_result = [
                {"column_name": row["name"], "data_type": row["type"], "is_nullable": "YES" if not row["notnull"] else "NO"}
                for row in inbox_result_raw
            ]
        
        actual_inbox_columns = [row["column_name"] for row in inbox_result]
        
        # Get actual columns for outbox_messages
        print("📤 Checking outbox_messages table...")
        
        if is_postgresql:
            outbox_result = await fetch_all(
                db,
                """
                SELECT column_name, data_type, is_nullable
                FROM information_schema.columns
                WHERE table_name = 'outbox_messages'
                ORDER BY ordinal_position
                """
            )
        else:
            outbox_result_raw = await fetch_all(
                db,
                "PRAGMA table_info(outbox_messages)"
            )
            outbox_result = [
                {"column_name": row["name"], "data_type": row["type"], "is_nullable": "YES" if not row["notnull"] else "NO"}
                for row in outbox_result_raw
            ]
        
        actual_outbox_columns = [row["column_name"] for row in outbox_result]
        
        # Check for missing columns in inbox
        print("\n" + "=" * 80)
        print("📥 inbox_messages Analysis")
        print("=" * 80)
        
        missing_inbox = []
        for col in EXPECTED_INBOX_COLUMNS:
            if col not in actual_inbox_columns:
                missing_inbox.append(col)
                print(f"❌ MISSING: {col}")
            else:
                print(f"✅ OK: {col}")
        
        extra_inbox = [col for col in actual_inbox_columns if col not in EXPECTED_INBOX_COLUMNS]
        if extra_inbox:
            print(f"\n⚠️  EXTRA columns (not in expected list): {extra_inbox}")
        
        # Check for missing columns in outbox
        print("\n" + "=" * 80)
        print("📤 outbox_messages Analysis")
        print("=" * 80)
        
        missing_outbox = []
        for col in EXPECTED_OUTBOX_COLUMNS:
            if col not in actual_outbox_columns:
                missing_outbox.append(col)
                print(f"❌ MISSING: {col}")
            else:
                print(f"✅ OK: {col}")
        
        extra_outbox = [col for col in actual_outbox_columns if col not in EXPECTED_OUTBOX_COLUMNS]
        if extra_outbox:
            print(f"\n⚠️  EXTRA columns (not in expected list): {extra_outbox}")
        
        # Summary
        print("\n" + "=" * 80)
        print("📊 Summary")
        print("=" * 80)
        print(f"inbox_messages: {len(actual_inbox_columns)} columns")
        print(f"  - Missing: {len(missing_inbox)}")
        print(f"  - Extra: {len(extra_inbox)}")
        print(f"\noutbox_messages: {len(actual_outbox_columns)} columns")
        print(f"  - Missing: {len(missing_outbox)}")
        print(f"  - Extra: {len(extra_outbox)}")
        
        if missing_inbox or missing_outbox:
            print("\n⚠️  SCHEMA INCOMPLETE - Missing columns detected!")
            print("\n💡 To add missing columns, run:")
            
            if missing_inbox:
                print(f"\n-- inbox_messages missing columns:")
                for col in missing_inbox:
                    print(f"-- ALTER TABLE inbox_messages ADD COLUMN {col} ...;")
            
            if missing_outbox:
                print(f"\n-- outbox_messages missing columns:")
                for col in missing_outbox:
                    print(f"-- ALTER TABLE outbox_messages ADD COLUMN {col} ...;")
            
            return False
        else:
            print("\n✅ SCHEMA COMPLETE - All expected columns present!")
            return True


async def verify_sample_data():
    """Verify sample data in inbox/outbox tables."""
    print("\n" + "=" * 80)
    print("🔍 Sample Data Verification")
    print("=" * 80)
    
    async with get_db() as db:
        # Check recent inbox messages
        print("\n📥 Recent inbox_messages:")
        inbox_samples = await fetch_all(
            db,
            """
            SELECT id, license_key_id, sender_contact, channel, body, status, direction, created_at
            FROM inbox_messages
            ORDER BY created_at DESC
            LIMIT 3
            """
        )
        if inbox_samples:
            for row in inbox_samples:
                print(f"  ID={row['id']}, License={row['license_key_id']}, "
                      f"Contact={row['sender_contact']}, Channel={row['channel']}, "
                      f"Status={row['status']}, Direction={row['direction']}")
        else:
            print("  (No inbox messages found)")
        
        # Check recent outbox messages
        print("\n📤 Recent outbox_messages:")
        outbox_samples = await fetch_all(
            db,
            """
            SELECT id, license_key_id, recipient_id, channel, body, status, created_at
            FROM outbox_messages
            ORDER BY created_at DESC
            LIMIT 3
            """
        )
        if outbox_samples:
            for row in outbox_samples:
                print(f"  ID={row['id']}, License={row['license_key_id']}, "
                      f"Recipient={row['recipient_id']}, Channel={row['channel']}, "
                      f"Status={row['status']}")
        else:
            print("  (No outbox messages found)")


async def main():
    """Main entry point."""
    try:
        # Initialize database pool
        from db_pool import db_pool
        import os
        
        # Set environment variables before creating pool
        os.environ["DB_TYPE"] = "postgresql"
        
        # Initialize the global pool
        await db_pool.initialize()
        
        schema_ok = await verify_schema()
        await verify_sample_data()
        
        # Close pool
        await db_pool.close()
        
        if not schema_ok:
            print("\n⚠️  Schema verification FAILED")
            sys.exit(1)
        else:
            print("\n✅ Schema verification PASSED")
            sys.exit(0)
            
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    # Force PostgreSQL for production
    os.environ["DB_TYPE"] = "postgresql"
    
    # Check if DATABASE_URL is set
    if not os.environ.get("DATABASE_URL"):
        print("⚠️  DATABASE_URL not set. Please set it:")
        print("   set DATABASE_URL=postgresql://user:pass@host:port/database")
        print("   python verify_inbox_outbox_schema.py")
        sys.exit(1)
    
    print(f"🔌 Connecting to: {os.environ['DATABASE_URL'][:50]}...")
    asyncio.run(main())
