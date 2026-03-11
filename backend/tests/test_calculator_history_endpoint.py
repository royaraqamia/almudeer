"""
Al-Mudeer Calculator History Endpoint Tests
Tests for the new dedicated calculator history API endpoints
"""

import pytest
import json
from datetime import datetime
from unittest.mock import AsyncMock, patch, MagicMock


@pytest.fixture
def mock_license_dependency():
    """Mock license dependency for testing - patches where it's used"""
    mock_dep = AsyncMock(return_value={"license_id": 1, "license_key_id": 1})
    with patch("routes.features.get_license_from_header", mock_dep):
        with patch("dependencies.get_license_from_header", mock_dep):
            yield {"license_id": 1, "license_key_id": 1}


@pytest.fixture
def mock_optional_license_dependency():
    """Mock optional license dependency for testing"""
    mock_dep = AsyncMock(return_value={"license_id": 1, "license_key_id": 1})
    with patch("routes.features.get_optional_license_from_header", mock_dep):
        with patch("dependencies.get_optional_license_from_header", mock_dep):
            yield {"license_id": 1, "license_key_id": 1}


@pytest.fixture
def mock_db_session():
    """Mock database session"""
    mock_db = AsyncMock()
    with patch("db_helper.get_db") as mock_get_db:
        mock_get_db.return_value.__aenter__.return_value = mock_db
        yield mock_db


@pytest.fixture
def mock_preferences_model():
    """Mock preferences model functions - patch where they're used"""
    with patch("routes.features.get_preferences") as mock_get, \
         patch("routes.features.update_preferences") as mock_update:
        mock_get.return_value = {
            "license_key_id": 1,
            "calculator_history": [],
            "dark_mode": False,
            "notifications_enabled": True,
        }
        mock_update.return_value = True
        yield mock_get, mock_update


class TestCalculatorHistoryEntrySchema:
    """Tests for CalculatorHistoryEntry schema validation"""

    def test_valid_entry(self):
        from routes.features import CalculatorHistoryEntry
        
        entry = CalculatorHistoryEntry(
            entry="5+5 = 10",
            timestamp="2026-03-11T10:00:00Z"
        )
        assert entry.entry == "5+5 = 10"
        assert entry.timestamp == "2026-03-11T10:00:00Z"

    def test_entry_with_arabic(self):
        from routes.features import CalculatorHistoryEntry
        
        entry = CalculatorHistoryEntry(
            entry="٥+٥ = ١٠",
            timestamp="2026-03-11T10:00:00Z"
        )
        assert entry.entry == "٥+٥ = ١٠"

    def test_entry_with_scientific_functions(self):
        from routes.features import CalculatorHistoryEntry
        
        entry = CalculatorHistoryEntry(
            entry="sqrt(16) = 4",
            timestamp="2026-03-11T10:00:00Z"
        )
        assert entry.entry == "sqrt(16) = 4"

    def test_entry_strips_html_tags(self):
        from routes.features import CalculatorHistoryEntry
        
        # HTML tags should be stripped for security
        entry = CalculatorHistoryEntry(
            entry="<script>alert('xss')</script>5+5 = 10",
            timestamp="2026-03-11T10:00:00Z"
        )
        assert "<script>" not in entry.entry
        assert "5+5 = 10" in entry.entry

    def test_entry_truncates_long_strings(self):
        from routes.features import CalculatorHistoryEntry
        
        # Pydantic Field validation enforces max_length before validator runs
        # So we test with exactly 500 characters (the max)
        entry = CalculatorHistoryEntry(
            entry="1" * 500,  # Exactly 500 characters (max allowed)
            timestamp="2026-03-11T10:00:00Z"
        )
        assert len(entry.entry) == 500
        
        # Verify that >500 characters raises validation error
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            CalculatorHistoryEntry(
                entry="1" * 501,  # 501 characters (exceeds max)
                timestamp="2026-03-11T10:00:00Z"
            )

    def test_entry_removes_control_characters(self):
        from routes.features import CalculatorHistoryEntry
        
        # Control characters should be removed
        entry = CalculatorHistoryEntry(
            entry="5+5 = 10\x00\x01\x02",
            timestamp="2026-03-11T10:00:00Z"
        )
        assert "\x00" not in entry.entry
        assert "\x01" not in entry.entry


