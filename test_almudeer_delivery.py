"""
Test script to verify Almudeer-to-Almudeer message delivery and status flow.
Run this to debug why double checks aren't showing.
"""
import asyncio
import sys
import os

# Set console encoding to UTF-8 for Windows
os.environ['PYTHONIOENCODING'] = 'utf-8'
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Set PostgreSQL connection
os.environ['DATABASE_URL'] = ''
os.environ['DB_TYPE'] = 'postgresql'

from db_helper import get_db, fetch_one, fetch_all
from database_unified import get_db_pool, close_db_pool
from models.inbox import get_full_chat_history


async def test_almudeer_delivery():
    print("=" * 80)
    print("Testing Almudeer-to-Almudeer Message Delivery Flow")
    print("=" * 80)

    # Initialize database pool
    pool = await get_db_pool()
    await pool.initialize()
    print("OK: Connected to PostgreSQL database")

    try:
        async with get_db() as db:
            # Get first 5 license keys
            licenses = await fetch_all(db, "SELECT id, username, full_name FROM license_keys ORDER BY id ASC LIMIT 5")

            if len(licenses) < 2:
                print("ERROR: Need at least 2 license keys to test")
                return

            print("\nFound {} license keys:".format(len(licenses)))
            for lic in licenses:
                username = lic['username'] or 'None'
                full_name = lic['full_name'] or 'None'
                line = "  - ID={}, Username={}, Name={}".format(lic['id'], username, full_name)
                print(line.encode('utf-8', errors='replace').decode())

            license_a = licenses[0]
            license_b = licenses[1] if len(licenses) > 1 else licenses[0]

            username_a = license_a['username'] or 'None'
            username_b = license_b['username'] or 'None'

            line_a = "\nAccount A: ID={}, Username={}".format(license_a['id'], username_a)
            line_b = "Account B: ID={}, Username={}".format(license_b['id'], username_b)
            print(line_a.encode('utf-8', errors='replace').decode())
            print(line_b.encode('utf-8', errors='replace').decode())

            # Check for messages from A to B
            print("\n--- Checking messages from A to B ---")
            if license_b['username']:
                messages_a_to_b = await get_full_chat_history(license_a['id'], license_b['username'], limit=10)

                if not messages_a_to_b:
                    print("WARNING: No messages found from A to B")
                else:
                    print("OK: Found {} messages".format(len(messages_a_to_b)))
                    for msg in messages_a_to_b:
                        direction = msg.get('direction', 'unknown')
                        status = msg.get('status', 'unknown')
                        delivery_status = msg.get('delivery_status', 'NULL')
                        body = msg.get('body', '')[:50]
                        line = "  - [{}] Status={}, DeliveryStatus={}, Body='{}...'".format(
                            direction, status, delivery_status, body)
                        print(line.encode('utf-8', errors='replace').decode())
            else:
                print("WARNING: Account B has no username")

            # Check for messages from B to A
            print("\n--- Checking messages from B to A ---")
            if license_a['username']:
                messages_b_to_a = await get_full_chat_history(license_b['id'], license_a['username'], limit=10)

                if not messages_b_to_a:
                    print("WARNING: No messages found from B to A")
                else:
                    print("OK: Found {} messages".format(len(messages_b_to_a)))
                    for msg in messages_b_to_a:
                        direction = msg.get('direction', 'unknown')
                        status = msg.get('status', 'unknown')
                        delivery_status = msg.get('delivery_status', 'NULL')
                        body = msg.get('body', '')[:50]
                        line = "  - [{}] Status={}, DeliveryStatus={}, Body='{}...'".format(
                            direction, status, delivery_status, body)
                        print(line.encode('utf-8', errors='replace').decode())
            else:
                print("WARNING: Account A has no username")

            # Check raw outbox data for Account A
            print("\n--- Raw Outbox Data for Account A (ID={}) ---".format(license_a['id']))
            outbox_a = await fetch_all(db, """
                SELECT id, channel, recipient_email, recipient_id, status, delivery_status, created_at 
                FROM outbox_messages 
                WHERE license_key_id = $1 
                ORDER BY created_at DESC 
                LIMIT 10
            """, [license_a['id']])

            if not outbox_a:
                print("WARNING: No outbox messages for Account A")
            else:
                print("OK: Found {} outbox messages:".format(len(outbox_a)))
                for msg in outbox_a:
                    to_addr = msg['recipient_email'] or msg['recipient_id'] or 'None'
                    line = "  - ID={}, Channel={}, To={}, Status={}, DeliveryStatus={}".format(
                        msg['id'], msg['channel'], to_addr, msg['status'], msg['delivery_status'])
                    print(line.encode('utf-8', errors='replace').decode())

            # Check raw outbox data for Account B
            print("\n--- Raw Outbox Data for Account B (ID={}) ---".format(license_b['id']))
            outbox_b = await fetch_all(db, """
                SELECT id, channel, recipient_email, recipient_id, status, delivery_status, created_at 
                FROM outbox_messages 
                WHERE license_key_id = $1 
                ORDER BY created_at DESC 
                LIMIT 10
            """, [license_b['id']])

            if not outbox_b:
                print("WARNING: No outbox messages for Account B")
            else:
                print("OK: Found {} outbox messages:".format(len(outbox_b)))
                for msg in outbox_b:
                    to_addr = msg['recipient_email'] or msg['recipient_id'] or 'None'
                    line = "  - ID={}, Channel={}, To={}, Status={}, DeliveryStatus={}".format(
                        msg['id'], msg['channel'], to_addr, msg['status'], msg['delivery_status'])
                    print(line.encode('utf-8', errors='replace').decode())

            # Check recent Almudeer channel messages across all licenses
            print("\n--- Recent Almudeer Channel Messages (All Licenses) ---")
            almudeer_msgs = await fetch_all(db, """
                SELECT o.id, o.license_key_id, o.recipient_email, o.status, o.delivery_status, o.created_at,
                       l.username as sender_username
                FROM outbox_messages o
                JOIN license_keys l ON o.license_key_id = l.id
                WHERE o.channel = 'almudeer'
                ORDER BY o.created_at DESC
                LIMIT 20
            """)

            if not almudeer_msgs:
                print("WARNING: No Almudeer channel messages found")
            else:
                print("OK: Found {} Almudeer messages:".format(len(almudeer_msgs)))
                for msg in almudeer_msgs:
                    sender_user = msg['sender_username'] or 'None'
                    recipient = msg['recipient_email'] or 'None'
                    line = "  - ID={}, From={}, To={}, Status={}, DeliveryStatus={}".format(
                        msg['id'], sender_user, recipient, msg['status'], msg['delivery_status'])
                    print(line.encode('utf-8', errors='replace').decode())

            print("\n" + "=" * 80)
            print("Test Complete")
            print("=" * 80)
            print("\nExpected behavior:")
            print("- Outgoing messages should have: status='sent', delivery_status='delivered' or 'read'")
            print("- If delivery_status is NULL or 'pending', the broadcast isn't working")
            print("- Check backend logs for 'Almudeer message delivered' messages")

    finally:
        # Cleanup
        await close_db_pool()
        print("\nOK: Database connection closed")


if __name__ == "__main__":
    asyncio.run(test_almudeer_delivery())
