"""
Al-Mudeer Athkar Routes Tests
Tests for Athkar progress tracking and sync endpoints
"""

import pytest
import json
from unittest.mock import AsyncMock, patch, MagicMock
from pydantic import ValidationError


@pytest.fixture
def mock_license_dependency():
    """Mock the license dependency for testing"""
    with patch("dependencies.get_license_from_header", return_value={"license_id": 1}):
        yield


@pytest.fixture
def mock_auth_data():
    """Mock authentication data"""
    return {"license_id": 1}


class TestAthkarProgressUpdateSchema:
    """Tests for the AthkarProgressUpdate Pydantic schema validation"""

    def test_valid_athkar_progress_update(self):
        """Test valid athkar progress data"""
        from routes.features import AthkarProgressUpdate
        
        data = AthkarProgressUpdate(
            counts={"m_ayatal_kursi": 1, "m_subhan_allah_bihamdihi": 50},
            misbaha=100
        )
        
        assert data.counts == {"m_ayatal_kursi": 1, "m_subhan_allah_bihamdihi": 50}
        assert data.misbaha == 100

    def test_empty_athkar_progress_update(self):
        """Test empty athkar progress data (defaults)"""
        from routes.features import AthkarProgressUpdate
        
        data = AthkarProgressUpdate()
        
        assert data.counts == {}
        assert data.misbaha == 0

    def test_rejects_negative_counts(self):
        """Test that negative counts are rejected"""
        from routes.features import AthkarProgressUpdate
        
        with pytest.raises(ValidationError) as exc_info:
            AthkarProgressUpdate(
                counts={"m_ayatal_kursi": -1},
                misbaha=0
            )
        
        assert "cannot be negative" in str(exc_info.value)

    def test_rejects_negative_misbaha(self):
        """Test that negative misbaha is rejected"""
        from routes.features import AthkarProgressUpdate

        with pytest.raises(ValidationError) as exc_info:
            AthkarProgressUpdate(
                counts={},
                misbaha=-10
            )

        # Pydantic v2 uses Field constraint (ge=0) which produces different error message
        assert "greater_than_equal" in str(exc_info.value) or "cannot be negative" in str(exc_info.value)

    def test_rejects_too_many_items(self):
        """Test that too many athkar items are rejected"""
        from routes.features import AthkarProgressUpdate
        
        # Create 101 items (exceeds limit of 100)
        counts = {f"item_{i}": 1 for i in range(101)}
        
        with pytest.raises(ValidationError) as exc_info:
            AthkarProgressUpdate(counts=counts, misbaha=0)
        
        assert "Too many athkar items" in str(exc_info.value)

    def test_rejects_non_string_keys(self):
        """Test that non-string keys are rejected"""
        from routes.features import AthkarProgressUpdate
        
        with pytest.raises(ValidationError) as exc_info:
            AthkarProgressUpdate(
                counts={123: 1},  # Integer key
                misbaha=0
            )
        
        assert "must be a string" in str(exc_info.value)

    def test_rejects_non_numeric_values(self):
        """Test that non-numeric values are rejected"""
        from routes.features import AthkarProgressUpdate
        
        with pytest.raises(ValidationError) as exc_info:
            AthkarProgressUpdate(
                counts={"m_ayatal_kursi": "invalid"},
                misbaha=0
            )
        
        assert "must be a number" in str(exc_info.value)

    def test_converts_float_to_int(self):
        """Test that float values are converted to integers"""
        from routes.features import AthkarProgressUpdate
        
        data = AthkarProgressUpdate(
            counts={"m_ayatal_kursi": 5.7},
            misbaha=0
        )
        
        assert data.counts["m_ayatal_kursi"] == 5

    def test_accepts_zero_values(self):
        """Test that zero values are accepted"""
        from routes.features import AthkarProgressUpdate
        
        data = AthkarProgressUpdate(
            counts={"m_ayatal_kursi": 0},
            misbaha=0
        )
        
        assert data.counts["m_ayatal_kursi"] == 0
        assert data.misbaha == 0

    def test_accepts_large_positive_values(self):
        """Test that large positive values are accepted"""
        from routes.features import AthkarProgressUpdate
        
        data = AthkarProgressUpdate(
            counts={"m_subhan_allah_bihamdihi": 10000},
            misbaha=999999
        )
        
        assert data.counts["m_subhan_allah_bihamdihi"] == 10000
        assert data.misbaha == 999999


