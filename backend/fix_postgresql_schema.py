import asyncio
import asyncpg
import os
from dotenv import load_dotenv

async def run_fix():
    load_dotenv()
    db_url = os.getenv("DATABASE_URL")
    print(f"Connecting to {db_url.split('@')[-1]}...")
    
    conn = await asyncpg.connect(db_url)
    try:
        print("\nChecking ALMUDEER channel conversations...")
        almudeer_convs = await conn.fetch("""
            SELECT id, sender_name, sender_contact, channel 
            FROM inbox_conversations 
            WHERE channel = 'almudeer'
            ORDER BY last_message_at DESC
            LIMIT 10
        """)
        
        if not almudeer_convs:
            print("NO almudeer channel conversations found.")
        
        for conv in almudeer_convs:
            print(f"Found conversation: {conv['sender_name']} (contact: {conv['sender_contact']})")
            
            # Check if this contact has a license key with matching username
            license_match = await conn.fetchrow("""
                SELECT id, username, last_seen_at 
                FROM license_keys 
                WHERE username = $1
            """, conv['sender_contact'])
            
            if license_match:
                print(f"  -> Found matching license: ID {license_match['id']}, Username: {license_match['username']}, Last Seen: {license_match['last_seen_at']}")
            else:
                print(f"  -> NO MATCHING LICENSE found for username: {conv['sender_contact']}")
                # Proactively check if there's a user WITH this email
                user_match = await conn.fetchrow("SELECT email, license_key_id FROM users WHERE email = $1", conv['sender_contact'])
                if user_match:
                    print(f"     Found user record: {user_match['email']} linked to license ID {user_match['license_key_id']}")
                    # Check that license
                    actual_license = await conn.fetchrow("SELECT id, username FROM license_keys WHERE id = $1", user_match['license_key_id'])
                    print(f"     Actual license ID {actual_license['id']} has username: '{actual_license['username']}'")
                else:
                    print("     No user record found for this contact.")

        print("\nChecking all licenses with usernames...")
        licenses = await conn.fetch("SELECT id, username, last_seen_at FROM license_keys WHERE username IS NOT NULL")
        for lk in licenses:
            print(f"License {lk['id']}: Username='{lk['username']}', Last Seen={lk['last_seen_at']}")

    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(run_fix())
