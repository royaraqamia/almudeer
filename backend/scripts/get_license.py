
import asyncio
import os
import sys

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from db_pool import db_pool
from db_helper import fetch_one, get_db

async def run():
    await db_pool.initialize()
    async with get_db() as db:
        row = await fetch_one(db, 'SELECT id FROM license_keys LIMIT 1')
        print(row['id'] if row else 'None')
    await db_pool.close()

if __name__ == "__main__":
    asyncio.run(run())
