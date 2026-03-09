"""
Database migration script to remove auto-reply related columns.
Drops 'auto_reply_enabled' from email_configs, telegram_configs, whatsapp_configs, telegram_phone_sessions.
Drops 'auto_reply_delay_seconds' from user_preferences.
"""

import asyncio
import os
import sys

# Add current directory to path so we can import db_helper
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from db_helper import get_db, execute_sql, commit_db, DB_TYPE

async def migrate():
    print(f"Starting migration for {DB_TYPE} database...")
    
    # Initialize the database pool
    from db_pool import db_pool
    await db_pool.initialize()
    
    async with get_db() as db:
        try:
            # 1. remove columns from email_configs
            print("Removing 'auto_reply_enabled' from email_configs...")
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE email_configs DROP COLUMN IF EXISTS auto_reply_enabled")
            else:
                try:
                    await execute_sql(db, "ALTER TABLE email_configs DROP COLUMN auto_reply_enabled")
                except Exception as e:
                    print(f"Note: Could not drop column from email_configs (might be legacy SQLite): {e}")

            # 2. remove columns from telegram_configs
            print("Removing 'auto_reply_enabled' from telegram_configs...")
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE telegram_configs DROP COLUMN IF EXISTS auto_reply_enabled")
            else:
                try:
                    await execute_sql(db, "ALTER TABLE telegram_configs DROP COLUMN auto_reply_enabled")
                except Exception as e:
                    print(f"Note: Could not drop column from telegram_configs: {e}")

            # 3. remove columns from whatsapp_configs
            print("Removing 'auto_reply_enabled' from whatsapp_configs...")
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE whatsapp_configs DROP COLUMN IF EXISTS auto_reply_enabled")
            else:
                try:
                    await execute_sql(db, "ALTER TABLE whatsapp_configs DROP COLUMN auto_reply_enabled")
                except Exception as e:
                    print(f"Note: Could not drop column from whatsapp_configs: {e}")

            # 4. remove columns from telegram_phone_sessions
            print("Removing 'auto_reply_enabled' from telegram_phone_sessions...")
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE telegram_phone_sessions DROP COLUMN IF EXISTS auto_reply_enabled")
            else:
                try:
                    await execute_sql(db, "ALTER TABLE telegram_phone_sessions DROP COLUMN auto_reply_enabled")
                except Exception as e:
                    print(f"Note: Could not drop column from telegram_phone_sessions: {e}")

            # 5. remove columns from user_preferences
            print("Removing 'auto_reply_delay_seconds' from user_preferences...")
            if DB_TYPE == "postgresql":
                await execute_sql(db, "ALTER TABLE user_preferences DROP COLUMN IF EXISTS auto_reply_delay_seconds")
            else:
                try:
                    await execute_sql(db, "ALTER TABLE user_preferences DROP COLUMN auto_reply_delay_seconds")
                except Exception as e:
                    print(f"Note: Could not drop column from user_preferences: {e}")

            await commit_db(db)
            print("Migration completed successfully.")
            
        except Exception as e:
            print(f"Migration failed: {e}")
            raise e
        finally:
            # Close the pool
            await db_pool.close()

if __name__ == "__main__":
    asyncio.run(migrate())
