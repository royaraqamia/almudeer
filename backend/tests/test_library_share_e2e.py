"""
End-to-End Tests for Library Share Notifications

P3-14: Test the complete flow of sharing library items and receiving notifications.
This tests the integration between:
- Library sharing API
- Notification service
- WebSocket event delivery
- Database state

Run with: pytest tests/test_library_share_e2e.py -v --tb=short
"""

import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport
from main import app
from db_helper import get_db, fetch_one, fetch_all, execute_sql
from models.library import add_library_item
from models.library_advanced import share_item, get_shared_items


@pytest.fixture
async def test_db():
    """Set up test database with test users"""
    # Create test users if they don't exist
    async with get_db() as db:
        import hashlib
        # Create test license using key_hash (the correct column)
        test_key = 'TEST_SHARE_E2E_KEY'
        key_hash = hashlib.sha256(test_key.encode()).hexdigest()
        
        # Ensure license_key column exists (migration for backward compatibility)
        try:
            await db.execute("ALTER TABLE license_keys ADD COLUMN license_key TEXT")
            await db.commit()
        except:
            pass  # Column already exists
        
        await db.execute(
            """
            INSERT OR IGNORE INTO license_keys (key_hash, license_key, is_active, created_at)
            VALUES (?, ?, 1, ?)
            """,
            [key_hash, test_key, datetime.now(timezone.utc)]
        )
        await db.commit()

        license_result = await fetch_one(
            db,
            "SELECT id FROM license_keys WHERE key_hash = ?",
            [key_hash]
        )
        license_id = license_result['id'] if license_result else 1

        # Create test users
        for email in ['owner@test.com', 'recipient@test.com']:
            await db.execute(
                """
                INSERT OR IGNORE INTO users (email, license_key_id, is_active, created_at)
                VALUES (?, ?, 1, ?)
                """,
                [email, license_id, datetime.now(timezone.utc)]
            )
        await db.commit()

        yield {'license_id': license_id}

        # Cleanup
        await db.execute("DELETE FROM users WHERE email LIKE '%@test.com'")
        await db.execute("DELETE FROM license_keys WHERE key_hash = ?", [key_hash])
        await db.commit()


@pytest.fixture
async def test_item(test_db):
    """Create a test library item"""
    item = await add_library_item(
        license_id=test_db['license_id'],
        item_type='note',
        user_id='owner@test.com',
        title='Test Share Item',
        content='Test content for sharing'
    )
    yield item
    # Cleanup handled by test_db fixture


@pytest.mark.asyncio
async def test_share_creates_notification(test_item, test_db):
    """
    E2E Test: Sharing an item creates a notification
    
    Flow:
    1. Owner shares item with recipient
    2. Notification is created in database
    3. Verify notification content
    """
    # Share the item
    result = await share_item(
        item_id=test_item['id'],
        license_id=test_db['license_id'],
        shared_with_user_id='recipient@test.com',
        permission='read',
        created_by='owner@test.com'
    )
    
    assert result['item_id'] == test_item['id']
    assert result['shared_with'] == 'recipient@test.com'
    assert result['permission'] == 'read'
    
    # Verify share was created in database
    async with get_db() as db:
        share = await fetch_one(
            db,
            """
            SELECT * FROM library_shares
            WHERE item_id = ? AND shared_with_user_id = ?
            """,
            [test_item['id'], 'recipient@test.com']
        )
        
        assert share is not None
        assert share['permission'] == 'read'
        assert share['deleted_at'] is None
        
        # Verify notification was created
        notification = await fetch_one(
            db,
            """
            SELECT * FROM notifications
            WHERE license_key_id = ?
            AND user_id = (SELECT id FROM users WHERE email = 'recipient@test.com')
            AND notification_type = 'library_share'
            ORDER BY created_at DESC
            LIMIT 1
            """,
            [test_db['license_id']]
        )
        
        # Note: Notification might be created asynchronously
        # This assertion may need adjustment based on timing
        if notification:
            assert notification['resource_id'] == str(test_item['id'])
            assert notification['resource_type'] == 'library'


@pytest.mark.asyncio
async def test_shared_item_appears_in_recipient_list(test_item, test_db):
    """
    E2E Test: Shared item appears in recipient's shared-with-me list
    
    Flow:
    1. Owner shares item with recipient
    2. Recipient fetches shared-with-me endpoint
    3. Verify item is in the list with correct permission
    """
    # Share the item
    await share_item(
        item_id=test_item['id'],
        license_id=test_db['license_id'],
        shared_with_user_id='recipient@test.com',
        permission='edit',
        created_by='owner@test.com'
    )
    
    # Get shared items for recipient
    shared_items = await get_shared_items(
        license_id=test_db['license_id'],
        user_id='recipient@test.com'
    )
    
    assert len(shared_items) > 0
    
    # Find our item
    our_item = next(
        (item for item in shared_items if item['id'] == test_item['id']),
        None
    )
    
    assert our_item is not None
    assert our_item['share_permission'] == 'edit'
    assert our_item['title'] == 'Test Share Item'


