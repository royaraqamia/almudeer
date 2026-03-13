"""
Al-Mudeer - Mobile App InboxMessage Field Verification

This script compares the backend database schema with the mobile app's
InboxMessage model to ensure all fields are consistent.
"""

import asyncio
import os
import re
from db_pool import db_pool
from db_helper import get_db, fetch_all


# Mobile app InboxMessage fields (from inbox_message.dart)
MOBILE_INBOX_FIELDS = [
    "id",
    "channel",
    "channelMessageId",
    "senderId",
    "senderName",
    "senderContact",
    "subject",
    "body",
    "receivedAt",
    "status",
    "createdAt",
    "direction",
    "timestamp",
    "deliveryStatus",
    "attachments",
    "platformMessageId",
    "platformStatus",
    "originalSender",
    "replyToId",
    "replyToPlatformId",
    "replyToBody",
    "replyToBodyPreview",
    "replyToSenderName",
    "replyToAttachments",
    "isForwarded",
    "editedAt",
    "isEdited",
    "isDeleted",
    "editCount",
    "threadId",
    "replyCount",
    "sendStatus",  # Mobile-only (optimistic UI)
    "outboxId",  # Mobile-only (optimistic UI)
    "isUploading",  # Mobile-only (optimistic UI)
    "uploadProgress",  # Mobile-only (optimistic UI)
    "uploadedBytes",  # Mobile-only (optimistic UI)
    "totalUploadBytes",  # Mobile-only (optimistic UI)
    "urgency",
    "sentiment",
    "isRead",
    "deletedAt",
    # Voice message fields
    "voiceNoteUrl",
    "voiceNoteDuration",
    "isVoiceNote",
    # Audio message fields
    "audioUrl",
    "audioDuration",
    "audioTranscript",
    # Message forwarding
    "forwardedFrom",
    "forwardedFromLicenseId",
    "forwardedMessageId",
    # Message pinning
    "isPinned",
    "pinnedAt",
    "archivedAt",
    # Message retry tracking
    "retryCount",
    "maxRetries",
    "lastRetryAt",
    "failedAt",
    "sentAt",
    # AI processing fields
    "aiSummary",
    "aiDraftResponse",
    "intent",
    "language",
    "dialect",
    "processedAt",
    # Sender info
    "senderUsername",
    # License key
    "licenseKeyId",
]

# Mobile app OutboxMessage fields (if exists)
MOBILE_OUTBOX_FIELDS = [
    # Add if mobile has separate outbox model
]


def snake_to_camel(snake):
    """Convert snake_case to camelCase."""
    parts = snake.split('_')
    return parts[0] + ''.join(word.capitalize() for word in parts[1:])


def camel_to_snake(camel):
    """Convert camelCase to snake_case."""
    result = []
    for i, char in enumerate(camel):
        if char.isupper() and i > 0:
            result.append('_')
        result.append(char.lower())
    return ''.join(result)


async def verify_mobile_backend_consistency():
    """Verify mobile app fields match backend database schema."""
    print("=" * 80)
    print("Al-Mudeer - Mobile/Backend Schema Consistency Check")
    print("=" * 80)
    
    # Get backend database columns
    print("\n📥 Fetching backend inbox_messages schema...")
    inbox_result = await fetch_all(
        db,
        """
        SELECT column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_name = 'inbox_messages'
        ORDER BY ordinal_position
        """
    )
    backend_inbox_columns = {row["column_name"]: row for row in inbox_result}
    
    print(f"📊 Backend inbox_messages: {len(backend_inbox_columns)} columns")
    print(f"📱 Mobile InboxMessage: {len(MOBILE_INBOX_FIELDS)} fields")
    
    # Check for mismatches
    print("\n" + "=" * 80)
    print("🔍 Field Consistency Analysis")
    print("=" * 80)
    
    # Convert mobile camelCase to backend snake_case for comparison
    mobile_to_backend = {}
    for mobile_field in MOBILE_INBOX_FIELDS:
        snake = camel_to_snake(mobile_field)
        mobile_to_backend[mobile_field] = snake
    
    # Check mobile fields that don't exist in backend
    print("\n📱 Mobile-only fields (not in backend - OK for optimistic UI):")
    mobile_only = []
    for mobile_field, backend_field in mobile_to_backend.items():
        if backend_field not in backend_inbox_columns:
            mobile_only.append(mobile_field)
            print(f"  ✅ {mobile_field} ({backend_field}) - Mobile-only")
    
    # Check backend fields that don't exist in mobile
    print("\n📥 Backend-only fields (not in mobile - may need to be added):")
    backend_only = []
    backend_snake_fields = set(backend_inbox_columns.keys())
    mobile_snake_fields = set(mobile_to_backend.values())
    
    for backend_field in sorted(backend_snake_fields):
        if backend_field not in mobile_snake_fields:
            backend_only.append(backend_field)
            col_info = backend_inbox_columns[backend_field]
            print(f"  ⚠️  {backend_field} ({col_info['data_type']}) - Not in mobile")
    
    # Check type mismatches
    print("\n🔍 Type Consistency Check:")
    type_issues = []
    for mobile_field, backend_field in mobile_to_backend.items():
        if backend_field in backend_inbox_columns:
            backend_type = backend_inbox_columns[backend_field]["data_type"]
            # Check for obvious type mismatches
            if mobile_field in ("id", "replyToId", "replyCount") and "int" not in backend_type and backend_type not in ("integer", "bigint"):
                type_issues.append(f"{mobile_field}: mobile=int, backend={backend_type}")
            if mobile_field in ("isForwarded", "isEdited", "isDeleted", "isRead", "isUploading") and "bool" in backend_type.lower() or backend_type == "boolean":
                # Mobile uses bool, backend uses boolean - OK
                pass
    
    if type_issues:
        print("  ⚠️  Potential type mismatches:")
        for issue in type_issues:
            print(f"    - {issue}")
    else:
        print("  ✅ No obvious type mismatches")
    
    # Summary
    print("\n" + "=" * 80)
    print("📊 Summary")
    print("=" * 80)
    print(f"Mobile-only fields: {len(mobile_only)} (OK for optimistic UI)")
    print(f"Backend-only fields: {len(backend_only)} (may need mobile updates)")
    print(f"Type mismatches: {len(type_issues)}")
    
    if backend_only:
        print("\n⚠️  RECOMMENDATION: Review backend-only fields and add to mobile if needed")
        print("\nFields to consider adding to mobile InboxMessage:")
        for field in backend_only:
            if not field.startswith("search_") and field not in ("processed_at",):  # Skip internal fields
                print(f"  - {field}")
    
    return len(backend_only) == 0 or all(f.startswith("search_") or f in ("processed_at",) for f in backend_only)


async def main():
    """Main entry point."""
    try:
        # Initialize database
        os.environ["DB_TYPE"] = "postgresql"
        await db_pool.initialize()
        
        # Get database connection
        global db
        async with get_db() as db:
            ok = await verify_mobile_backend_consistency()
        
        # Close pool
        await db_pool.close()
        
        if ok:
            print("\n✅ Schema consistency check PASSED")
            return 0
        else:
            print("\n⚠️  Schema consistency check completed with warnings")
            return 1
            
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(asyncio.run(main()))
