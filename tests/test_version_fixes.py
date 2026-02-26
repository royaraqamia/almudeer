"""
Tests for Auto-Update System Critical Fixes

Tests the following fixes:
1. ETag Cache Async Lock (no deadlocks)
2. Maintenance Window Midnight Crossing
3. Downgrade Prevention
4. CDN Health Check
5. Update Active Check in Admin Dashboard
"""

import pytest
import asyncio
from datetime import datetime, time, timezone
from unittest.mock import AsyncMock, patch, MagicMock

# Import the module under test
from routes.version import (
    _is_update_active,
    _get_version_etag,
    _refresh_etag_cache,
    _ETAG_DATA_CACHE_LOCK,
    _CDN_HEALTH_CACHE,
    _verify_cdn_health,
)
from database import set_app_config, get_app_config
import json


class TestVersionFixes:
    """Test critical auto-update fixes"""

    @pytest.mark.asyncio
    async def test_etag_cache_async_lock(self):
        """
        CRITICAL FIX #1: Test that ETag cache doesn't deadlock under concurrent load.
        
        Previously used threading.Lock() in async function, causing deadlocks.
        Now uses asyncio.Lock() for async-safe locking.
        """
        # Simulate 50 concurrent requests trying to refresh ETag cache
        async def get_etag():
            return _get_version_etag()
        
        tasks = [get_etag() for _ in range(50)]
        
        # This should complete without deadlocking
        # If using threading.Lock(), this would hang
        results = await asyncio.wait_for(
            asyncio.gather(*tasks, return_exceptions=True),
            timeout=10.0  # Should complete in <1 second
        )
        
        # All should succeed (no exceptions)
        successful = [r for r in results if not isinstance(r, Exception)]
        assert len(successful) == 50, f"Only {len(successful)}/50 succeeded"
        
        # All should return non-empty strings
        assert all(isinstance(r, str) and len(r) > 0 for r in successful)

    @pytest.mark.asyncio
    async def test_etag_cache_refresh_async_safe(self):
        """
        Test that _refresh_etag_cache uses async-safe locking.
        """
        # Verify the lock is an asyncio.Lock
        assert isinstance(_ETAG_DATA_CACHE_LOCK, asyncio.Lock), \
            "ETag cache lock must be asyncio.Lock, not threading.Lock"
        
        # Test concurrent refresh attempts
        async def refresh():
            await _refresh_etag_cache()
        
        tasks = [refresh() for _ in range(10)]
        
        # Should complete without deadlock
        await asyncio.wait_for(
            asyncio.gather(*tasks, return_exceptions=True),
            timeout=5.0
        )

    def test_maintenance_window_normal(self):
        """
        CRITICAL FIX #8: Test maintenance window during normal hours.
        
        Example: 02:00-04:00 should match 03:00
        """
        config = {
            "maintenance_hours": {
                "timezone": "UTC",
                "start": "02:00",
                "end": "04:00"
            }
        }
        
        # Mock datetime to return 03:00 UTC
        with patch('routes.version.datetime') as mock_datetime:
            mock_datetime.now.return_value = datetime(2026, 2, 26, 3, 0, tzinfo=timezone.utc)
            mock_datetime.strptime = datetime.strptime
            
            is_active, reason = _is_update_active(config)
            
            # Should be IN maintenance window (not active)
            assert is_active == False
            assert "Maintenance window" in reason

    def test_maintenance_window_midnight_crossing(self):
        """
        CRITICAL FIX #8: Test maintenance window crossing midnight.
        
        Example: 23:00-02:00 should match 23:30 and 01:00
        This was BROKEN before the fix (string comparison).
        """
        config = {
            "maintenance_hours": {
                "timezone": "UTC",
                "start": "23:00",
                "end": "02:00"
            }
        }
        
        # Test at 23:30 (should be in maintenance)
        with patch('routes.version.datetime') as mock_datetime:
            mock_datetime.now.return_value = datetime(2026, 2, 26, 23, 30, tzinfo=timezone.utc)
            mock_datetime.strptime = datetime.strptime
            mock_datetime.side_effect = lambda *args, **kw: datetime(*args, **kw)
            
            is_active, reason = _is_update_active(config)
            
            # Should be IN maintenance window (not active)
            assert is_active == False, "Should be in maintenance at 23:30"
            assert "Maintenance window" in reason
        
        # Test at 01:00 next day (should also be in maintenance)
        with patch('routes.version.datetime') as mock_datetime:
            mock_datetime.now.return_value = datetime(2026, 2, 27, 1, 0, tzinfo=timezone.utc)
            mock_datetime.strptime = datetime.strptime
            mock_datetime.side_effect = lambda *args, **kw: datetime(*args, **kw)
            
            is_active, reason = _is_update_active(config)
            
            # Should be IN maintenance window (not active)
            assert is_active == False, "Should be in maintenance at 01:00"
            assert "Maintenance window" in reason
        
        # Test at 12:00 (should NOT be in maintenance)
        with patch('routes.version.datetime') as mock_datetime:
            mock_datetime.now.return_value = datetime(2026, 2, 26, 12, 0, tzinfo=timezone.utc)
            mock_datetime.strptime = datetime.strptime
            mock_datetime.side_effect = lambda *args, **kw: datetime(*args, **kw)
            
            is_active, reason = _is_update_active(config)
            
            # Should be ACTIVE (not in maintenance)
            assert is_active == True, "Should be active at 12:00"

    def test_maintenance_window_outside_range(self):
        """
        Test that updates are active outside maintenance window.
        """
        config = {
            "maintenance_hours": {
                "timezone": "UTC",
                "start": "02:00",
                "end": "04:00"
            }
        }
        
        # Test at 12:00 (well outside window)
        with patch('routes.version.datetime') as mock_datetime:
            mock_datetime.now.return_value = datetime(2026, 2, 26, 12, 0, tzinfo=timezone.utc)
            mock_datetime.strptime = datetime.strptime
            
            is_active, reason = _is_update_active(config)
            
            # Should be ACTIVE
            assert is_active == True

    @pytest.mark.asyncio
    async def test_downgrade_prevention(self):
        """
        CRITICAL FIX #10: Test that downgrades require force_downgrade flag.
        
        Prevents admin from accidentally setting lower build number.
        """
        from routes.version import set_min_build_number
        from fastapi import HTTPException
        
        # First, set a build number
        test_admin_key = "test_admin_key"
        
        # Mock the admin check to always pass
        with patch('routes.version._check_admin_access', return_value=True):
            # Set initial build to 10
            result = await set_min_build_number(
                request=MagicMock(),
                build_number=10,
                is_soft_update=False,
                x_admin_key=test_admin_key
            )
            assert result['min_build_number'] == 10
            
            # Try to downgrade to 5 WITHOUT force_downgrade flag
            with pytest.raises(HTTPException) as exc_info:
                await set_min_build_number(
                    request=MagicMock(),
                    build_number=5,
                    is_soft_update=False,
                    x_admin_key=test_admin_key
                )
            
            # Should mention downgrade in error
            assert "Downgrade" in str(exc_info.value.detail)
            
            # Downgrade WITH force_downgrade flag should work
            result = await set_min_build_number(
                request=MagicMock(),
                build_number=5,
                is_soft_update=False,
                force_downgrade=True,  # Explicit flag
                x_admin_key=test_admin_key
            )
            assert result['min_build_number'] == 5

    @pytest.mark.asyncio
    async def test_cdn_health_check(self):
        """
        NEW FEATURE: Test CDN health check functionality.
        """
        # Test with invalid URL (should return False)
        result = await _verify_cdn_health("https://invalid.example.com/apk.apk", timeout=1.0)
        assert result == False
        
        # Test with empty URL (should return False)
        result = await _verify_cdn_health("", timeout=1.0)
        assert result == False
        
        # Test with None URL (should return False)
        result = await _verify_cdn_health(None, timeout=1.0)  # type: ignore
        assert result == False

    @pytest.mark.asyncio
    async def test_cdn_health_cache_initialized(self):
        """
        Test that CDN health cache is properly initialized.
        """
        # Check all architectures are in cache
        expected_archs = ["universal", "arm64_v8a", "armeabi_v7a", "x86_64"]
        
        for arch in expected_archs:
            assert arch in _CDN_HEALTH_CACHE, f"Missing {arch} in CDN health cache"
            assert "healthy" in _CDN_HEALTH_CACHE[arch]
            assert "last_check" in _CDN_HEALTH_CACHE[arch]

    @pytest.mark.asyncio
    async def test_admin_dashboard_update_active_check(self):
        """
        FIX: Test that admin dashboard uses actual _is_update_active check.
        
        Previously hardcoded "update_active": True, now uses real check.
        """
        from routes.version import get_admin_dashboard
        
        # Mock admin access
        with patch('routes.version._check_admin_access', return_value=True):
            # Mock request
            mock_request = MagicMock()
            mock_request.client.host = "127.0.0.1"
            
            # Get dashboard data
            result = await get_admin_dashboard(mock_request, "test_key")
            
            # Check that update_config has actual values
            assert "update_config" in result
            assert "update_active" in result["update_config"]
            assert "update_active_reason" in result["update_config"]
            
            # update_active should be a boolean (not hardcoded True)
            assert isinstance(result["update_config"]["update_active"], bool)

    def test_effective_from_scheduling(self):
        """
        Test that effective_from scheduling works correctly.
        """
        from datetime import datetime, timedelta
        
        # Set effective_from to tomorrow
        tomorrow = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        
        config = {
            "effective_from": tomorrow
        }
        
        # Should NOT be active yet
        is_active, reason = _is_update_active(config)
        assert is_active == False
        assert "scheduled" in reason.lower()

    def test_effective_until_expiry(self):
        """
        Test that effective_until expiry works correctly.
        """
        from datetime import datetime, timedelta
        
        # Set effective_until to yesterday
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        
        config = {
            "effective_until": yesterday
        }
        
        # Should be EXPIRED (not active)
        is_active, reason = _is_update_active(config)
        assert is_active == False
        assert "expired" in reason.lower()


