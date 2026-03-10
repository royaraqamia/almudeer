"""
Share System Verification Script
Tests all critical share functionality without pytest dependencies
"""

import asyncio
import sys
import os

# Set required environment variables
os.environ["TESTING"] = "1"
os.environ["DB_TYPE"] = "sqlite"
os.environ["ENCRYPTION_KEY"] = "test-encryption-key-32-chars-min"
os.environ["JWT_SECRET_KEY"] = "test-jwt-secret-key-at-least-32-chars"
os.environ["ADMIN_KEY"] = "test-admin-key"

async def verify_imports():
    """Verify all share system modules import correctly"""
    print("=" * 60)
    print("VERIFYING SHARE SYSTEM IMPORTS")
    print("=" * 60)
    
    try:
        from models.task_shares import share_task, get_shared_tasks, remove_share
        print("✓ models.task_shares imported successfully")
    except Exception as e:
        print(f"✗ models.task_shares import failed: {e}")
        return False
    
    try:
        from models.library_advanced import share_item, get_shared_items, remove_share as lib_remove_share
        print("✓ models.library_advanced imported successfully")
    except Exception as e:
        print(f"✗ models.library_advanced import failed: {e}")
        return False
    
    try:
        from models.tasks import can_edit_task, can_delete_task, can_comment_on_task
        print("✓ models.tasks permission functions imported successfully")
    except Exception as e:
        print(f"✗ models.tasks import failed: {e}")
        return False
    
    try:
        from utils.permissions import (
            PermissionLevel, ResourceAction, can_perform_action,
            get_effective_permission, can_share, can_manage_shares
        )
        print("✓ utils.permissions imported successfully")
    except Exception as e:
        print(f"✗ utils.permissions import failed: {e}")
        return False
    
    try:
        from utils.share_utils import validate_share_permission, resolve_username_to_user_id
        print("✓ utils.share_utils imported successfully")
    except Exception as e:
        print(f"✗ utils.share_utils import failed: {e}")
        return False
    
    return True


def verify_permission_logic():
    """Verify permission logic works correctly"""
    print("\n" + "=" * 60)
    print("VERIFYING PERMISSION LOGIC")
    print("=" * 60)
    
    from utils.permissions import (
        can_view, can_edit, can_share, can_delete, can_manage_shares,
        get_effective_permission, PermissionLevel
    )
    
    # Test read permission
    assert can_view(PermissionLevel.READ) == True, "Read should view"
    assert can_edit(PermissionLevel.READ) == False, "Read should not edit"
    assert can_share(PermissionLevel.READ) == False, "Read should not share"
    assert can_delete(PermissionLevel.READ) == False, "Read should not delete"
    print("✓ Read permission logic correct")
    
    # Test edit permission
    assert can_view(PermissionLevel.EDIT) == True, "Edit should view"
    assert can_edit(PermissionLevel.EDIT) == True, "Edit should edit"
    assert can_share(PermissionLevel.EDIT) == True, "Edit should share"
    assert can_delete(PermissionLevel.EDIT) == False, "Edit should not delete"
    print("✓ Edit permission logic correct")
    
    # Test admin permission
    assert can_view(PermissionLevel.ADMIN) == True, "Admin should view"
    assert can_edit(PermissionLevel.ADMIN) == True, "Admin should edit"
    assert can_share(PermissionLevel.ADMIN) == True, "Admin should share"
    assert can_delete(PermissionLevel.ADMIN) == True, "Admin should delete"
    assert can_manage_shares(PermissionLevel.ADMIN) == True, "Admin should manage shares"
    print("✓ Admin permission logic correct")
    
    # Test effective permission
    assert get_effective_permission('read', False) == PermissionLevel.READ
    assert get_effective_permission('edit', False) == PermissionLevel.EDIT
    assert get_effective_permission('admin', False) == PermissionLevel.ADMIN
    assert get_effective_permission(None, True) == PermissionLevel.OWNER
    print("✓ Effective permission logic correct")
    
    return True


