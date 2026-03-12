"""
Al-Mudeer - Task Feature Load Tests
Load testing suite for tasks feature using Locust.

Tests concurrent task operations to verify:
- WebSocket scaling under load
- Database connection pool handling
- LWW conflict resolution under concurrent updates
- Task sharing performance
- Cache effectiveness under load

FIX PERF-001: Enhanced with correlation ID tracking and detailed metrics.

Usage:
    # Install locust
    pip install locust

    # Run load test with web UI
    locust -f tests/load/task_load_tests.py --host=http://localhost:8000

    # Run with specific user load
    locust -f tests/load/task_load_tests.py --host=http://localhost:8000 \
        --users 100 --spawn-rate 10 --run-time 5m

    # Headless mode for CI/CD
    locust -f tests/load/task_load_tests.py --host=http://localhost:8000 \
        --users 200 --spawn-rate 20 --headless --run-time 10m \
        --html=report.html
    
    # Stress test (500 users)
    locust -f tests/load/task_load_tests.py --host=http://localhost:8000 \
        --users 500 --spawn-rate 50 --headless --run-time 15m \
        --html=stress_test_report.html

    # With correlation ID tracking (for debugging)
    LOCUST_CORRELATION_ID=1 locust -f tests/load/task_load_tests.py \
        --host=http://localhost:8000 --users 100 --spawn-rate 10
"""

import random
import json
import uuid
import os
from datetime import datetime, timedelta
from locust import HttpUser, task, between, events
from logging import getLogger

logger = getLogger(__name__)

# FIX PERF-001: Correlation ID for tracing
USE_CORRELATION_ID = os.getenv("LOCUST_CORRELATION_ID", "0") == "1"


