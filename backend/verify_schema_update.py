import asyncio
from models.base import init_enhanced_tables
from db_helper import get_db, execute_sql, fetch_one

async def verify_schema():
    print("Initializing tables to trigger migration...")
    await init_enhanced_tables()
    
    print("Verifying schema...")
    async with get_db() as db:
        try:
            # Check inbox_messages
            await execute_sql(db, "SELECT is_forwarded FROM inbox_messages LIMIT 1")
            print("SUCCESS: inbox_messages has is_forwarded column")
        except Exception as e:
            print(f"FAILURE: inbox_messages missing is_forwarded: {e}")

        try:
            # Check outbox_messages
            await execute_sql(db, "SELECT is_forwarded FROM outbox_messages LIMIT 1")
            print("SUCCESS: outbox_messages has is_forwarded column")
        except Exception as e:
            print(f"FAILURE: outbox_messages missing is_forwarded: {e}")

if __name__ == "__main__":
    asyncio.run(verify_schema())
