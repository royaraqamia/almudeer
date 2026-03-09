from datetime import datetime
from hijri_converter import Gregorian

def to_hijri_date_string(date_obj: datetime) -> str:
    """
    Convert Gregorian datetime to Hijri date string in Arabic format.
    Format: YYYY/MM/DD (Hijri)
    Example: 1445/01/01
    """
    if not date_obj:
        return ""
        
    hijri = Gregorian(date_obj.year, date_obj.month, date_obj.day).to_hijri()
    
    # Pad month and day with zeros
    month = f"{hijri.month:02d}"
    day = f"{hijri.day:02d}"
    
    return f"{hijri.year}/{month}/{day}"
