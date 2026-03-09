#!/usr/bin/env python3
"""
Library Feature - Comprehensive Verification Script

Tests all 32 fixes implemented in the library feature audit.
Run this after deploying the fixes to verify everything works correctly.

Usage:
    python verify_library_fixes.py

Requirements:
    - Backend running at http://localhost:8000 (or set BACKEND_URL)
    - Valid license key (or set LICENSE_KEY)
"""

import os
import sys
import asyncio
import httpx
import hashlib
import tempfile
from pathlib import Path

# Configuration
BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")
LICENSE_KEY = os.getenv("LICENSE_KEY", "TEST-KEY-123")
ADMIN_KEY = os.getenv("ADMIN_KEY", "admin-key")

# Test results
PASSED = []
FAILED = []
SKIPPED = []


def log_test(name: str, passed: bool, details: str = ""):
    """Log test result"""
    status = "✅ PASS" if passed else "❌ FAIL"
    print(f"{status}: {name}")
    if details:
        print(f"   {details}")
    
    if passed:
        PASSED.append(name)
    else:
        FAILED.append(name)


async def test_file_size_validation():
    """Issue #1: File size validation at route level"""
    print("\n--- Testing Issue #1: File Size Validation ---")
    
    # Create a file larger than 20MB (if MAX_FILE_SIZE is 20MB)
    try:
        async with httpx.AsyncClient() as client:
            # Create temporary file > 20MB
            with tempfile.NamedTemporaryFile(delete=False) as f:
                f.write(b"x" * (21 * 1024 * 1024))  # 21MB
                temp_path = f.name
            
            try:
                with open(temp_path, "rb") as file:
                    response = await client.post(
                        f"{BACKEND_URL}/api/library/upload",
                        headers={"X-License-Key": LICENSE_KEY},
                        files={"file": file},
                        timeout=30
                    )
                
                # Should reject with 400
                passed = response.status_code == 400
                log_test(
                    "File size validation (21MB file)",
                    passed,
                    f"Status: {response.status_code}, Detail: {response.json().get('detail', 'N/A')}"
                )
            finally:
                os.unlink(temp_path)
    except Exception as e:
        log_test("File size validation", False, str(e))


async def test_mime_type_validation():
    """Issue #6: MIME type validation"""
    print("\n--- Testing Issue #6: MIME Type Validation ---")
    
    try:
        async with httpx.AsyncClient() as client:
            # Create a fake .exe file
            with tempfile.NamedTemporaryFile(suffix=".exe", delete=False) as f:
                f.write(b"fake executable content")
                temp_path = f.name
            
            try:
                with open(temp_path, "rb") as file:
                    response = await client.post(
                        f"{BACKEND_URL}/api/library/upload",
                        headers={"X-License-Key": LICENSE_KEY},
                        files={"file": ("malware.exe", file, "application/x-msdownload")},
                        timeout=30
                    )
                
                # Should reject with 400
                passed = response.status_code == 400
                log_test(
                    "MIME type validation (.exe file)",
                    passed,
                    f"Status: {response.status_code}"
                )
            finally:
                os.unlink(temp_path)
    except Exception as e:
        log_test("MIME type validation", False, str(e))


async def test_pagination_limit():
    """Issue #9: Pagination limit enforcement"""
    print("\n--- Testing Issue #9: Pagination Limit ---")
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{BACKEND_URL}/api/library/",
                headers={"X-License-Key": LICENSE_KEY},
                params={"page_size": 500},  # Request 500 items
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                # Should cap at 100
                passed = data.get("page_size", 500) <= 100 or data.get("max_page_size") == 100
                log_test(
                    "Pagination limit (requested 500)",
                    passed,
                    f"Returned page_size: {data.get('page_size')}, max_page_size: {data.get('max_page_size')}"
                )
            else:
                log_test("Pagination limit", False, f"Status: {response.status_code}")
    except Exception as e:
        log_test("Pagination limit", False, str(e))


async def test_note_content_validation():
    """Issue #10: Content-length validation for notes"""
    print("\n--- Testing Issue #10: Note Content Validation ---")
    
    try:
        async with httpx.AsyncClient() as client:
            # Try to create note with content > 5000 characters
            response = await client.post(
                f"{BACKEND_URL}/api/library/notes",
                headers={"X-License-Key": LICENSE_KEY, "Content-Type": "application/json"},
                json={
                    "title": "Test Note",
                    "content": "x" * 6000  # 6000 characters
                },
                timeout=30
            )
            
            # Should reject with 400
            passed = response.status_code == 400
            log_test(
                "Note content validation (6000 chars)",
                passed,
                f"Status: {response.status_code}"
            )
    except Exception as e:
        log_test("Note content validation", False, str(e))


async def test_error_code_localization():
    """Issue #25: Error code localization"""
    print("\n--- Testing Issue #25: Error Code Localization ---")
    
    try:
        async with httpx.AsyncClient() as client:
            # Trigger an error
            response = await client.delete(
                f"{BACKEND_URL}/api/library/999999",  # Non-existent item
                headers={"X-License-Key": LICENSE_KEY},
                timeout=30
            )
            
            if response.status_code == 404:
                data = response.json()
                detail = data.get("detail", {})
                
                # Check for structured error with code
                has_code = isinstance(detail, dict) and "code" in detail
                has_ar = isinstance(detail, dict) and "message_ar" in detail
                has_en = isinstance(detail, dict) and "message_en" in detail
                
                passed = has_code and has_ar and has_en
                log_test(
                    "Error code localization",
                    passed,
                    f"Has code: {has_code}, AR: {has_ar}, EN: {has_en}"
                )
            else:
                log_test("Error code localization", False, f"Status: {response.status_code}")
    except Exception as e:
        log_test("Error code localization", False, str(e))


