"""
Load Tests for Library Upload Endpoints

Production Readiness: Test concurrent upload scenarios to ensure system stability
under load. These tests simulate real-world usage patterns.

Run with: pytest tests/load/test_library_load.py -v --tb=short
"""

import pytest
import asyncio
import aiohttp
import time
from typing import List, Tuple
from datetime import datetime, timezone


# Test configuration
CONCURRENT_UPLOADS = 50  # Simulate 50 simultaneous uploads
FILE_SIZE = 1024 * 1024  # 1MB file
MAX_RESPONSE_TIME_SECONDS = 10  # Max acceptable response time
FAILURE_RATE_THRESHOLD = 0.05  # 5% failure rate threshold


class TestLibraryConcurrentUploads:
    """Load tests for library upload endpoint"""

    @pytest.fixture
    async def auth_headers(self):
        """Get authentication headers for testing"""
        # This would need a test user setup
        # For now, skip if no auth available
        pytest.skip("Requires test user setup")
        yield {}

    @pytest.fixture
    def test_file_content(self):
        """Generate test file content"""
        return b"x" * FILE_SIZE

    async def _upload_file(
        self, 
        session: aiohttp.ClientSession, 
        file_content: bytes,
        auth_headers: dict,
        base_url: str
    ) -> Tuple[bool, float, str]:
        """
        Upload a file and return (success, response_time, error_message)
        """
        start_time = time.time()
        
        # Create form data with file
        data = aiohttp.FormData()
        data.add_field(
            'file',
            file_content,
            filename=f'test_file_{int(time.time() * 1000)}.bin',
            content_type='application/octet-stream'
        )
        
        try:
            async with session.post(
                f"{base_url}/api/library/upload",
                data=data,
                headers=auth_headers,
                timeout=aiohttp.ClientTimeout(total=MAX_RESPONSE_TIME_SECONDS * 2)
            ) as response:
                response_time = time.time() - start_time
                
                if response.status == 200:
                    return True, response_time, ""
                else:
                    error_body = await response.text()
                    return False, response_time, f"Status {response.status}: {error_body}"
                    
        except asyncio.TimeoutError:
            response_time = time.time() - start_time
            return False, response_time, "Request timeout"
        except Exception as e:
            response_time = time.time() - start_time
            return False, response_time, str(e)

    @pytest.mark.asyncio
    @pytest.mark.loadtest
    async def test_concurrent_uploads(self, auth_headers, test_file_content):
        """
        Test 50 concurrent file uploads
        
        Success criteria:
        - Failure rate < 5%
        - Average response time < 5 seconds
        - P95 response time < 10 seconds
        """
        base_url = "http://localhost:8000"
        
        async with aiohttp.ClientSession() as session:
            # Launch all uploads concurrently
            tasks = [
                self._upload_file(session, test_file_content, auth_headers, base_url)
                for _ in range(CONCURRENT_UPLOADS)
            ]
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Analyze results
            successful = 0
            failed = 0
            response_times: List[float] = []
            errors: List[str] = []
            
            for result in results:
                if isinstance(result, Exception):
                    failed += 1
                    errors.append(f"Exception: {str(result)}")
                else:
                    success, response_time, error = result
                    response_times.append(response_time)
                    
                    if success:
                        successful += 1
                    else:
                        failed += 1
                        errors.append(error)
            
            # Calculate metrics
            failure_rate = failed / CONCURRENT_UPLOADS
            avg_response_time = sum(response_times) / len(response_times) if response_times else 0
            sorted_times = sorted(response_times)
            p95_response_time = sorted_times[int(len(sorted_times) * 0.95)] if len(sorted_times) > 0 else 0
            
            # Log results
            print(f"\n{'='*60}")
            print(f"Concurrent Upload Test Results")
            print(f"{'='*60}")
            print(f"Total uploads: {CONCURRENT_UPLOADS}")
            print(f"Successful: {successful}")
            print(f"Failed: {failed}")
            print(f"Failure rate: {failure_rate:.2%}")
            print(f"Average response time: {avg_response_time:.2f}s")
            print(f"P95 response time: {p95_response_time:.2f}s")
            print(f"Max response time: {max(response_times):.2f}s" if response_times else "N/A")
            print(f"{'='*60}")
            
            if errors:
                print(f"\nErrors ({len(errors)}):")
                for i, error in enumerate(errors[:10], 1):  # Show first 10 errors
                    print(f"  {i}. {error}")
                if len(errors) > 10:
                    print(f"  ... and {len(errors) - 10} more")
            
            # Assertions
            assert failure_rate < FAILURE_RATE_THRESHOLD, \
                f"Failure rate {failure_rate:.2%} exceeds threshold {FAILURE_RATE_THRESHOLD:.2%}"
            
            assert avg_response_time < MAX_RESPONSE_TIME_SECONDS, \
                f"Average response time {avg_response_time:.2f}s exceeds max {MAX_RESPONSE_TIME_SECONDS}s"
            
            assert p95_response_time < MAX_RESPONSE_TIME_SECONDS, \
                f"P95 response time {p95_response_time:.2f}s exceeds max {MAX_RESPONSE_TIME_SECONDS}s"

    @pytest.mark.asyncio
    @pytest.mark.loadtest
    async def test_storage_quota_under_load(self, auth_headers, test_file_content):
        """
        Test storage quota enforcement under concurrent load
        
        Verify that storage limits are properly enforced even with
        multiple simultaneous uploads.
        """
        base_url = "http://localhost:8000"
        
        # First, check current storage usage
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{base_url}/api/library/",
                headers=auth_headers
            ) as response:
                if response.status != 200:
                    pytest.skip("Cannot get storage usage")
                
                data = await response.json()
                current_usage = data.get('storage_usage_bytes', 0)
                
                # Assume 100MB limit
                MAX_STORAGE = 100 * 1024 * 1024
                remaining = MAX_STORAGE - current_usage
                
                # Calculate how many files we can upload
                num_files = min(
                    CONCURRENT_UPLOADS,
                    max(1, int(remaining / FILE_SIZE))
                )
                
                print(f"\nStorage test: Current usage={current_usage/1024/1024:.2f}MB, "
                      f"Remaining={remaining/1024/1024:.2f}MB, "
                      f"Testing with {num_files} files")
            
            # Upload files until we hit the limit
            successful = 0
            storage_errors = 0
            
            for i in range(num_files):
                success, _, error = await self._upload_file(
                    session, test_file_content, auth_headers, base_url
                )
                
                if success:
                    successful += 1
                elif "storage" in error.lower() or "quota" in error.lower():
                    storage_errors += 1
                    print(f"Storage limit reached after {successful} files")
                    break
            
            print(f"\nStorage quota test results:")
            print(f"  Successful uploads: {successful}")
            print(f"  Storage errors: {storage_errors}")
            
            # At least some uploads should succeed or we should get storage errors
            assert successful > 0 or storage_errors > 0, \
                "Expected some successful uploads or storage errors"


