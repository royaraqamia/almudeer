import asyncio
import sys
import os

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))
os.environ["DATABASE_PATH"] = "backend/almudeer.db"

from db_helper import get_db, execute_sql, fetch_all, fetch_one
from models.inbox import save_inbox_message, get_inbox_conversations, get_full_chat_history

async def verify_visibility():
    license_id = 1  # Assuming license 1 exists or use a dummy
    contact = "test_visibility_contact"
    
    print(f"--- Verification Started ---")
    
    # 1. Save a new message
    print(f"1. Saving new message for {contact}...")
    msg_id = await save_inbox_message(
        license_id=license_id,
        channel="whatsapp",
        body="Visibility test message",
        sender_contact=contact,
        sender_name="Test User"
    )
    print(f"Saved message ID: {msg_id}")
    
    # 2. Check conversation list
    print(f"2. Checking conversation list visibility...")
    conversations = await get_inbox_conversations(license_id)
    found_conv = any(c['sender_contact'] == contact for c in conversations)
    
    if found_conv:
        print("✅ SUCCESS: Conversation is visible in the list.")
    else:
        print("❌ FAILURE: Conversation NOT found in the list.")
    
    # 3. Check chat history
    print(f"3. Checking chat history visibility...")
    history = await get_full_chat_history(license_id, contact)
    found_msg = any(m['id'] == msg_id for m in history)
    
    if found_msg:
        print("✅ SUCCESS: Message is visible in chat history.")
    else:
        print("❌ FAILURE: Message NOT found in history.")
        
    print(f"--- Verification Finished ---")

if __name__ == "__main__":
    asyncio.run(verify_visibility())
