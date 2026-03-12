"""
Al-Mudeer Test Fixtures
Shared pytest fixtures for backend testing
"""

import os
import sys
import pytest
import asyncio
from typing import AsyncGenerator, Generator

# Set test environment
os.environ["TESTING"] = "1"
os.environ["DB_TYPE"] = "sqlite"
os.environ["DATABASE_PATH"] = "test_almudeer.db"
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
def sample_license_key() -> str:
    """Return a sample license key for testing"""
    return "MUDEER-TEST-1234-5678"


@pytest.fixture
def sample_message() -> dict:
    """Return a sample message for testing"""
    return {
        "body": "مرحباً، أريد الاستفسار عن الأسعار",
        "sender_name": "أحمد محمد",
        "sender_contact": "+963912345678",
        "channel": "telegram",
    }


@pytest.fixture
def auth_headers(sample_license_key) -> dict:
    """Return authentication headers"""
    return {"X-License-Key": sample_license_key}


@pytest.fixture(autouse=True)
async def db_session():
    """Create a test database session with schema initialized"""
    from db_helper import get_db
    from models.base import init_enhanced_tables, init_customers_and_analytics

    # 1. Initialize Base Tables (License Keys, Legacy)
    async with get_db() as db:
        # Initialize License Keys (Fundamental)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS license_keys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key_hash TEXT UNIQUE NOT NULL,
                license_key TEXT,  -- For backward compatibility with some tests
                license_key_encrypted TEXT,
                full_name TEXT NOT NULL,
                profile_image_url TEXT,
                contact_email TEXT,
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
                email TEXT,
                token_version INTEGER DEFAULT 1
            )
        """)
        # Initialize Legacy Tables
        await db.execute("""
            CREATE TABLE IF NOT EXISTS usage_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                license_key_id INTEGER REFERENCES license_keys(id),
                action_type TEXT NOT NULL,
                input_preview TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS crm_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                license_key_id INTEGER REFERENCES license_keys(id),
                sender_name TEXT,
                sender_contact TEXT,
                message_type TEXT,
                intent TEXT,
                extracted_data TEXT,
                original_message TEXT,
                draft_response TEXT,
                status TEXT DEFAULT 'جديد',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP
            )
        """)

        await db.execute("""
            CREATE TABLE IF NOT EXISTS knowledge_documents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                license_key_id INTEGER NOT NULL REFERENCES license_keys(id),
                user_id TEXT,
                source TEXT DEFAULT 'manual',
                text TEXT,
                file_path TEXT,
                file_size INTEGER,
                mime_type TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP,
                deleted_at TIMESTAMP
            )
        """)
        
        # Users table for JWT authentication
        await db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                name TEXT,
                license_key_id INTEGER,
                role TEXT DEFAULT 'user',
                is_active BOOLEAN DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_login TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Initialize tasks table (needed for task sharing tests)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                license_key_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                description TEXT,
                status TEXT DEFAULT 'pending',
                priority TEXT DEFAULT 'medium',
                due_date TIMESTAMP,
                completed_at TIMESTAMP,
                created_by TEXT,
                assigned_to TEXT,
                visibility TEXT DEFAULT 'private',
                is_deleted BOOLEAN DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)
        
        # Initialize task_shares table
        await db.execute("""
            CREATE TABLE IF NOT EXISTS task_shares (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                license_key_id INTEGER NOT NULL,
                shared_with_user_id TEXT NOT NULL,
                permission TEXT NOT NULL DEFAULT 'read',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_by TEXT,
                expires_at TIMESTAMP,
                deleted_at TIMESTAMP,
                FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id) ON DELETE CASCADE,
                UNIQUE(task_id, shared_with_user_id)
            )
        """)
        
        await db.commit()

    # 2. Initialize Enhanced Tables (using model functions)
    # These functions manage their own DB connections/transactions
    await init_enhanced_tables()
    await init_customers_and_analytics()

    # 3. Seed Data and Yield Session
    async with get_db() as db:
        # Seed test license key
        import hashlib
        test_key = "MUDEER-TEST-1234-5678"
        key_hash = hashlib.sha256(test_key.encode()).hexdigest()

        await db.execute("""
            INSERT OR IGNORE INTO license_keys (key_hash, full_name, is_active)
            VALUES (?, ?, ?)
        """, (key_hash, "Test Company", 1))

        await db.commit()
        yield db

@pytest.fixture
async def seeded_license(db_session):
    """Ensure database has a test license key"""
    return "MUDEER-TEST-1234-5678"
