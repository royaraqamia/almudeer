import json
from datetime import datetime, date
from decimal import Decimal
from uuid import UUID
from typing import Any, Optional

class EnhancedJSONEncoder(json.JSONEncoder):
    """
    Custom JSON encoder that handles:
    - datetime: converted to ISO format
    - date: converted to ISO format
    - Decimal: converted to float or string
    - UUID: converted to string
    - set: converted to list
    """
    def default(self, obj: Any) -> Any:
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        if isinstance(obj, Decimal):
            return float(obj)
        if isinstance(obj, UUID):
            return str(obj)
        if isinstance(obj, set):
            return list(obj)
        return super().default(obj)

def json_dumps(obj: Any, **kwargs) -> str:
    """
    Utility function to dump objects to JSON using the EnhancedJSONEncoder.
    """
    # Ensure cls is not passed twice
    kwargs.setdefault('cls', EnhancedJSONEncoder)
    return json.dumps(obj, **kwargs)


# FIX: Unified boolean normalization utility for consistent handling across the codebase
def normalize_bool(value: Any, default: bool = False) -> bool:
    """
    Normalize various boolean representations to Python bool.
    
    Handles:
    - None: returns default
    - bool: returns as-is
    - int (0/1): 0 = False, non-zero = True
    - str ('true'/'false'/'yes'/'no'/'1'/'0'): case-insensitive
    - Any other truthy/falsy value
    
    Args:
        value: The value to normalize
        default: Default value if input is None
        
    Returns:
        bool: Normalized boolean value
    """
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value != 0
    if isinstance(value, str):
        return value.lower() in ('true', '1', 'yes', 'y')
    # Fallback for any other type
    return bool(value)


def normalize_priority(value: Any, default: str = 'medium') -> str:
    """
    Normalize priority values from various formats.
    
    Handles:
    - int (0-3): converts to string ('low', 'medium', 'high', 'urgent')
    - str: validates and returns as-is
    - None: returns default
    
    Args:
        value: The priority value to normalize
        default: Default priority if input is None or invalid
        
    Returns:
        str: Normalized priority string
    """
    priority_map = ['low', 'medium', 'high', 'urgent']
    
    if value is None:
        return default
    if isinstance(value, int):
        if 0 <= value < len(priority_map):
            return priority_map[value]
        return default
    if isinstance(value, str):
        normalized = value.lower()
        if normalized in priority_map:
            return normalized
        return default
    return default
