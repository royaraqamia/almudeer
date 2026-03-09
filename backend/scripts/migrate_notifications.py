import asyncio
import os
import sys

# Add the parent directory to sys.path to import db_helper
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Set the DATABASE_URL directly for this script
os.environ["DATABASE_URL"] = ""
os.environ["DB_TYPE"] = "postgresql"

from db_helper import get_db, execute_sql, commit_db, DB_TYPE
from db_pool import db_pool

async def migrate():
    # Initialize database pool
    await db_pool.initialize()
    
    print(f"Starting migration for {DB_TYPE}...")
    async with get_db() as db:
        sql = "UPDATE user_preferences SET notifications_enabled = true"
        
        print(f"Executing: {sql}")
        await execute_sql(db, sql)
        await commit_db(db)
        print("Migration completed successfully!")
    
    # Close database pool
    await db_pool.close()

if __name__ == "__main__":
    asyncio.run(migrate())
