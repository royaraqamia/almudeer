import sqlite3
import os

# Create a temporary test database
DB_PATH = "test_delivery_hardening.db"
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Setup tables
cursor.execute("""
CREATE TABLE inbox_messages (
    id INTEGER PRIMARY KEY,
    sender_name TEXT,
    body TEXT,
    sender_contact TEXT,
    sender_id TEXT,
    license_key_id INTEGER
)
""")

cursor.execute("""
CREATE TABLE outbox_messages (
    id INTEGER PRIMARY KEY,
    license_key_id INTEGER,
    inbox_message_id INTEGER,
    channel TEXT,
    body TEXT,
    recipient_id TEXT,
    recipient_email TEXT,
    status TEXT
)
""")

# Insert Mock Data
# 1. Fresh Message (initiated from mobile)
cursor.execute("""
INSERT INTO outbox_messages (id, license_key_id, inbox_message_id, channel, body, recipient_id, recipient_email, status)
VALUES (101, 1, NULL, 'whatsapp', 'Hello from mobile!', NULL, '+123456789', 'approved')
""")

# 2. Reply (initiated from mobile)
cursor.execute("""
INSERT INTO inbox_messages (id, sender_name, body, sender_contact, sender_id, license_key_id)
VALUES (501, 'Test User', 'Incoming msg', '+123456789', '555', 1)
""")
cursor.execute("""
INSERT INTO outbox_messages (id, license_key_id, inbox_message_id, channel, body, recipient_id, recipient_email, status)
VALUES (102, 1, 501, 'whatsapp', 'Reply from mobile!', '555', '+123456789', 'approved')
""")

conn.commit()

print("--- Testing Hardened Outbox Retrieval Logic ---")

def test_retrieval(outbox_id, license_id):
    cursor.execute("""
        SELECT o.*, i.sender_name, i.body as original_message, i.sender_contact, i.sender_id
        FROM outbox_messages o
        LEFT JOIN inbox_messages i ON o.inbox_message_id = i.id
        WHERE o.id = ? AND o.license_key_id = ?
    """, [outbox_id, license_id])
    
    rows = cursor.fetchall()
    if not rows:
        print(f"FAILED: Outbox {outbox_id} not found.")
        return None
    
    # Simulate dict row
    row = dict(zip([d[0] for d in cursor.description], rows[0]))
    return row

# Test Case 1: Fresh Message
print("\n[Case 1] Fresh Message (NULL inbox_message_id)")
row1 = test_retrieval(101, 1)
if row1:
    print(f"Success: Retrieved row for {row1['id']}")
    recipient = row1['recipient_id'] or row1['recipient_email'] or row1['sender_id']
    print(f"Resolved Recipient: {recipient} (Expected: +123456789)")
    if recipient == '+123456789':
        print("RESULT: PASS")
    else:
        print("RESULT: FAIL")

# Test Case 2: Reply
print("\n[Case 2] Reply (Linked inbox_message_id)")
row2 = test_retrieval(102, 1)
if row2:
    print(f"Success: Retrieved row for {row2['id']}")
    recipient = row2['recipient_id'] or row2['recipient_email'] or row2['sender_id']
    print(f"Resolved Recipient: {recipient} (Expected: 555)")
    if recipient == '555':
        print("RESULT: PASS")
    else:
        print("RESULT: FAIL")

conn.close()
os.remove(DB_PATH)
