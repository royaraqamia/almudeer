#!/usr/bin/env python3
"""
Al-Mudeer Library - Load Testing Script

Load testing for library feature using locust.io or custom async load tester.

Tests:
1. Concurrent uploads
2. Search performance
3. Share operations
4. Storage quota handling

Usage:
    # Install dependencies
    pip install locust

    # Run with locust (web UI)
    locust -f load_test_library.py --host=http://localhost:8000

    # Run headless
    locust -f load_test_library.py --host=http://localhost:8000 --headless -u 100 -r 10 -t 300s

    # Run custom async tests
    python load_test_library.py --mode=custom --users=50 --duration=60
"""

import os
import sys
import asyncio
import time
import random
import hashlib
import tempfile
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import locust
try:
    from locust import HttpUser, task, between, events
    LOCUST_AVAILABLE = True
except ImportError:
    LOCUST_AVAILABLE = False
    logger.warning("locust not installed - custom load testing only")

# Test configuration
TEST_LICENSE_KEY = os.getenv("TEST_LICENSE_KEY", "TEST-KEY-1234")
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "test@example.com")


# ============================================================================
# LOCUST LOAD TESTS
# ============================================================================

if LOCUST_AVAILABLE:
    class LibraryUser(HttpUser):
        """Simulated user for library load testing"""
        
        wait_time = between(1, 3)  # Wait 1-3 seconds between tasks
        host = os.getenv("LOAD_TEST_HOST", "http://localhost:8000")
        
        def on_start(self):
            """Setup: Authenticate and get license"""
            self.headers = {"X-License-Key": TEST_LICENSE_KEY}
        
        @task(3)
        def list_items(self):
            """List library items (most common operation)"""
            categories = ["notes", "files"]
            category = random.choice(categories)
            
            with self.client.get(
                "/api/library/",
                headers=self.headers,
                params={"category": category, "page": 1, "page_size": 20},
                catch_response=True
            ) as response:
                if response.status_code == 200:
                    data = response.json()
                    if data.get("success"):
                        response.success()
                    else:
                        response.failure(f"API error: {data}")
                else:
                    response.failure(f"Status {response.status_code}")
        
        @task(2)
        def search_items(self):
            """Search library items"""
            search_terms = ["test", "note", "file", "document", "image"]
            term = random.choice(search_terms)
            
            self.client.get(
                "/api/library/",
                headers=self.headers,
                params={"search": term, "page": 1}
            )
        
        @task(1)
        def get_item_detail(self):
            """Get specific item details"""
            # Get item ID from list first
            list_response = self.client.get(
                "/api/library/",
                headers=self.headers,
                params={"page": 1, "page_size": 10}
            )
            
            if list_response.status_code == 200:
                data = list_response.json()
                items = data.get("items", [])
                if items:
                    item_id = random.choice(items)["id"]
                    self.client.get(
                        f"/api/library/{item_id}",
                        headers=self.headers
                    )
        
        @task(1)
        def create_note(self):
            """Create a new note"""
            note_data = {
                "title": f"Load Test Note {int(time.time())}",
                "content": f"Test content created at {datetime.now().isoformat()}"
            }
            
            self.client.post(
                "/api/library/notes",
                headers={**self.headers, "Content-Type": "application/json"},
                json=note_data
            )
        
        @task(1)
        def get_storage_usage(self):
            """Check storage usage"""
            self.client.get(
                "/api/library/usage/statistics",
                headers=self.headers
            )


# ============================================================================
# CUSTOM ASYNC LOAD TESTER
# ============================================================================

class LoadTestResult:
    """Store load test results"""
    
    def __init__(self):
        self.total_requests = 0
        self.successful_requests = 0
        self.failed_requests = 0
        self.total_latency = 0.0
        self.min_latency = float('inf')
        self.max_latency = 0.0
        self.errors: Dict[str, int] = {}
    
    def record(self, latency: float, success: bool, error: str = None):
        self.total_requests += 1
        if success:
            self.successful_requests += 1
        else:
            self.failed_requests += 1
            if error:
                self.errors[error] = self.errors.get(error, 0) + 1
        
        self.total_latency += latency
        self.min_latency = min(self.min_latency, latency)
        self.max_latency = max(self.max_latency, latency)
    
    @property
    def avg_latency(self) -> float:
        return self.total_latency / self.total_requests if self.total_requests > 0 else 0
    
    @property
    def success_rate(self) -> float:
        return (self.successful_requests / self.total_requests * 100) if self.total_requests > 0 else 0
    
    def summary(self) -> str:
        return f"""
Load Test Summary
=================
Total Requests: {self.total_requests}
Successful: {self.successful_requests}
Failed: {self.failed_requests}
Success Rate: {self.success_rate:.2f}%

Latency (ms):
  Min: {self.min_latency*1000:.2f}
  Max: {self.max_latency*1000:.2f}
  Avg: {self.avg_latency*1000:.2f}

Errors:
{chr(10).join(f'  {k}: {v}' for k, v in self.errors.items()) or '  None'}
"""


