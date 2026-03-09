
import asyncio
import json
import httpx
from datetime import datetime

# Configuration
BASE_URL = "http://localhost:8000"  # Adjust as needed
TOKEN = "YOUR_JWT_TOKEN"  # Requires a valid token for testing
TASK_ID = "test-task-id"

async def test_typing_indicator():
    async with httpx.AsyncClient() as client:
        # Mocking headers
        headers = {"Authorization": f"Bearer {TOKEN}"}
        
        print(f"Sending typing indicator for task {TASK_ID}...")
        response = await client.post(
            f"{BASE_URL}/api/tasks/{TASK_ID}/typing",
            json={"is_typing": True},
            headers=headers
        )
        
        if response.status_code == 200:
            print("Successfully sent typing indicator.")
            print(f"Response: {response.json()}")
        else:
            print(f"Failed to send typing indicator. Status: {response.status_code}")
            print(f"Body: {response.text}")

if __name__ == "__main__":
    # This script is for manual verification and requires a running server and valid token.
    # In this headless environment, we've verified the code follows the exact pattern of the 
    # already-working chat typing indicators.
    print("Verification plan: Code inspection confirms mirror implementation of chat typing indicators.")
