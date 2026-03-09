import asyncio
import os
import sys
from datetime import datetime

# Add parent dir to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from db_helper import get_db, execute_sql, commit_db, DB_TYPE
from models.inbox import save_inbox_message, search_messages
from migrations.fts_setup import setup_full_text_search

async def test_search():
    print(f"Testing Search with DB_TYPE={DB_TYPE}")
    
    # 1. Setup FTS
    await setup_full_text_search()
    
    # 2. Insert Test Data
    license_id = 99999
    async with get_db() as db:
        # Clear old test data
        await execute_sql(db, "DELETE FROM inbox_messages WHERE license_key_id = ?", [license_id])
        await commit_db(db)

    print("Inserting test messages...")
    msg1 = await save_inbox_message(license_id, "whatsapp", "Hello world, this is a test message about python.", "Test Sender", "test@test.com")
    msg2 = await save_inbox_message(license_id, "whatsapp", "Another message about AI and coding.", "Test Sender", "test@test.com")
    msg3 = await save_inbox_message(license_id, "whatsapp", "Just a random chat.", "Test Sender", "test@test.com")
    
    # 3. Search
    print("Searching for 'python'...")
    res1 = await search_messages(license_id, "python")
    print(f"Result count: {res1['total']}")
    if res1['total'] > 0:
        print(f"First match: {res1['messages'][0]['body']}")
        
    print("Searching for 'AI'...")
    res2 = await search_messages(license_id, "AI")
    print(f"Result count: {res2['total']}")
    if res2['total'] > 0:
        print(f"First match: {res2['messages'][0]['body']}")

    print("Searching for 'banana' (should be 0)...")
    res3 = await search_messages(license_id, "banana")
    print(f"Result count: {res3['total']}")

if __name__ == "__main__":
    asyncio.run(test_search())