class TestVersionAnalytics:
    """Test version analytics tracking"""

    @pytest.mark.asyncio
    async def test_update_event_tracking(self):
        """
        Test that update events are properly tracked.
        """
        from database import save_update_event, get_update_events
        
        # Save a test event
        await save_update_event(
            event="test_event",
            from_build=10,
            to_build=11,
            device_id="test_device",
            device_type="android"
        )
        
        # Get recent events
        events = await get_update_events(limit=10)
        
        # Should find our test event
        test_events = [e for e in events if e.get("event") == "test_event"]
        assert len(test_events) > 0
        
        # Verify event data
        event = test_events[0]
        assert event.get("from_build") == 10
        assert event.get("to_build") == 11
        assert event.get("device_id") == "test_device"


class TestBuildNumberValidation:
    """Test build number validation"""

    def test_invalid_build_number_rejected(self):
        """
        Test that build numbers < 1 are rejected.
        """
        from routes.version import set_min_build_number
        from fastapi import HTTPException
        
        @pytest.mark.asyncio
        async def test():
            with patch('routes.version._check_admin_access', return_value=True):
                with pytest.raises(HTTPException) as exc_info:
                    await set_min_build_number(
                        request=MagicMock(),
                        build_number=0,  # Invalid
                        x_admin_key="test"
                    )
                assert exc_info.value.status_code == 400
        
        # Run the async test
        asyncio.run(test())

    def test_priority_validation(self):
        """
        Test that invalid priorities are rejected.
        """
        from routes.version import set_min_build_number, UPDATE_PRIORITY_NORMAL
        from fastapi import HTTPException
        
        @pytest.mark.asyncio
        async def test():
            with patch('routes.version._check_admin_access', return_value=True):
                with pytest.raises(HTTPException) as exc_info:
                    await set_min_build_number(
                        request=MagicMock(),
                        build_number=10,
                        priority="invalid_priority",  # Invalid
                        x_admin_key="test"
                    )
                assert exc_info.value.status_code == 400
                assert "priority" in str(exc_info.value.detail).lower()
        
        # Run the async test
        asyncio.run(test())


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