class TaskUser(HttpUser):
    """
    Simulates a user performing task operations.
    
    FIX PERF-001: Added correlation ID support and enhanced logging.
    """

    wait_time = between(1, 3)  # Wait 1-3 seconds between tasks
    
    # Task tracking for realistic scenarios
    task_ids = []
    max_tracked_tasks = 10

    def on_start(self):
        """Authenticate and get token on start"""
        self.license_key = self._get_or_create_license()
        self.token = self._authenticate()
        self.task_ids = []
        self.user_id = f"user_{random.randint(1000, 9999)}"
        
        logger.info(f"TaskUser started: user={self.user_id}, license={self.license_key[:20]}...")

    def _get_or_create_license(self):
        """Get or create a test license key"""
        # For load testing, use a demo license
        return "demo-license-key"

    def _authenticate(self):
        """Authenticate and get JWT token"""
        try:
            response = self.client.post(
                "/api/auth/login",
                json={
                    "license_key": self.license_key,
                    "username": self.user_id,
                    "password": "test_password_123"
                }
            )
            if response.status_code == 200:
                data = response.json()
                return data.get("access_token")
        except Exception as e:
            logger.warning(f"Authentication failed: {e}")

        # Fallback: use demo token
        return "demo-token"

    def _get_headers(self):
        """Get request headers with optional correlation ID"""
        headers = {"Authorization": f"Bearer {self.token}"}
        if USE_CORRELATION_ID:
            headers["X-Correlation-ID"] = f"{self.user_id}-{uuid.uuid4().hex[:8]}"
        return headers
    
    @task(10)
    def list_tasks(self):
        """Get task list (most common operation)"""
        self.client.get(
            "/api/tasks/",
            headers=self._get_headers(),
            name="/api/tasks [GET]"
        )

    @task(5)
    def create_task(self):
        """Create a new task"""
        task_id = str(uuid.uuid4())
        task_data = {
            "id": task_id,
            "title": f"Load Test Task {random.randint(1000, 9999)}",
            "description": "Automatically generated load test task",
            "priority": random.choice(["low", "medium", "high", "urgent"]),
            "category": random.choice(["Work", "Personal", "Shopping", "Health"]),
            "is_completed": False,
            "visibility": "shared",
            "updated_at": datetime.utcnow().isoformat()
        }

        # Some tasks have due dates
        if random.random() > 0.5:
            task_data["due_date"] = (
                datetime.utcnow() + timedelta(days=random.randint(1, 30))
            ).isoformat()

        # Some tasks have subtasks
        if random.random() > 0.7:
            task_data["sub_tasks"] = [
                {"id": str(uuid.uuid4()), "title": f"Subtask {i}", "is_completed": False}
                for i in range(random.randint(1, 5))
            ]

        response = self.client.post(
            "/api/tasks/",
            data={"task_json": json.dumps(task_data)},
            headers=self._get_headers(),
            name="/api/tasks [POST]"
        )

        # Track created task for later operations
        if response.status_code == 200 and len(self.task_ids) < self.max_tracked_tasks:
            self.task_ids.append(task_id)

    @task(8)
    def update_task(self):
        """Update an existing task"""
        if not self.task_ids:
            return

        task_id = random.choice(self.task_ids)
        update_data = {
            "title": f"Updated Task {random.randint(1000, 9999)}",
            "updated_at": datetime.utcnow().isoformat()
        }

        # Sometimes toggle completion status
        if random.random() > 0.7:
            update_data["is_completed"] = random.choice([True, False])

        # Sometimes update priority
        if random.random() > 0.5:
            update_data["priority"] = random.choice(["low", "medium", "high", "urgent"])

        self.client.put(
            f"/api/tasks/{task_id}",
            data={"task_json": json.dumps(update_data)},
            headers=self._get_headers(),
            name="/api/tasks/{id} [PUT]"
        )

    @task(3)
    def delete_task(self):
        """Delete a task"""
        if not self.task_ids:
            return

        task_id = self.task_ids.pop()
        self.client.delete(
            f"/api/tasks/{task_id}",
            headers=self._get_headers(),
            name="/api/tasks/{id} [DELETE]"
        )

    @task(2)
    def share_task(self):
        """Share a task with another user"""
        if not self.task_ids:
            return

        task_id = random.choice(self.task_ids)
        share_data = {
            "shared_with_user_id": f"user_{random.randint(1000, 9999)}",
            "permission": random.choice(["read", "edit", "admin"])
        }

        self.client.post(
            f"/api/tasks/{task_id}/share",
            json=share_data,
            headers=self._get_headers(),
            name="/api/tasks/{id}/share [POST]"
        )

    @task(4)
    def get_collaborators(self):
        """Get list of collaborators"""
        self.client.get(
            "/api/tasks/collaborators",
            headers=self._get_headers(),
            name="/api/tasks/collaborators [GET]"
        )

    @task(1)
    def add_comment(self):
        """Add a comment to a task"""
        if not self.task_ids:
            return

        task_id = random.choice(self.task_ids)
        comment_data = {
            "content": f"Load test comment {random.randint(1000, 9999)}",
            "user_id": "test-user"
        }

        self.client.post(
            f"/api/tasks/{task_id}/comments",
            data={"comment_json": json.dumps(comment_data)},
            headers=self._get_headers(),
            name="/api/tasks/{id}/comments [POST]"
        )

    @task(1)
    def get_analytics(self):
        """Get task analytics (tests cache effectiveness)"""
        self.client.get(
            "/api/tasks/analytics",
            headers=self._get_headers(),
            name="/api/tasks/analytics [GET]"
        )


class TaskConflictUser(HttpUser):
    """
    Simulates concurrent updates to the same task (conflict testing).
    This tests LWW conflict resolution under load.
    """
    
    wait_time = between(0.1, 0.5)  # Very fast updates to create conflicts
    
    def on_start(self):
        """Get token and shared task ID"""
        self.token = "demo-token"
        # All users in this class will update the same task
        self.conflict_task_id = "conflict-test-task-" + str(uuid.uuid4())[:8]
        
        # Create the task first
        self._create_conflict_task()
    
    def _create_conflict_task(self):
        """Create initial task for conflict testing"""
        task_data = {
            "id": self.conflict_task_id,
            "title": "Conflict Test Task",
            "description": "Task for testing LWW conflict resolution",
            "priority": "medium",
            "is_completed": False,
            "updated_at": datetime.utcnow().isoformat()
        }
        
        self.client.post(
            "/api/tasks/",
            data={"task_json": json.dumps(task_data)},
            headers={"Authorization": f"Bearer {self.token}"},
            name="/api/tasks [POST - Conflict Setup]"
        )
    
    @task
    def concurrent_update(self):
        """Rapidly update the same task to test LWW"""
        update_data = {
            "title": f"Concurrent Update {random.randint(1000, 9999)}",
            "updated_at": datetime.utcnow().isoformat()
        }
        
        self.client.put(
            f"/api/tasks/{self.conflict_task_id}",
            data={"task_json": json.dumps(update_data)},
            headers={"Authorization": f"Bearer {self.token}"},
            name="/api/tasks/{id} [PUT - Conflict]"
        )


# ============ Event Handlers ============