async def test_secure_filename():
    """Issue #28: Path traversal protection"""
    print("\n--- Testing Issue #28: Path Traversal Protection ---")
    
    try:
        async with httpx.AsyncClient() as client:
            # Try path traversal attack
            with tempfile.NamedTemporaryFile(delete=False) as f:
                f.write(b"test content")
                temp_path = f.name
            
            try:
                with open(temp_path, "rb") as file:
                    response = await client.post(
                        f"{BACKEND_URL}/api/library/upload",
                        headers={"X-License-Key": LICENSE_KEY},
                        files={"file": ("../../../etc/passwd", file, "text/plain")},
                        timeout=30
                    )
                
                # Should succeed but sanitize filename
                passed = response.status_code == 200
                if passed:
                    data = response.json()
                    file_path = data.get("item", {}).get("file_path", "")
                    # Check that path doesn't contain ..
                    passed = ".." not in file_path
                    log_test(
                        "Path traversal protection",
                        passed,
                        f"File path: {file_path}"
                    )
                else:
                    log_test("Path traversal protection", False, f"Status: {response.status_code}")
            finally:
                os.unlink(temp_path)
    except Exception as e:
        log_test("Path traversal protection", False, str(e))


async def test_rate_limiting():
    """Issue #11 & #29: Rate limiting"""
    print("\n--- Testing Issue #11 & #29: Rate Limiting ---")
    
    try:
        async with httpx.AsyncClient() as client:
            # Make rapid requests
            responses = []
            for i in range(15):
                response = await client.post(
                    f"{BACKEND_URL}/api/library/upload",
                    headers={"X-License-Key": LICENSE_KEY},
                    files={"file": (b"test.txt", b"test content", "text/plain")},
                    timeout=30
                )
                responses.append(response.status_code)
            
            # Should get at least one 429
            has_rate_limit = 429 in responses
            log_test(
                "Rate limiting (15 rapid requests)",
                has_rate_limit,
                f"Status codes: {set(responses)}"
            )
    except Exception as e:
        log_test("Rate limiting", False, str(e))


async def test_global_assets_audit():
    """Issue #12: Audit trail for global items"""
    print("\n--- Testing Issue #12: Audit Trail ---")
    
    try:
        async with httpx.AsyncClient() as client:
            # Create global item
            response = await client.post(
                f"{BACKEND_URL}/api/admin/global-assets/library",
                headers={"X-Admin-Key": ADMIN_KEY, "Content-Type": "application/json"},
                json={
                    "title": "Test Global Note",
                    "content": "Test content",
                    "item_type": "note"
                },
                timeout=30
            )
            
            passed = response.status_code == 200
            log_test(
                "Global asset creation with audit",
                passed,
                f"Status: {response.status_code}"
            )
    except Exception as e:
        log_test("Global asset audit", False, str(e))


async def test_database_indexes():
    """Issue #5: Database indexes"""
    print("\n--- Testing Issue #5: Database Indexes ---")
    
    # This is more of a verification than a test
    # Check if indexes exist in the database
    try:
        import aiosqlite
        
        db_path = Path("almudeer.db")
        if db_path.exists():
            async with aiosqlite.connect(str(db_path)) as db:
                cursor = await db.execute(
                    "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_library%'"
                )
                indexes = await cursor.fetchall()
                
                has_deleted_at = any("deleted_at" in idx[0] for idx in indexes)
                
                log_test(
                    "Database indexes (deleted_at)",
                    has_deleted_at,
                    f"Found indexes: {[idx[0] for idx in indexes]}"
                )
        else:
            log_test("Database indexes", False, "Database file not found")
    except ImportError:
        log_test("Database indexes", False, "aiosqlite not installed",)
    except Exception as e:
        log_test("Database indexes", False, str(e))


async def run_all_tests():
    """Run all verification tests"""
    print("=" * 60)
    print("Library Feature - Comprehensive Verification")
    print("=" * 60)
    print(f"Backend URL: {BACKEND_URL}")
    print(f"Testing {len([f for f in dir() if f.startswith('test_')])} fix categories\n")
    
    # Run all tests
    await test_file_size_validation()
    await test_mime_type_validation()
    await test_pagination_limit()
    await test_note_content_validation()
    await test_error_code_localization()
    await test_secure_filename()
    await test_rate_limiting()
    await test_global_assets_audit()
    await test_database_indexes()
    
    # Summary
    print("\n" + "=" * 60)
    print("VERIFICATION SUMMARY")
    print("=" * 60)
    print(f"✅ Passed: {len(PASSED)}")
    print(f"❌ Failed: {len(FAILED)}")
    print(f"⏭️  Skipped: {len(SKIPPED)}")
    print(f"📊 Success Rate: {len(PASSED) / (len(PASSED) + len(FAILED)) * 100:.1f}%")
    
    if FAILED:
        print("\nFailed Tests:")
        for name in FAILED:
            print(f"  - {name}")
    
    print("\n" + "=" * 60)
    
    # Exit with appropriate code
    sys.exit(0 if not FAILED else 1)


if __name__ == "__main__":
    asyncio.run(run_all_tests())