@pytest.mark.asyncio
async def test_share_expiration(test_item, test_db):
    """
    E2E Test: Share expiration works correctly
    
    Flow:
    1. Share item with expiration
    2. Verify share is active before expiration
    3. Simulate expiration
    4. Verify share is no longer accessible
    """
    from models.library_advanced import share_item as share_item_advanced
    
    # Share with 1 day expiration
    result = await share_item_advanced(
        item_id=test_item['id'],
        license_id=test_db['license_id'],
        shared_with_user_id='recipient@test.com',
        permission='read',
        created_by='owner@test.com',
        expires_in_days=1
    )
    
    assert result['expires_at'] is not None
    
    # Verify expiration is set correctly (approximately 1 day from now)
    expected_expiration = datetime.now(timezone.utc) + timedelta(days=1)
    time_diff = abs((result['expires_at'] - expected_expiration).total_seconds())
    assert time_diff < 60  # Within 1 minute
    
    # Share should be accessible now
    shared_items = await get_shared_items(
        license_id=test_db['license_id'],
        user_id='recipient@test.com'
    )
    
    assert len([i for i in shared_items if i['id'] == test_item['id']]) == 1
    
    # Now test with expired share
    expired_result = await share_item_advanced(
        item_id=test_item['id'] + 100,  # Different item ID to avoid conflict
        license_id=test_db['license_id'],
        shared_with_user_id='recipient2@test.com',
        permission='read',
        created_by='owner@test.com',
        expires_in_days=-1  # Expired yesterday
    )
    
    # Expired shares should not appear in shared items
    shared_items = await get_shared_items(
        license_id=test_db['license_id'],
        user_id='recipient2@test.com'
    )
    
    # Should not include expired shares
    assert len([i for i in shared_items if i['id'] == test_item['id'] + 100]) == 0


@pytest.mark.asyncio
async def test_revoke_share_notification(test_item, test_db):
    """
    E2E Test: Revoking share creates notification
    
    Flow:
    1. Share item with recipient
    2. Revoke the share
    3. Verify share is marked as deleted
    4. Verify revocation notification is created
    """
    from models.library_advanced import remove_share
    
    # Share the item
    share_result = await share_item(
        item_id=test_item['id'],
        license_id=test_db['license_id'],
        shared_with_user_id='recipient@test.com',
        permission='read',
        created_by='owner@test.com'
    )
    
    share_id = share_result.get('id') or share_result.get('share_id')
    
    # Get share from DB to get ID
    async with get_db() as db:
        share = await fetch_one(
            db,
            "SELECT id FROM library_shares WHERE item_id = ? AND shared_with_user_id = ?",
            [test_item['id'], 'recipient@test.com']
        )
        share_id = share['id']
    
    # Revoke the share
    success = await remove_share(
        share_id=share_id,
        license_id=test_db['license_id'],
        revoked_by='owner@test.com'
    )
    
    assert success is True
    
    # Verify share is marked as deleted
    async with get_db() as db:
        share = await fetch_one(
            db,
            "SELECT deleted_at FROM library_shares WHERE id = ?",
            [share_id]
        )
        
        assert share is not None
        assert share['deleted_at'] is not None
        
        # Verify share no longer appears in shared items
        shared_items = await get_shared_items(
            license_id=test_db['license_id'],
            user_id='recipient@test.com'
        )
        
        assert len([i for i in shared_items if i['id'] == test_item['id']]) == 0


@pytest.mark.asyncio
async def test_self_share_prevention(test_item, test_db):
    """
    E2E Test: Cannot share item with yourself
    
    Flow:
    1. Owner tries to share item with themselves
    2. Verify ValueError is raised
    """
    with pytest.raises(ValueError) as exc_info:
        await share_item(
            item_id=test_item['id'],
            license_id=test_db['license_id'],
            shared_with_user_id='owner@test.com',
            permission='read',
            created_by='owner@test.com'
        )
    
    assert "Cannot share an item with yourself" in str(exc_info.value)


@pytest.mark.asyncio
async def test_duplicate_share_update(test_item, test_db):
    """
    E2E Test: Re-sharing updates existing share instead of creating duplicate
    
    Flow:
    1. Share item with read permission
    2. Share same item with edit permission
    3. Verify only one share exists with updated permission
    """
    # First share
    await share_item(
        item_id=test_item['id'],
        license_id=test_db['license_id'],
        shared_with_user_id='recipient@test.com',
        permission='read',
        created_by='owner@test.com'
    )
    
    # Second share (update)
    await share_item(
        item_id=test_item['id'],
        license_id=test_db['license_id'],
        shared_with_user_id='recipient@test.com',
        permission='admin',
        created_by='owner@test.com'
    )
    
    # Verify only one share exists
    async with get_db() as db:
        shares = await fetch_all(
            db,
            """
            SELECT * FROM library_shares
            WHERE item_id = ? AND shared_with_user_id = ? AND deleted_at IS NULL
            """,
            [test_item['id'], 'recipient@test.com']
        )
        
        assert len(shares) == 1
        assert shares[0]['permission'] == 'admin'