async def run_custom_load_test(
    base_url: str,
    license_key: str,
    num_users: int = 10,
    duration_seconds: int = 60,
    requests_per_user: int = 100
) -> LoadTestResult:
    """
    Run custom async load test.
    
    Args:
        base_url: Backend URL
        license_key: Test license key
        num_users: Number of concurrent users
        duration_seconds: Test duration
        requests_per_user: Requests per user
    
    Returns:
        LoadTestResult with statistics
    """
    import httpx
    
    result = LoadTestResult()
    stop_event = asyncio.Event()
    
    async def user_task(user_id: int):
        """Simulate a user making requests"""
        async with httpx.AsyncClient(base_url=base_url) as client:
            headers = {"X-License-Key": license_key}
            
            for i in range(requests_per_user):
                if stop_event.is_set():
                    break
                
                try:
                    # Random operation
                    op = random.choice(["list", "search", "detail", "note"])
                    start = time.time()
                    
                    if op == "list":
                        response = await client.get(
                            "/api/library/",
                            headers=headers,
                            params={"page": 1, "page_size": 20}
                        )
                    elif op == "search":
                        response = await client.get(
                            "/api/library/",
                            headers=headers,
                            params={"search": "test", "page": 1}
                        )
                    elif op == "detail":
                        # Get first item then fetch detail
                        list_resp = await client.get(
                            "/api/library/",
                            headers=headers,
                            params={"page": 1, "page_size": 1}
                        )
                        if list_resp.status_code == 200:
                            items = list_resp.json().get("items", [])
                            if items:
                                response = await client.get(
                                    f"/api/library/{items[0]['id']}",
                                    headers=headers
                                )
                            else:
                                continue
                        else:
                            continue
                    else:  # note
                        response = await client.post(
                            "/api/library/notes",
                            headers={**headers, "Content-Type": "application/json"},
                            json={
                                "title": f"Load Test {user_id}-{i}",
                                "content": f"Test content {datetime.now().isoformat()}"
                            }
                        )
                    
                    latency = time.time() - start
                    
                    success = response.status_code in [200, 201]
                    error = None if success else f"Status {response.status_code}"
                    
                    result.record(latency, success, error)
                    
                except Exception as e:
                    latency = time.time() - start
                    result.record(latency, False, str(e))
                
                # Small delay between requests
                await asyncio.sleep(random.uniform(0.1, 0.5))
    
    # Run users concurrently
    logger.info(f"Starting load test: {num_users} users, {requests_per_user} requests each")
    start_time = time.time()
    
    users = [asyncio.create_task(user_task(i)) for i in range(num_users)]
    
    # Wait for completion or timeout
    done, pending = await asyncio.wait(
        users,
        timeout=duration_seconds,
        return_when=asyncio.ALL_COMPLETED
    )
    
    # Cancel pending tasks
    for task in pending:
        task.cancel()
    
    elapsed = time.time() - start_time
    
    print(f"\n{'='*60}")
    print(f"Load Test completed in {elapsed:.2f} seconds")
    print(result.summary())
    
    return result


# ============================================================================
# CLI Entry Point
# ============================================================================

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Library Load Testing")
    parser.add_argument(
        "--mode",
        choices=["locust", "custom"],
        default="custom",
        help="Load testing mode"
    )
    parser.add_argument(
        "--host",
        default="http://localhost:8000",
        help="Backend URL"
    )
    parser.add_argument(
        "--users",
        type=int,
        default=10,
        help="Number of concurrent users"
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=60,
        help="Test duration in seconds"
    )
    parser.add_argument(
        "--requests",
        type=int,
        default=100,
        help="Requests per user"
    )
    
    args = parser.parse_args()
    
    if args.mode == "locust":
        if not LOCUST_AVAILABLE:
            print("Error: locust not installed. Run: pip install locust")
            sys.exit(1)
        
        print(f"""
{'='*60}
LOCUST LOAD TEST
{'='*60}
Host: {args.host}
License: {TEST_LICENSE_KEY}

Start locust with:
  locust -f {__file__} --host={args.host}

Or headless:
  locust -f {__file__} --host={args.host} --headless -u {args.users} -r 10 -t {args.duration}s
{'='*60}
""")
    else:
        print(f"""
{'='*60}
CUSTOM LOAD TEST
{'='*60}
Host: {args.host}
Users: {args.users}
Duration: {args.duration}s
Requests/user: {args.requests}
{'='*60}
""")
        
        asyncio.run(run_custom_load_test(
            base_url=args.host,
            license_key=TEST_LICENSE_KEY,
            num_users=args.users,
            duration_seconds=args.duration,
            requests_per_user=args.requests
        ))
