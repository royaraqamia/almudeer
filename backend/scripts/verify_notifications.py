import asyncio
import os
import sys
from dotenv import load_dotenv

# Add the parent directory to sys.path to import db_helper
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Set the DATABASE_URL directly for this script
os.environ["DATABASE_URL"] = ""
os.environ["DB_TYPE"] = "postgresql"

from models.preferences import get_preferences, update_preferences
from db_pool import db_pool
from db_helper import get_db, fetch_one, fetch_all, DB_TYPE

async def verify():
    # Initialize database pool
    await db_pool.initialize()
    
    print(f"Starting verification for {DB_TYPE}...")
    
    # 1. Verify ALL records in DB have notifications_enabled = True
    async with get_db() as db:
        print("Checking if any record has notifications_enabled = False...")
        row = await fetch_one(db, "SELECT count(*) as total FROM user_preferences WHERE notifications_enabled = false")
        count = row.get('total')
        print(f"Records with notifications disabled: {count}")
        assert count == 0, f"Error: found {count} records with notifications disabled!"

        # Get a sample license_id to test logic
        sample = await fetch_one(db, "SELECT license_key_id FROM user_preferences LIMIT 1")
        if sample:
            license_id = sample['license_key_id']
            print(f"Testing enforcement for license_id: {license_id}")
            
            # 2. Test GET enforcement (hardcoded in preferences.py)
            prefs = await get_preferences(license_id)
            print(f"GET notifications_enabled: {prefs.get('notifications_enabled')}")
            assert prefs.get('notifications_enabled') is True
            
            # 3. Test UPDATE enforcement (overridden in preferences.py)
            print("Attempting to UPDATE notifications_enabled to False...")
            await update_preferences(license_id, notifications_enabled=False)
            
            # Check DB again
            row = await fetch_one(db, "SELECT notifications_enabled FROM user_preferences WHERE license_key_id = ?", [license_id])
            print(f"DB value after update attempt: {row['notifications_enabled']}")
            assert row['notifications_enabled'] is True
            
            print("Verification of 'Always Enabled' policy successful!")
        else:
            print("Warning: No records found in user_preferences to test enforcement.")

    # Close database pool
    await db_pool.close()

if __name__ == "__main__":
    asyncio.run(verify())
