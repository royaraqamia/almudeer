"""
Al-Mudeer Calculator Preferences Tests
Tests for calculator history validation and preferences endpoints
"""

import pytest
import json
from unittest.mock import AsyncMock, patch


@pytest.fixture
def mock_license_dependency():
    """Mock license dependency for testing"""
    with patch("dependencies.get_license_from_header", return_value={"license_id": 1}):
        yield


@pytest.fixture
def mock_db_session():
    """Mock database session"""
    mock_db = AsyncMock()
    with patch("db_helper.get_db") as mock_get_db:
        mock_get_db.return_value.__aenter__.return_value = mock_db
        yield mock_db


class TestCalculatorHistoryValidation:
    """Tests for calculator history length validation"""

    @pytest.mark.asyncio
    async def test_valid_calculator_history_list(self, mock_license_dependency):
        """Test that valid calculator history (under 50 entries) is accepted"""
        from routes.features import PreferencesUpdate

        history = ["1+1 = 2", "2+2 = 4", "3+3 = 6"]
        data = PreferencesUpdate(calculator_history=history)

        assert data.calculator_history == history

    @pytest.mark.asyncio
    async def test_calculator_history_at_limit(self, mock_license_dependency):
        """Test that exactly 50 entries is accepted"""
        from routes.features import PreferencesUpdate

        history = [f"{i}+{i} = {i*2}" for i in range(50)]
        data = PreferencesUpdate(calculator_history=history)

        assert len(data.calculator_history) == 50

    @pytest.mark.asyncio
    async def test_calculator_history_exceeds_limit(self, mock_license_dependency):
        """Test that more than 50 entries raises validation error"""
        from routes.features import PreferencesUpdate
        from pydantic import ValidationError

        history = [f"{i}+{i} = {i*2}" for i in range(51)]

        with pytest.raises(ValidationError) as exc_info:
            PreferencesUpdate(calculator_history=history)

        assert "Calculator history cannot exceed 50 entries" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_calculator_history_json_string_valid(self, mock_license_dependency):
        """Test that valid JSON string history is accepted"""
        from routes.features import PreferencesUpdate
        
        history = ["1+1 = 2", "2+2 = 4"]
        history_json = json.dumps(history)
        data = PreferencesUpdate(calculator_history=history_json)
        
        assert data.calculator_history == history_json

    @pytest.mark.asyncio
    async def test_calculator_history_json_string_exceeds_limit(self, mock_license_dependency):
        """Test that JSON string with more than 50 entries raises validation error"""
        from routes.features import PreferencesUpdate
        from pydantic import ValidationError

        history = [f"{i}+{i} = {i*2}" for i in range(51)]
        history_json = json.dumps(history)

        with pytest.raises(ValidationError) as exc_info:
            PreferencesUpdate(calculator_history=history_json)

        assert "Calculator history cannot exceed 50 entries" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_calculator_history_none_is_accepted(self, mock_license_dependency):
        """Test that None calculator history is accepted"""
        from routes.features import PreferencesUpdate
        
        data = PreferencesUpdate(calculator_history=None)
        
        assert data.calculator_history is None

    @pytest.mark.asyncio
    async def test_calculator_history_empty_list(self, mock_license_dependency):
        """Test that empty list is accepted"""
        from routes.features import PreferencesUpdate
        
        data = PreferencesUpdate(calculator_history=[])
        
        assert data.calculator_history == []

    @pytest.mark.asyncio
    async def test_calculator_history_invalid_json_string(self, mock_license_dependency):
        """Test that invalid JSON string is rejected"""
        from routes.features import PreferencesUpdate
        from pydantic import ValidationError

        # Invalid JSON should now be rejected (security fix)
        with pytest.raises(ValidationError) as exc_info:
            PreferencesUpdate(calculator_history="not valid json")

        assert "Calculator history must be valid JSON" in str(exc_info.value)


class TestCalculatorPreferencesEndpoint:
    """Tests for calculator preferences API endpoints"""
    
    # Note: Integration tests requiring full DB schema are skipped
    # The validation tests above cover the critical functionality

    @pytest.mark.asyncio
    async def test_update_preferences_rejects_large_history(self):
        """Test that updating preferences with large history is rejected"""
        from routes.features import PreferencesUpdate
        from pydantic import ValidationError

        large_history = [f"{i}+{i} = {i*2}" for i in range(100)]

        # Validation happens at payload creation time
        with pytest.raises(ValidationError) as exc_info:
            PreferencesUpdate(calculator_history=large_history)

        assert "Calculator history cannot exceed 50 entries" in str(exc_info.value)


class TestCalculatorHistoryEdgeCases:
    """Edge case tests for calculator history"""

    @pytest.mark.asyncio
    async def test_calculator_history_with_unicode(self, mock_license_dependency):
        """Test calculator history with Arabic/Unicode characters"""
        from routes.features import PreferencesUpdate
        
        history = ["١+١ = ٢", "مرحباً = Hello", "5+5 = 10"]
        data = PreferencesUpdate(calculator_history=history)
        
        assert len(data.calculator_history) == 3

    @pytest.mark.asyncio
    async def test_calculator_history_with_long_expressions(self, mock_license_dependency):
        """Test calculator history with long expressions"""
        from routes.features import PreferencesUpdate
        
        long_expr = "123456789 + 987654321 = 1111111110"
        history = [long_expr]
        data = PreferencesUpdate(calculator_history=history)
        
        assert data.calculator_history[0] == long_expr

    @pytest.mark.asyncio
    async def test_calculator_history_with_special_characters(self, mock_license_dependency):
        """Test calculator history with special characters"""
        from routes.features import PreferencesUpdate
        
        history = ["sqrt(16) = 4", "2^10 = 1024", "sin(0) = 0"]
        data = PreferencesUpdate(calculator_history=history)
        
        assert len(data.calculator_history) == 3
