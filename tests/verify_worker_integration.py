
import asyncio
from unittest.mock import MagicMock, AsyncMock, patch
import sys
import os

# Create a mock for the database connection context manager
class MockDBContext:
    async def __aenter__(self):
        return MagicMock()
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass

async def test_worker_notification_trigger():
    print("Starting worker integration verification...")
    
    # Mock modules that workers.py imports
    # We need to mock 'models' and 'db_helper' BEFORE importing workers
    
    with patch("services.notification_service.process_message_notifications", new_callable=AsyncMock) as mock_process_notifications:
        
        # We need to patch all the db and model calls inside workers.py
        with patch("workers.get_db") as mock_get_db, \
             patch("workers.fetch_one", new_callable=AsyncMock) as mock_fetch_one, \
             patch("workers.fetch_all", new_callable=AsyncMock) as mock_fetch_all, \
             patch("workers.execute_sql", new_callable=AsyncMock) as mock_execute_sql, \
             patch("workers.commit_db", new_callable=AsyncMock) as mock_commit_db, \
             patch("workers.get_or_create_customer", new_callable=AsyncMock) as mock_get_customer, \
             patch("workers.MessagePoller._increment_user_rate_limit", new_callable=MagicMock) as mock_rate_limit, \
             patch("workers.MessagePoller._is_duplicate_content", return_value=False), \
             patch("workers.apply_filters", return_value=True):
             
            mock_get_db.return_value = MockDBContext()
            
            # Setup mock data
            # Mock customer with VIP status
            mock_get_customer.return_value = {"id": 123, "is_vip": True}
            
            # Mock fetch_one for sender details check
            # It's called to get sender_name/contact
            mock_fetch_one.return_value = {"sender_name": "Test Sender", "sender_contact": "123456"}
            
            from workers import MessagePoller
            poller = MessagePoller()
            
            # Test Case 1: Notification should trigger (auto_reply=False)
            print("Test 1: Normal message, auto_reply=False")
            await poller._analyze_and_process_message(
                message_id=1, 
                body="Test message", 
                license_id=1, 
                channel="whatsapp", 
                recipient="123456",
                sender_name="Test Sender"
            )
            
            if mock_process_notifications.called:
                print("SUCCESS: Notification triggered for normal message.")
                # Verify is_vip was passed correctly
                args = mock_process_notifications.call_args
                # args[0] is (license_id, notification_data)
                data = args[0][1]
                if data.get("is_vip") is True:
                    print("SUCCESS: is_vip captured correctly.")
                else:
                    print(f"FAILURE: is_vip not captured: {data.get('is_vip')}")
            else:
                print("FAILURE: Notification NOT triggered.")
                
            mock_process_notifications.reset_mock()
            
            # Test Case 2: Auto-reply TRUE with draft response -> Should NOT trigger waiting_for_reply logic if we filtered it
            # But wait, logic says "if not is_auto_replied". 
            # is_auto_replied = bool(auto_reply and data.get("draft_response"))
            
            print("Test 2: Auto-reply enabled and draft exists")
            
            # Mock _auto_reply to avoid error
            poller._auto_reply = AsyncMock()
            
            await poller._analyze_and_process_message(
                message_id=2, 
                body="Test message 2", 
                license_id=1, 
                channel="whatsapp", 
                recipient="123456",
                sender_name="Test Sender"
            )
            
            if not mock_process_notifications.called:
                 print("SUCCESS: Notification NOT triggered for auto-replied message.")
            else:
                 print("FAILURE: Notification triggered unexpectedly for auto-replied message.")

if __name__ == "__main__":
    # We need to add the parent directory to path to import workers
    sys.path.append(os.getcwd())
    asyncio.run(test_worker_notification_trigger())
