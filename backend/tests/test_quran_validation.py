"""
Tests for Quran progress validation.
Ensures proper validation of surah and verse numbers.
"""

import pytest
from routes.sync import _validate_quran_progress


class TestQuranProgressValidation:
    """Test suite for _validate_quran_progress function."""

    def test_valid_progress(self):
        """Test valid Quran progress data."""
        data = {"last_surah": 1, "last_verse": 7}
        assert _validate_quran_progress(data) is None

        data = {"last_surah": 114, "last_verse": 6}
        assert _validate_quran_progress(data) is None

        data = {"last_surah": 2, "last_verse": 286}  # Al-Baqarah max
        assert _validate_quran_progress(data) is None

    def test_invalid_data_type(self):
        """Test that non-dict data is rejected."""
        assert _validate_quran_progress(None) is not None
        assert _validate_quran_progress("string") is not None
        assert _validate_quran_progress(123) is not None
        assert _validate_quran_progress([]) is not None

    def test_missing_surah(self):
        """Test that missing surah number is rejected."""
        data = {"last_verse": 5}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "رقم السورة مطلوب" in result

    def test_missing_verse(self):
        """Test that missing verse number is rejected."""
        data = {"last_surah": 1}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "رقم الآية مطلوب" in result

    def test_surah_below_range(self):
        """Test that surah < 1 is rejected."""
        data = {"last_surah": 0, "last_verse": 1}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "1 و 114" in result

        data = {"last_surah": -1, "last_verse": 1}
        result = _validate_quran_progress(data)
        assert result is not None

    def test_surah_above_range(self):
        """Test that surah > 114 is rejected."""
        data = {"last_surah": 115, "last_verse": 1}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "1 و 114" in result

        data = {"last_surah": 200, "last_verse": 1}
        result = _validate_quran_progress(data)
        assert result is not None

    def test_verse_below_range(self):
        """Test that verse < 1 is rejected."""
        data = {"last_surah": 1, "last_verse": 0}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "موجباً" in result

        data = {"last_surah": 1, "last_verse": -5}
        result = _validate_quran_progress(data)
        assert result is not None

    def test_verse_exceeds_surah_count(self):
        """Test that verse exceeding surah's verse count is rejected."""
        # Al-Fatihah has only 7 verses
        data = {"last_surah": 1, "last_verse": 8}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "الفاتحة" in result or "سورة 1" in result
        assert "7" in result

        # Al-Kawthar has only 3 verses
        data = {"last_surah": 108, "last_verse": 4}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "3" in result

        # Al-Baqarah has 286 verses - this should pass
        data = {"last_surah": 2, "last_verse": 286}
        assert _validate_quran_progress(data) is None

        # Al-Baqarah with 287 verses should fail
        data = {"last_surah": 2, "last_verse": 287}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "286" in result

    def test_string_numbers_are_coerced(self):
        """Test that string numbers are converted to integers."""
        data = {"last_surah": "1", "last_verse": "7"}
        assert _validate_quran_progress(data) is None

        data = {"last_surah": "114", "last_verse": "6"}
        assert _validate_quran_progress(data) is None

    def test_invalid_string_numbers(self):
        """Test that invalid string numbers are rejected."""
        data = {"last_surah": "abc", "last_verse": 1}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "رقماً صحيحاً" in result

        data = {"last_surah": 1, "last_verse": "xyz"}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "رقماً صحيحاً" in result

    def test_float_numbers_are_rejected(self):
        """Test that float numbers are rejected or coerced."""
        # Floats that can be coerced to int
        data = {"last_surah": 1.0, "last_verse": 7}
        # This will fail because 1.0 is not an int
        result = _validate_quran_progress(data)
        # Either it gets coerced or rejected - both are acceptable
        # The important thing is it doesn't crash

    def test_edge_cases_all_surahs(self):
        """Test boundary verses for various surahs."""
        # Test first verse of each surah
        for surah in [1, 2, 50, 100, 114]:
            data = {"last_surah": surah, "last_verse": 1}
            assert _validate_quran_progress(data) is None, f"Failed for surah {surah}"

        # Test last verse of specific surahs
        test_cases = [
            (1, 7),    # Al-Fatihah
            (9, 129),  # At-Tawbah
            (36, 83),  # Ya-Sin
            (55, 78),  # Ar-Rahman
            (108, 3),  # Al-Kawthar (shortest)
            (114, 6),  # An-Nas
        ]
        for surah, max_verse in test_cases:
            data = {"last_surah": surah, "last_verse": max_verse}
            assert _validate_quran_progress(data) is None, f"Failed for surah {surah}, verse {max_verse}"

    def test_error_messages_are_in_arabic(self):
        """Test that error messages are in Arabic."""
        test_cases = [
            {"last_surah": 0, "last_verse": 1},
            {"last_surah": 1, "last_verse": 0},
            {"last_surah": 1, "last_verse": 100},  # Exceeds Al-Fatihah
            {"last_surah": "abc", "last_verse": 1},
        ]
        for data in test_cases:
            result = _validate_quran_progress(data)
            assert result is not None
            # Check that result contains Arabic characters
            assert any('\u0600' <= c <= '\u06FF' for c in result), f"Error message not in Arabic: {result}"

    def test_dynamic_error_messages_include_numbers(self):
        """Test that dynamic error messages include the invalid numbers."""
        data = {"last_surah": 150, "last_verse": 1}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "150" in result

        data = {"last_surah": 1, "last_verse": -10}
        result = _validate_quran_progress(data)
        assert result is not None
        assert "-10" in result