class TestCalculatorHistoryUpdateSchema:
    """Tests for CalculatorHistoryUpdate schema validation"""

    def test_valid_history_update(self):
        from routes.features import CalculatorHistoryUpdate, CalculatorHistoryEntry
        
        update = CalculatorHistoryUpdate(history=[
            CalculatorHistoryEntry(entry="5+5 = 10", timestamp="2026-03-11T10:00:00Z"),
            CalculatorHistoryEntry(entry="10-3 = 7", timestamp="2026-03-11T10:01:00Z"),
        ])
        assert len(update.history) == 2

    def test_history_at_limit(self):
        from routes.features import CalculatorHistoryUpdate, CalculatorHistoryEntry
        
        entries = [
            CalculatorHistoryEntry(entry=f"{i}+{i} = {i*2}", timestamp="2026-03-11T10:00:00Z")
            for i in range(50)
        ]
        update = CalculatorHistoryUpdate(history=entries)
        assert len(update.history) == 50

    def test_history_exceeds_limit(self):
        from routes.features import CalculatorHistoryUpdate, CalculatorHistoryEntry
        from pydantic import ValidationError
        
        entries = [
            CalculatorHistoryEntry(entry=f"{i}+{i} = {i*2}", timestamp="2026-03-11T10:00:00Z")
            for i in range(51)
        ]
        
        with pytest.raises(ValidationError) as exc_info:
            CalculatorHistoryUpdate(history=entries)
        
        assert "Calculator history cannot exceed 50 entries" in str(exc_info.value)

    def test_empty_history_is_valid(self):
        from routes.features import CalculatorHistoryUpdate
        
        update = CalculatorHistoryUpdate(history=[])
        assert len(update.history) == 0


class TestGetCalculatorHistoryEndpoint:
    """Tests for GET /api/calculator/history endpoint"""

    @pytest.mark.asyncio
    async def test_get_empty_history(self, mock_preferences_model):
        """Test getting empty calculator history"""
        from routes.features import get_calculator_history
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        mock_get, _ = mock_preferences_model
        
        # Create mock license dict (simulating what Depends would provide)
        mock_license = {"license_id": 1, "license_key_id": 1}
        
        result = await get_calculator_history(mock_request, mock_license)
        
        assert result.success is True
        assert result.history == []

    @pytest.mark.asyncio
    async def test_get_history_with_entries(self, mock_preferences_model):
        """Test getting calculator history with entries"""
        from routes.features import get_calculator_history
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        mock_get, _ = mock_preferences_model
        
        # Mock history with structured entries
        history_data = [
            {"entry": "5+5 = 10", "timestamp": "2026-03-11T10:00:00Z"},
            {"entry": "10-3 = 7", "timestamp": "2026-03-11T10:01:00Z"},
        ]
        mock_get.return_value["calculator_history"] = history_data
        
        mock_license = {"license_id": 1, "license_key_id": 1}
        result = await get_calculator_history(mock_request, mock_license)
        
        assert result.success is True
        assert len(result.history) == 2
        assert result.history[0].entry == "5+5 = 10"
        assert result.history[1].entry == "10-3 = 7"

    @pytest.mark.asyncio
    async def test_get_history_legacy_string_format(self, mock_preferences_model):
        """Test getting history with legacy string format (backward compatibility)"""
        from routes.features import get_calculator_history
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        mock_get, _ = mock_preferences_model
        
        # Mock legacy format - just strings
        mock_get.return_value["calculator_history"] = ["5+5 = 10", "10-3 = 7"]
        
        mock_license = {"license_id": 1, "license_key_id": 1}
        result = await get_calculator_history(mock_request, mock_license)
        
        assert result.success is True
        assert len(result.history) == 2

    @pytest.mark.asyncio
    async def test_get_history_json_string(self, mock_preferences_model):
        """Test getting history stored as JSON string"""
        from routes.features import get_calculator_history
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        mock_get, _ = mock_preferences_model
        
        # Mock JSON string format
        history_data = [{"entry": "5+5 = 10", "timestamp": "2026-03-11T10:00:00Z"}]
        mock_get.return_value["calculator_history"] = json.dumps(history_data)
        
        mock_license = {"license_id": 1, "license_key_id": 1}
        result = await get_calculator_history(mock_request, mock_license)
        
        assert result.success is True
        assert len(result.history) == 1


class TestUpdateCalculatorHistoryEndpoint:
    """Tests for PATCH /api/calculator/history endpoint"""

    @pytest.mark.asyncio
    async def test_update_history(self, mock_preferences_model):
        """Test updating calculator history"""
        from routes.features import update_calculator_history, CalculatorHistoryUpdate, CalculatorHistoryEntry
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        _, mock_update = mock_preferences_model
        
        update_data = CalculatorHistoryUpdate(history=[
            CalculatorHistoryEntry(entry="5+5 = 10", timestamp="2026-03-11T10:00:00Z"),
        ])
        
        mock_license = {"license_id": 1, "license_key_id": 1}
        result = await update_calculator_history(mock_request, update_data, mock_license)
        
        assert result["success"] is True
        mock_update.assert_called_once()
        
        # Verify the call included calculator_history as JSON
        call_kwargs = mock_update.call_args[1]
        assert "calculator_history" in call_kwargs
        
        # Verify it's valid JSON
        history_json = call_kwargs["calculator_history"]
        parsed = json.loads(history_json)
        assert isinstance(parsed, list)
        assert len(parsed) == 1
        assert parsed[0]["entry"] == "5+5 = 10"
        assert parsed[0]["timestamp"] == "2026-03-11T10:00:00Z"

    @pytest.mark.asyncio
    async def test_update_history_with_arabic(self, mock_preferences_model):
        """Test updating history with Arabic expressions"""
        from routes.features import update_calculator_history, CalculatorHistoryUpdate, CalculatorHistoryEntry
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        _, mock_update = mock_preferences_model
        
        update_data = CalculatorHistoryUpdate(history=[
            CalculatorHistoryEntry(entry="٥+٥ = ١٠", timestamp="2026-03-11T10:00:00Z"),
        ])
        
        mock_license = {"license_id": 1, "license_key_id": 1}
        result = await update_calculator_history(mock_request, update_data, mock_license)
        
        assert result["success"] is True
        assert result["message"] == "تم حفظ سجل الحاسبة"


