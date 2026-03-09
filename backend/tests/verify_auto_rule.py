
import asyncio
from unittest.mock import MagicMock, AsyncMock, patch
import sys
import os
import json

# Add project root
sys.path.append(os.getcwd())

async def test_auto_rule_creation():
    print("Starting automatic rule creation verification...")
    
    # We need to test services.notification_service.get_rules
    # We will mock get_db and db interactions
    
    from services import notification_service
    
    # --- Test Case 1: Rule does NOT exist ---
    print("\nTest 1: Rule missing -> Should Auto-Create")
    
    with patch("services.notification_service.get_db") as mock_get_db, \
         patch("services.notification_service.fetch_all", new_callable=AsyncMock) as mock_fetch_all, \
         patch("services.notification_service.execute_sql", new_callable=AsyncMock) as mock_execute_sql, \
         patch("services.notification_service.commit_db", new_callable=AsyncMock) as mock_commit_db:
         
        mock_get_db.return_value.__aenter__.return_value = MagicMock()
        
        # Setup fetch_all side effects
        # 1st call: Empty list (no rules)
        # 2nd call: List with the new rule (simulating DB update)
        mock_fetch_all.side_effect = [
            [], # Initial check
            [ # Re-fetch
                {
                    "id": 1, 
                    "license_key_id": 1, 
                    "name": "تنبيه بانتظار الرد", 
                    "condition_type": "waiting_for_reply", 
                    "channels": json.dumps(["in_app"]),
                    "is_active": 1
                }
            ]
        ]
        
        # Call function
        rules = await notification_service.get_rules(1)
        
        # Verify
        if mock_execute_sql.called:
            print("SUCCESS: execute_sql called (Insert performed).")
            # Check args
            args = mock_execute_sql.call_args
            query = args[0][1]
            if "INSERT INTO notification_rules" in query and "waiting_for_reply" in query:
                print("SUCCESS: Insert query looks correct.")
            else:
                 print(f"FAILURE: Unexpected query: {query}")
        else:
            print("FAILURE: execute_sql NOT called.")
            
        if len(rules) == 1 and rules[0]["condition_type"] == "waiting_for_reply":
             print("SUCCESS: Returned list contains the new rule.")
        else:
             print(f"FAILURE: Returned rules mismatch: {rules}")

    # --- Test Case 2: Rule ALREADY exists ---
    print("\nTest 2: Rule exists -> Should NOT Create")
    
    with patch("services.notification_service.get_db") as mock_get_db, \
         patch("services.notification_service.fetch_all", new_callable=AsyncMock) as mock_fetch_all, \
         patch("services.notification_service.execute_sql", new_callable=AsyncMock) as mock_execute_sql:
         
        mock_get_db.return_value.__aenter__.return_value = MagicMock()
        
        # 1st call: List WITH the rule
        mock_fetch_all.return_value = [
            {
                "id": 10, 
                "license_key_id": 1, 
                "name": "Existing Rule", 
                "condition_type": "waiting_for_reply", 
                "channels": json.dumps(["in_app"]),
                "is_active": 1
            }
        ]
        
        # Call function
        rules = await notification_service.get_rules(1)
        
        # Verify
        if not mock_execute_sql.called:
            print("SUCCESS: execute_sql NOT called.")
        else:
            print("FAILURE: execute_sql WAS called unexpectedly.")
            
        if len(rules) == 1:
             print("SUCCESS: Returned existing rule.")


if __name__ == "__main__":
    asyncio.run(test_auto_rule_creation())