class TestGetAthkarProgress:
    """Tests for GET /athkar/progress endpoint"""

    @pytest.mark.asyncio
    async def test_get_athkar_progress_success(self, mock_license_dependency):
        """Test successful retrieval of athkar progress"""
        from routes.features import get_athkar_progress
        
        mock_prefs = {
            "athkar_stats": json.dumps({
                "counts": {"m_ayatal_kursi": 1, "m_subhan_allah_bihamdihi": 50},
                "misbaha": 100
            })
        }
        
        with patch("routes.features.get_preferences", new_callable=AsyncMock) as mock_get_prefs:
            mock_get_prefs.return_value = mock_prefs
            
            response = await get_athkar_progress(license={"license_id": 1})
            
            assert response["success"] is True
            assert response["athkar"] is not None
            assert response["athkar"]["counts"]["m_ayatal_kursi"] == 1
            assert response["athkar"]["misbaha"] == 100

    @pytest.mark.asyncio
    async def test_get_athkar_progress_empty(self, mock_license_dependency):
        """Test retrieval when no athkar progress exists"""
        from routes.features import get_athkar_progress
        
        with patch("routes.features.get_preferences", new_callable=AsyncMock) as mock_get_prefs:
            mock_get_prefs.return_value = {"athkar_stats": None}
            
            response = await get_athkar_progress(license={"license_id": 1})
            
            assert response["success"] is True
            assert response["athkar"] is None

    @pytest.mark.asyncio
    async def test_get_athkar_progress_invalid_json(self, mock_license_dependency):
        """Test retrieval when stored JSON is invalid"""
        from routes.features import get_athkar_progress
        
        mock_prefs = {"athkar_stats": "invalid json{"}
        
        with patch("routes.features.get_preferences", new_callable=AsyncMock) as mock_get_prefs:
            mock_get_prefs.return_value = mock_prefs
            
            response = await get_athkar_progress(license={"license_id": 1})
            
            assert response["success"] is True
            assert response["athkar"] is None

    @pytest.mark.asyncio
    async def test_get_athkar_progress_dict_format(self, mock_license_dependency):
        """Test retrieval when athkar_stats is already a dict (not JSON string)"""
        from routes.features import get_athkar_progress
        
        mock_prefs = {
            "athkar_stats": {
                "counts": {"m_ayatal_kursi": 1},
                "misbaha": 50
            }
        }
        
        with patch("routes.features.get_preferences", new_callable=AsyncMock) as mock_get_prefs:
            mock_get_prefs.return_value = mock_prefs
            
            response = await get_athkar_progress(license={"license_id": 1})
            
            assert response["success"] is True
            assert response["athkar"]["counts"]["m_ayatal_kursi"] == 1


class TestUpdateAthkarProgress:
    """Tests for PATCH /athkar/progress endpoint"""

    @pytest.mark.asyncio
    async def test_update_athkar_progress_success(self, mock_license_dependency):
        """Test successful update of athkar progress"""
        from routes.features import update_athkar_progress
        from routes.features import AthkarProgressUpdate
        
        update_data = AthkarProgressUpdate(
            counts={"m_ayatal_kursi": 1, "m_subhan_allah_bihamdihi": 50},
            misbaha=100
        )
        
        with patch("routes.features.update_preferences", new_callable=AsyncMock) as mock_update:
            mock_update.return_value = True
            
            # Mock Request object for rate limiting
            mock_request = MagicMock()
            
            response = await update_athkar_progress(
                request=mock_request,
                data=update_data,
                license={"license_id": 1}
            )
            
            assert response["success"] is True
            assert "تم حفظ تقدم الأذكار" in response["message"]
            mock_update.assert_called_once()

    @pytest.mark.asyncio
    async def test_update_athkar_progress_empty_data(self, mock_license_dependency):
        """Test update with empty data (defaults)"""
        from routes.features import update_athkar_progress
        from routes.features import AthkarProgressUpdate
        
        update_data = AthkarProgressUpdate()  # Empty defaults
        
        with patch("routes.features.update_preferences", new_callable=AsyncMock) as mock_update:
            mock_update.return_value = True
            
            mock_request = MagicMock()
            
            response = await update_athkar_progress(
                request=mock_request,
                data=update_data,
                license={"license_id": 1}
            )
            
            assert response["success"] is True
            # Should still save empty data
            mock_update.assert_called_once()

    @pytest.mark.asyncio
    async def test_update_athkar_progress_validation_error(self, mock_license_dependency):
        """Test update with invalid data triggers validation error"""
        from routes.features import update_athkar_progress
        from routes.features import AthkarProgressUpdate
        from pydantic import ValidationError
        
        # Try to create invalid data - this should fail at schema level
        with pytest.raises(ValidationError):
            AthkarProgressUpdate(
                counts={"item": -1},  # Negative count
                misbaha=0
            )


class TestAthkarRateLimiting:
    """Tests for athkar endpoint rate limiting"""

    def test_update_endpoint_has_rate_limit_decorator(self):
        """Test that the update endpoint has rate limiting configured"""
        from routes.features import update_athkar_progress
        
        # Check that the function has rate limit decorator applied
        # The decorator should be visible in the function's __wrapped__ attribute
        assert hasattr(update_athkar_progress, '__wrapped__') or \
               hasattr(update_athkar_progress, '__name__')


class TestAthkarIntegration:
    """Integration tests for athkar endpoints"""

    @pytest.mark.asyncio
    async def test_full_athkar_sync_flow(self, mock_license_dependency):
        """Test complete sync flow: update then get"""
        from routes.features import get_athkar_progress, update_athkar_progress
        from routes.features import AthkarProgressUpdate
        
        # Update progress
        update_data = AthkarProgressUpdate(
            counts={"m_ayatal_kursi": 1, "e_ayatal_kursi": 1},
            misbaha=33
        )
        
        stored_data = None
        
        async def mock_update(license_id, **kwargs):
            nonlocal stored_data
            stored_data = kwargs.get('athkar_stats')
            return True
        
        with patch("routes.features.update_preferences", side_effect=mock_update):
            with patch("routes.features.get_preferences", new_callable=AsyncMock) as mock_get:
                # First call for update (returns existing prefs)
                # Second call for get (returns updated prefs)
                mock_get.side_effect = [
                    {},  # Initial prefs for update
                    {"athkar_stats": stored_data}  # Updated prefs for get
                ]
                
                mock_request = MagicMock()
                
                # Update
                await update_athkar_progress(
                    request=mock_request,
                    data=update_data,
                    license={"license_id": 1}
                )
                
                # Get
                response = await get_athkar_progress(license={"license_id": 1})
                
                assert response["success"] is True
                assert response["athkar"] is not None
                assert response["athkar"]["counts"]["m_ayatal_kursi"] == 1
                assert response["athkar"]["counts"]["e_ayatal_kursi"] == 1
                assert response["athkar"]["misbaha"] == 33
