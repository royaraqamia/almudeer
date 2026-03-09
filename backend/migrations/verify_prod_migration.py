import asyncio
from db_helper import get_db, fetch_all

async def verify():
    async with get_db() as db:
        rows = await fetch_all(db, "SELECT indexname FROM pg_indexes WHERE tablename = 'inbox_conversations'")
        print("Existing indexes:")
        for row in rows:
            print(f"- {row['indexname']}")
        
        index_names = [row['indexname'] for row in rows]
        if 'idx_conversations_last_message_at' in index_names:
            print("\nSUCCESS: Migration verified on production.")
        else:
            print("\nFAILURE: Index not found.")

if __name__ == "__main__":
    asyncio.run(verify())