async def verify_cache_integrity():
    """Verify cache functions work correctly"""
    print("\n" + "=" * 60)
    print("VERIFYING CACHE INTEGRITY")
    print("=" * 60)

    from utils.cache_utils import get_shared_tasks_cache, reset_caches
    
    # Reset caches for testing
    reset_caches()
    cache = get_shared_tasks_cache()
    
    # Test cache set/get
    await cache.set("test_key", {"data": "test_value"})
    result = await cache.get("test_key")
    assert result == {"data": "test_value"}, "Cache set/get failed"
    print("✓ Cache set/get works correctly")
    
    # Test cache expiration
    from utils.cache_utils import LRUCache
    test_cache = LRUCache(name="test", ttl_seconds=0, max_size=10)
    await test_cache.set("expire_key", "value")
    import asyncio
    await asyncio.sleep(0.1)  # Wait for expiration
    result = await test_cache.get("expire_key")
    assert result is None, "Cache expiration failed"
    print("✓ Cache expiration works correctly")
    
    # Test cache invalidation
    await cache.set("1|user1|all", {"data": []})
    await cache.set("1|user2|all", {"data": []})
    await cache.invalidate("1|user1|all")
    
    result1 = await cache.get("1|user1|all")
    result2 = await cache.get("1|user2|all")

    assert result1 is None, "Should invalidate specific key"
    assert result2 is not None, "Should keep other keys"
    print("✓ Cache invalidation works correctly")

    # Test prefix invalidation
    # Note: cache still has "test_key" from earlier test, so we check for that
    await cache.invalidate_prefix("1|")
    # After invalidating "1|" prefix, only "test_key" should remain
    assert len(cache._cache) == 1, f"Should have 1 entry remaining (test_key), but has {len(cache._cache)}"
    assert "test_key" in cache._cache, "Should keep test_key"
    print("✓ Prefix invalidation works correctly")
    
    # Test LRU eviction
    small_cache = LRUCache(name="small_test", ttl_seconds=300, max_size=3)
    await small_cache.set("key1", "value1")
    import asyncio
    await asyncio.sleep(0.01)  # Small delay to ensure different timestamps
    await small_cache.set("key2", "value2")
    await asyncio.sleep(0.01)
    await small_cache.set("key3", "value3")
    await asyncio.sleep(0.01)
    # Access key1 to make it recently used
    await small_cache.get("key1")
    await asyncio.sleep(0.01)
    # Add key4, should evict key2 (least recently used)
    await small_cache.set("key4", "value4")

    assert await small_cache.get("key1") is not None, "Should keep recently accessed key1"
    assert await small_cache.get("key2") is None, "Should evict LRU key2"
    assert await small_cache.get("key3") is not None, "Should keep key3"
    assert await small_cache.get("key4") is not None, "Should keep new key4"
    print("✓ LRU eviction works correctly")
    
    # Test stats
    stats = cache.get_stats()
    assert "hits" in stats, "Stats should include hits"
    assert "misses" in stats, "Stats should include misses"
    assert "hit_rate_percent" in stats, "Stats should include hit rate"
    print("✓ Cache statistics work correctly")

    # Test batch invalidation (NEW FEATURE)
    batch_cache = LRUCache(name="batch_test", ttl_seconds=300, max_size=100)
    await batch_cache.set("license1|user1|read", {"data": "1"})
    await batch_cache.set("license1|user1|edit", {"data": "2"})
    await batch_cache.set("license1|user2|read", {"data": "3"})
    await batch_cache.set("license2|user1|read", {"data": "4"})
    
    # Batch invalidate specific keys
    await batch_cache.invalidate_batch(["license1|user1|read", "license1|user1|edit"])
    
    assert await batch_cache.get("license1|user1|read") is None, "Should invalidate batch key 1"
    assert await batch_cache.get("license1|user1|edit") is None, "Should invalidate batch key 2"
    assert await batch_cache.get("license1|user2|read") is not None, "Should keep other key"
    assert await batch_cache.get("license2|user1|read") is not None, "Should keep other license"
    print("✓ Batch cache invalidation works correctly")

    return True


def verify_error_sanitization():
    """Verify error sanitization helper functions"""
    print("\n" + "=" * 60)
    print("VERIFYING ERROR SANITIZATION")
    print("=" * 60)
    
    from routes.tasks import _get_share_error_arabic
    
    # Test error message translations
    assert 'لا يمكنك' in _get_share_error_arabic('Cannot share with yourself')
    print("✓ Self-share error sanitized")
    
    assert 'تم إلغاء' in _get_share_error_arabic('Share was revoked')
    print("✓ Revoked share error sanitized")
    
    assert 'غير موجودة' in _get_share_error_arabic('Task not found')
    print("✓ Not found error sanitized")
    
    return True


async def main():
    """Run all verifications"""
    print("\n")
    print("╔" + "=" * 58 + "╗")
    print("║" + " " * 10 + "SHARE SYSTEM VERIFICATION" + " " * 21 + "║")
    print("╚" + "=" * 58 + "╝")
    print()
    
    all_passed = True
    
    # 1. Verify imports
    if not await verify_imports():
        print("\n✗ IMPORT VERIFICATION FAILED")
        all_passed = False
    else:
        print("\n✓ IMPORT VERIFICATION PASSED")
    
    # 2. Verify permission logic
    try:
        if not verify_permission_logic():
            print("\n✗ PERMISSION LOGIC VERIFICATION FAILED")
            all_passed = False
        else:
            print("\n✓ PERMISSION LOGIC VERIFICATION PASSED")
    except Exception as e:
        print(f"\n✗ PERMISSION LOGIC VERIFICATION FAILED: {e}")
        all_passed = False
    
    # 3. Verify cache integrity
    try:
        if not await verify_cache_integrity():
            print("\n✗ CACHE INTEGRITY VERIFICATION FAILED")
            all_passed = False
        else:
            print("\n✓ CACHE INTEGRITY VERIFICATION PASSED")
    except Exception as e:
        print(f"\n✗ CACHE INTEGRITY VERIFICATION FAILED: {e}")
        all_passed = False
    
    # 4. Verify error sanitization
    try:
        if not verify_error_sanitization():
            print("\n✗ ERROR SANITIZATION VERIFICATION FAILED")
            all_passed = False
        else:
            print("\n✓ ERROR SANITIZATION VERIFICATION PASSED")
    except Exception as e:
        print(f"\n✗ ERROR SANITIZATION VERIFICATION FAILED: {e}")
        all_passed = False
    
    # Final result
    print("\n" + "=" * 60)
    if all_passed:
        print("║  ✓ ALL VERIFICATIONS PASSED - SHARE SYSTEM IS 10/10!  ║")
    else:
        print("║  ✗ SOME VERIFICATIONS FAILED                           ║")
    print("=" * 60)
    
    return 0 if all_passed else 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
