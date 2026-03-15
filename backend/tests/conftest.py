"""
Al-Mudeer Test Fixtures
Shared fixtures for backend testing
"""

import os
import sys
import pytest
import asyncio
from typing import AsyncGenerator, Generator

# Register custom pytest marks
def pytest_configure(config):
    """Register custom marks to avoid warnings"""
    config.addinivalue_line(
        "markers", "loadtest: mark test as a load test (slow, requires special setup)"
    )

# Set test environment
os.environ["TESTING"] = "1"
os.environ["DB_TYPE"] = "sqlite"
os.environ["DATABASE_PATH"] = ":memory:"
os.environ["ADMIN_KEY"] = "test-admin-key"
os.environ["ENCRYPTION_KEY"] = "test-encryption-key-for-tests"
os.environ["JWT_SECRET_KEY"] = "test-jwt-secret-key-at-least-thirty-two-chars-long"

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture(scope="session")
def event_loop() -> Generator[asyncio.AbstractEventLoop, None, None]:
    """Create event loop for async tests"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
async def test_app():
    """Create test FastAPI app instance"""
    from main import app
    yield app


@pytest.fixture
async def test_client(test_app):
    """Create async test client"""
    from httpx import AsyncClient, ASGITransport

    transport = ASGITransport(app=test_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.fixture
def sample_license_key():
    """Sample license key for tests"""
    return "test-license-key-12345"


@pytest.fixture
def sample_license_headers(sample_license_key):
    """Sample headers with license key"""
    return {"X-License-Key": sample_license_key}


@pytest.fixture(autouse=False)
async def db_session():
    """Create a test database session with schema initialized.
    
    Note: This fixture is NOT autouse. Tests that need database
    should explicitly request it. Tests using mocks should not.
    """
    from db_helper import get_db
    import aiosqlite
    import tempfile

    # Use a unique test database file per test to avoid locking
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
    temp_db_path = temp_db.name
    temp_db.close()
    
    try:
        async with aiosqlite.connect(temp_db_path) as db:
            # Initialize License Keys
            await db.execute("""
                CREATE TABLE IF NOT EXISTS license_keys (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    key_hash TEXT UNIQUE NOT NULL,
                    license_key TEXT,
                    license_key_encrypted TEXT,
                    full_name TEXT NOT NULL,
                    profile_image_url TEXT,
                    username TEXT UNIQUE,
                    is_active BOOLEAN DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    expires_at TIMESTAMP,
                    last_seen_at TIMESTAMP,
                    referral_code TEXT UNIQUE,
                    referred_by_id INTEGER,
                    is_trial BOOLEAN DEFAULT 0,
                    referral_count INTEGER DEFAULT 0,
                    phone TEXT,
                    token_version INTEGER DEFAULT 1
                )
            """)
            
            # Initialize outbox_messages
            await db.execute("""
                CREATE TABLE IF NOT EXISTS outbox_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    license_key_id INTEGER NOT NULL,
                    channel TEXT NOT NULL,
                    body TEXT NOT NULL,
                    status TEXT DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    edited_at TIMESTAMP,
                    edit_count INTEGER DEFAULT 0,
                    edited_by TEXT,
                    original_body TEXT,
                    deleted_at TIMESTAMP,
                    recipient_contact TEXT,
                    recipient_id INTEGER,
                    FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
                )
            """)
            
            # Initialize inbox_messages
            await db.execute("""
                CREATE TABLE IF NOT EXISTS inbox_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    license_key_id INTEGER NOT NULL,
                    channel TEXT NOT NULL,
                    body TEXT NOT NULL,
                    status TEXT DEFAULT 'new',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    edited_at TIMESTAMP,
                    platform_message_id TEXT,
                    sender_contact TEXT,
                    FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
                )
            """)
            
            await db.commit()
        
        yield temp_db_path
    finally:
        try:
            os.unlink(temp_db_path)
        except:
            pass


@pytest.fixture
async def seeded_license(db_session):
    """Create a seeded license key for testing"""
    import aiosqlite
    
    async with aiosqlite.connect(db_session) as db:
        await db.execute("""
            INSERT INTO license_keys (key_hash, license_key, full_name, username, is_active)
            VALUES (?, ?, ?, ?, ?)
        """, ("test-hash", "test-key", "Test User", "testuser", 1))
        await db.commit()
    
    yield db_session
