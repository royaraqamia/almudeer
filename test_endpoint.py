import requests
import json
import time

# Test the /shared-with-me endpoint
BASE_URL = "https://almudeer.up.railway.app"

print("=" * 60)
print("Testing /api/library/shared-with-me")
print("=" * 60)
response = requests.get(
    f"{BASE_URL}/api/library/shared-with-me", 
    timeout=10
)
print(f"Status Code: {response.status_code}")
print(f"Response: {json.dumps(response.json(), indent=2)}")
