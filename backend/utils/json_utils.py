import json
from datetime import datetime, date
from decimal import Decimal
from uuid import UUID
from typing import Any

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