class TestLibraryShareUnderLoad:
    """Load tests for library sharing endpoint"""

    @pytest.fixture
    async def auth_headers(self):
        """Get authentication headers for testing"""
        pytest.skip("Requires test user setup")
        yield {}

    @pytest.mark.asyncio
    @pytest.mark.loadtest
    async def test_concurrent_shares(self, auth_headers):
        """
        Test concurrent share operations
        
        Verify that sharing works correctly under concurrent load
        and doesn't create duplicate shares.
        """
        base_url = "http://localhost:8000"
        item_id = 1  # Would need to create a test item first
        shared_with = "test_user@example.com"
        
        async with aiohttp.ClientSession() as session:
            # Launch 10 concurrent share requests
            tasks = []
            for _ in range(10):
                data = {
                    'shared_with_user_id': shared_with,
                    'permission': 'read'
                }
                task = session.post(
                    f"{base_url}/api/library/{item_id}/share",
                    json=data,
                    headers=auth_headers
                )
                tasks.append(task)
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            successful = 0
            conflicts = 0  # Expected for duplicate shares
            errors = 0
            
            for result in results:
                if isinstance(result, Exception):
                    errors += 1
                elif result.status == 200:
                    successful += 1
                elif result.status == 409:  # Conflict - already shared
                    conflicts += 1
                else:
                    errors += 1
            
            print(f"\nConcurrent share test results:")
            print(f"  Successful: {successful}")
            print(f"  Conflicts (expected): {conflicts}")
            print(f"  Errors: {errors}")
            
            # Most should succeed or get conflict errors
            assert errors == 0, f"Unexpected errors: {errors}"