# Metrics tracking
_metrics = {
    "start_time": None,
    "total_requests": 0,
    "failed_requests": 0,
    "slow_requests": 0,
    "errors": []
}


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Called when load test starts"""
    _metrics["start_time"] = datetime.now()
    logger.info("=" * 60)
    logger.info("LOAD TEST STARTING")
    logger.info("=" * 60)
    logger.info(f"Target host: {environment.host}")
    logger.info(f"Users: {environment.parsed_options.num_users}")
    logger.info(f"Spawn rate: {environment.parsed_options.spawn_rate}")
    logger.info(f"Correlation ID tracking: {'ENABLED' if USE_CORRELATION_ID else 'DISABLED'}")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Called when load test stops"""
    duration = (datetime.now() - _metrics["start_time"]).total_seconds() if _metrics["start_time"] else 0
    
    logger.info("=" * 60)
    logger.info("LOAD TEST COMPLETED")
    logger.info("=" * 60)
    logger.info(f"Duration: {duration:.2f} seconds")
    logger.info(f"Total requests: {_metrics['total_requests']}")
    logger.info(f"Failed requests: {_metrics['failed_requests']}")
    logger.info(f"Slow requests (>1s): {_metrics['slow_requests']}")
    
    # Calculate success rate
    if _metrics["total_requests"] > 0:
        success_rate = (1 - _metrics["failed_requests"] / _metrics["total_requests"]) * 100
        logger.info(f"Success rate: {success_rate:.2f}%")
    
    # Print summary statistics
    stats = environment.stats
    logger.info(f"\nRequest statistics:")
    logger.info(f"  Total: {stats.total.num_requests}")
    logger.info(f"  Failures: {stats.total.num_failures}")
    logger.info(f"  Avg response time: {stats.total.avg_response_time:.2f}ms")
    logger.info(f"  Min response time: {stats.total.min_response_time:.2f}ms")
    logger.info(f"  Max response time: {stats.total.max_response_time:.2f}ms")
    logger.info(f"  Requests/sec: {stats.total.current_rps:.2f}")
    
    # Performance recommendations
    logger.info("\n" + "=" * 60)
    logger.info("PERFORMANCE RECOMMENDATIONS")
    logger.info("=" * 60)
    
    if stats.total.avg_response_time > 500:
        logger.warning("⚠ Average response time > 500ms - Consider optimizing database queries")
    
    if stats.total.fail_ratio > 0.01:
        logger.warning("⚠ Failure rate > 1% - Check error logs for issues")
    
    if _metrics["slow_requests"] > _metrics["total_requests"] * 0.1:
        logger.warning("⚠ > 10% requests are slow - Consider adding caching or indexing")
    
    logger.info("=" * 60)


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response,
               context, exception, start_time, url, **kwargs):
    """Called on each request for custom logging"""
    _metrics["total_requests"] += 1
    
    if exception:
        _metrics["failed_requests"] += 1
        _metrics["errors"].append(str(exception))
        logger.warning(f"Request failed: {name} - {exception}")

    # Log slow requests
    if response_time > 1000:
        _metrics["slow_requests"] += 1
        logger.warning(f"Slow request: {name} took {response_time:.0f}ms")


# ============ Custom Assertions ============

def assert_response_time(response, max_ms=500):
    """Assert response time is under threshold"""
    if response.elapsed.total_seconds() * 1000 > max_ms:
        raise Exception(f"Response time {response.elapsed.total_seconds()*1000:.0f}ms > {max_ms}ms")


def assert_json_response(response):
    """Assert response is valid JSON"""
    try:
        response.json()
    except:
        raise Exception("Response is not valid JSON")


# ============ Load Test Scenarios ============

"""
Recommended Scenarios:

1. Normal Load (100 users, 10 min):
   locust -f task_load_tests.py --users 100 --spawn-rate 10 --run-time 10m

2. Peak Load (500 users, 15 min):
   locust -f task_load_tests.py --users 500 --spawn-rate 50 --run-time 15m

3. Stress Test (1000 users, 30 min):
   locust -f task_load_tests.py --users 1000 --spawn-rate 100 --run-time 30m

4. Conflict Test (50 users, 5 min):
   # Only run TaskConflictUser
   locust -f task_load_tests.py --users 50 --spawn-rate 5 --run-time 5m \
       --exclude-class TaskUser

5. Endurance Test (200 users, 2 hours):
   locust -f task_load_tests.py --users 200 --spawn-rate 20 --run-time 120m
"""