class TestClearCalculatorHistoryEndpoint:
    """Tests for DELETE /api/calculator/history endpoint"""

    @pytest.mark.asyncio
    async def test_clear_history(self, mock_preferences_model):
        """Test clearing calculator history"""
        from routes.features import clear_calculator_history
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        _, mock_update = mock_preferences_model
        
        mock_license = {"license_id": 1, "license_key_id": 1}
        result = await clear_calculator_history(mock_request, mock_license)
        
        assert result["success"] is True
        assert result["message"] == "تم مسح سجل الحاسبة"
        
        # Verify update_preferences was called with empty history
        mock_update.assert_called_once()
        call_kwargs = mock_update.call_args[1]
        assert "calculator_history" in call_kwargs
        
        history_json = call_kwargs["calculator_history"]
        parsed = json.loads(history_json)
        assert parsed == []


class TestCalculatorHistoryValidation:
    """Additional validation tests for calculator history"""

    def test_timestamp_format_validation(self):
        """Test that timestamps are stored as strings (ISO 8601)"""
        from routes.features import CalculatorHistoryEntry
        
        # Various valid ISO 8601 formats
        valid_timestamps = [
            "2026-03-11T10:00:00Z",
            "2026-03-11T10:00:00+00:00",
            "2026-03-11T10:00:00.123Z",
            "2026-03-11T10:00:00.123456+03:00",
        ]
        
        for ts in valid_timestamps:
            entry = CalculatorHistoryEntry(entry="5+5 = 10", timestamp=ts)
            assert entry.timestamp == ts

    def test_entry_with_special_math_symbols(self):
        """Test entries with various math symbols"""
        from routes.features import CalculatorHistoryEntry
        
        entries = [
            "5 × 5 = 25",
            "10 ÷ 2 = 5",
            "2² = 4",
            "√16 = 4",
            "2^10 = 1024",
            "sin(0) = 0",
            "cos(0) = 1",
            "log(100) = 2",
            "ln(e) ≈ 1",
        ]
        
        for entry_str in entries:
            entry = CalculatorHistoryEntry(entry=entry_str, timestamp="2026-03-11T10:00:00Z")
            assert entry.entry == entry_str

    def test_entry_with_unicode_numbers(self):
        """Test entries with Arabic-Indic numerals"""
        from routes.features import CalculatorHistoryEntry
        
        entry = CalculatorHistoryEntry(
            entry="١+١ = ٢",  # Arabic-Indic numerals
            timestamp="2026-03-11T10:00:00Z"
        )
        assert entry.entry == "١+١ = ٢"


class TestCalculatorHistoryIntegration:
    """Integration tests for calculator history flow"""

    @pytest.mark.asyncio
    async def test_full_crud_flow(self, mock_preferences_model):
        """Test full create-read-update-delete flow"""
        from routes.features import (
            get_calculator_history,
            update_calculator_history,
            clear_calculator_history,
            CalculatorHistoryUpdate,
            CalculatorHistoryEntry,
        )
        from fastapi import Request
        
        mock_request = MagicMock(spec=Request)
        mock_get, mock_update = mock_preferences_model
        mock_license = {"license_id": 1, "license_key_id": 1}
        
        # 1. Start with empty history
        result = await get_calculator_history(mock_request, mock_license)
        assert len(result.history) == 0
        
        # 2. Add entries
        update_data = CalculatorHistoryUpdate(history=[
            CalculatorHistoryEntry(entry="1+1 = 2", timestamp="2026-03-11T10:00:00Z"),
            CalculatorHistoryEntry(entry="2+2 = 4", timestamp="2026-03-11T10:01:00Z"),
        ])
        await update_calculator_history(mock_request, update_data, mock_license)
        
        # 3. Read entries (mock the updated preferences)
        mock_get.return_value["calculator_history"] = [
            {"entry": "1+1 = 2", "timestamp": "2026-03-11T10:00:00Z"},
            {"entry": "2+2 = 4", "timestamp": "2026-03-11T10:01:00Z"},
        ]
        result = await get_calculator_history(mock_request, mock_license)
        assert len(result.history) == 2
        
        # 4. Clear history
        result = await clear_calculator_history(mock_request, mock_license)
        assert result["success"] is True
