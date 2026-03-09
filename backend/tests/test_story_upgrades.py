import pytest
from datetime import datetime, timedelta
from models.stories import add_story, update_story, delete_story, get_active_stories, cleanup_expired_stories
from database import get_db, execute_sql, fetch_one
import asyncio

@pytest.mark.asyncio
async def test_story_expiration_calculation():
    """Verify that expires_at is correctly calculated based on duration_hours."""
    # Mock license and user
    license_id = 1
    user_id = "test_user"
    
    # Test 6 hours duration
    story = await add_story(
        license_id=license_id,
        story_type="text",
        user_id=user_id,
        content="Test Story 6h",
        duration_hours=6
    )
    
    created_at = datetime.fromisoformat(story['created_at']) if isinstance(story['created_at'], str) else story['created_at']
    expires_at = datetime.fromisoformat(story['expires_at']) if isinstance(story['expires_at'], str) else story['expires_at']
    
    # Check difference is roughly 6 hours
    diff = expires_at - created_at
    assert abs(diff.total_seconds() - 6 * 3600) < 10

@pytest.mark.asyncio
async def test_update_story_content():
    """Verify that story content can be updated."""
    license_id = 1
    user_id = "test_user"
    
    # Create initial story
    story = await add_story(
        license_id=license_id,
        story_type="text",
        user_id=user_id,
        content="Original Content"
    )
    
    # Update content
    updated = await update_story(
        story_id=story['id'],
        license_id=license_id,
        user_id=user_id,
        content="Updated Content"
    )
    
    assert updated['content'] == "Updated Content"
    assert updated['updated_at'] is not None

@pytest.mark.asyncio
async def test_story_visibility_after_expiration():
    """Verify that expired stories are not returned by get_active_stories."""
    license_id = 1
    user_id = "test_user"
    
    # Manually insert an expired story
    async with get_db() as db:
        now = datetime.utcnow()
        expired_time = (now - timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S')
        await execute_sql(
            db,
            "INSERT INTO stories (license_key_id, user_id, type, content, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
            [license_id, user_id, "text", "Expired Story", now.strftime('%Y-%m-%d %H:%M:%S'), expired_time]
        )
        await db.commit()
    
    # Fetch active stories
    active_stories = await get_active_stories(license_id)
    
    # Verify the expired story is not there
    assert not any(s['content'] == "Expired Story" for s in active_stories)

@pytest.mark.asyncio
async def test_cleanup_removes_expired_stories():
    """Verify that cleanup_expired_stories permanently deletes expired entries."""
    license_id = 1
    user_id = "test_user"
    
    # Manually insert an expired story
    async with get_db() as db:
        now = datetime.utcnow()
        expired_time = (now - timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S')
        await execute_sql(
            db,
            "INSERT INTO stories (license_key_id, user_id, type, content, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
            [license_id, user_id, "text", "Old Story", now.strftime('%Y-%m-%d %H:%M:%S'), expired_time]
        )
        await db.commit()
    
    # Run cleanup
    await cleanup_expired_stories()
    
    # Verify it's gone from DB
    async with get_db() as db:
        row = await fetch_one(db, "SELECT * FROM stories WHERE content = ?", ["Old Story"])
        assert row is None
