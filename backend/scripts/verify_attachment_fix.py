
import asyncio
import os
import sys
import json
from datetime import datetime

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

from db_pool import db_pool
from models.inbox import save_inbox_message, get_inbox_conversations, upsert_conversation_state
from db_helper import execute_sql, get_db, commit_db, DB_TYPE

async def main():
    print("Initialize DB Pool...")
    await db_pool.initialize()

    license_id = 999
    sender_contact = "test_attachment_fix"
    
    # 1. Insert a message with attachment and no body
    print(f"Saving test message for {sender_contact}...")
    attachments = [
        {
            "type": "image",
            "mime_type": "image/jpeg",
            "url": "/static/uploads/test.jpg",
            "filename": "test.jpg"
        }
    ]
    
    msg_id = await save_inbox_message(
        license_id=license_id,
        channel="whatsapp",
        body="",
        sender_name="Test User",
        sender_contact=sender_contact,
        attachments=attachments
    )
    print(f"Message saved with ID: {msg_id}")

    # 2. Force upsert conversation state
    print("Upserting conversation state...")
    await upsert_conversation_state(license_id, sender_contact, "Test User", "whatsapp")

    # 3. Verify get_inbox_conversations returns attachments
    print("Verifying get_inbox_conversations...")
    conversations = await get_inbox_conversations(license_id)
    
    test_conv = next((c for c in conversations if c["sender_contact"] == sender_contact), None)
    
    if not test_conv:
        print("FAILURE: Conversation not found in inbox list.")
    else:
        print(f"SUCCESS: Found conversation.")
        print(f"Body: '{test_conv.get('body')}'")
        print(f"Attachments: {test_conv.get('attachments')}")
        
        if test_conv.get('body') == "صورة" and test_conv.get('attachments'):
            print("VERIFIED: Both backend body fallback AND attachment metadata are working!")
        elif test_conv.get('attachments'):
            print("VERIFIED: Attachment metadata is present.")
        else:
            print("FAILURE: Missing expected data.")

    # Cleanup
    async with get_db() as db:
        await execute_sql(db, "DELETE FROM inbox_messages WHERE sender_contact = ?", [sender_contact])
        await execute_sql(db, "DELETE FROM inbox_conversations WHERE sender_contact = ?", [sender_contact])
        await commit_db(db)
        print("Cleanup complete.")

    await db_pool.close()

if __name__ == "__main__":
    asyncio.run(main())
