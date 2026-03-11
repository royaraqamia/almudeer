"""Verify production setup for tasks feature"""
import sys
import os

# Set dummy keys for testing
os.environ["JWT_SECRET_KEY"] = "test_key_for_verification_only_64_chars_long_hex_string_12345"
os.environ["ADMIN_KEY"] = "test_admin_key_64_chars_long_hex_string_for_testing_123456"
os.environ["DEVICE_SECRET_PEPPER"] = "test_pepper_64_chars_long_hex_string_for_testing_123456"
os.environ["LICENSE_KEY_PEPPER"] = "test_pepper_64_chars_long_hex_string_for_testing_123456"

print("=" * 60)
print("TASKS FEATURE - PRODUCTION SETUP VERIFICATION")
print("=" * 60)

# Test 1: Alerting Service
print("\n[1/5] Testing Alerting Service import...")
try:
    from services.alerting_service import get_alerting_service, AlertingService
    service = get_alerting_service()
    print("      ✓ Alerting service: OK")
    print(f"      - Default thresholds: {len(service._thresholds)}")
except Exception as e:
    print(f"      ✗ Alerting service: FAILED - {e}")
    sys.exit(1)

# Test 2: Telemetry Service
print("\n[2/5] Testing Telemetry Service import...")
try:
    from services.telemetry import setup_telemetry, get_tracer
    print("      ✓ Telemetry service: OK")
except Exception as e:
    print(f"      ✗ Telemetry service: FAILED - {e}")

# Test 3: Task Shares Model
print("\n[3/5] Testing Task Shares model...")
try:
    from models.task_shares import share_task, get_shared_tasks, remove_share
    print("      ✓ Task shares model: OK")
except Exception as e:
    print(f"      ✗ Task shares model: FAILED - {e}")
    sys.exit(1)

# Test 4: Tasks Routes
print("\n[4/5] Testing Tasks routes...")
try:
    from routes.tasks import router as tasks_router
    print("      ✓ Tasks routes: OK")
    # Check OpenAPI docs
    routes = [r.path for r in tasks_router.routes]
    print(f"      - Endpoints: {len(routes)}")
except Exception as e:
    print(f"      ✗ Tasks routes: FAILED - {e}")
    sys.exit(1)

# Test 5: Migration Files
print("\n[5/5] Checking migration files...")
migration_dir = "alembic/versions"
expected_migrations = [
    "20260307_028_add_tasks_table.py",
    "20260307_029_add_task_sharing.py",
    "20260308_030a_add_task_shares_updated_at.py",
    "20260311_036_add_task_shares_expires_at.py",
]

for migration in expected_migrations:
    path = os.path.join(migration_dir, migration)
    if os.path.exists(path):
        print(f"      ✓ {migration}")
    else:
        print(f"      ✗ {migration} - MISSING")

print("\n" + "=" * 60)
print("VERIFICATION COMPLETE")
print("=" * 60)
print("\nNext steps:")
print("1. Run: alembic upgrade head")
print("2. Set OTEL_ENABLED=true for distributed tracing")
print("3. Start backend and check /api/health endpoint")
