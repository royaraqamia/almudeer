"""
QR Code Database Model
Handles QR code generation, validation, and tracking
"""

from datetime import datetime, timedelta, timezone
from typing import Optional, List, Dict, Any
import secrets
import hashlib

from db_helper import get_db, execute_sql, fetch_one, fetch_all


# QR Code types
class QRCodeType:
    LICENSE_KEY = "license_key"
    SHARE_LINK = "share_link"
    CUSTOMER_CARD = "customer_card"
    CUSTOM = "custom"


# QR Code purposes
class QRCodePurpose:
    AUTHENTICATION = "authentication"
    SHARING = "sharing"
    PAYMENT = "payment"
    CONTACT = "contact"
    URL = "url"
    TEXT = "text"
    OTHER = "other"


async def init_qr_tables():
    """Initialize QR code database tables"""
    async with get_db() as db:
        # QR Codes table
        await execute_sql(db, """
            CREATE TABLE IF NOT EXISTS qr_codes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                license_key_id INTEGER NOT NULL,
                code_hash TEXT UNIQUE NOT NULL,
                code_data TEXT NOT NULL,
                code_type TEXT NOT NULL DEFAULT 'custom',
                purpose TEXT DEFAULT 'other',
                
                -- Security & Validation
                is_active BOOLEAN DEFAULT TRUE,
                is_used BOOLEAN DEFAULT FALSE,
                max_uses INTEGER DEFAULT NULL,
                use_count INTEGER DEFAULT 0,
                
                -- Expiration
                expires_at TIMESTAMP,
                
                -- Metadata
                title TEXT,
                description TEXT,
                metadata_json TEXT,
                
                -- Tracking
                created_by INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_used_at TIMESTAMP,
                deleted_at TIMESTAMP,
                
                -- Foreign Keys
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id),
                FOREIGN KEY (created_by) REFERENCES users(id)
            )
        """)

        # Add indexes for performance
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_qr_codes_license 
            ON qr_codes(license_key_id)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_qr_codes_hash 
            ON qr_codes(code_hash)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_qr_codes_active 
            ON qr_codes(is_active, is_used, expires_at)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_qr_codes_created_by 
            ON qr_codes(created_by)
        """)

        # QR Code Scan Logs table for analytics
        await execute_sql(db, """
            CREATE TABLE IF NOT EXISTS qr_scan_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                qr_code_id INTEGER NOT NULL,
                license_key_id INTEGER NOT NULL,
                
                -- Scan details
                scanned_data TEXT,
                scan_result TEXT, -- 'success', 'failed', 'expired', 'invalid'
                
                -- Device/Location info
                device_info TEXT,
                ip_address TEXT,
                user_agent TEXT,
                
                -- Timestamps
                scanned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                
                FOREIGN KEY (qr_code_id) REFERENCES qr_codes(id),
                FOREIGN KEY (license_key_id) REFERENCES license_keys(id)
            )
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_qr_scan_logs_qr 
            ON qr_scan_logs(qr_code_id)
        """)

        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS idx_qr_scan_logs_license 
            ON qr_scan_logs(license_key_id, scanned_at)
        """)


async def generate_qr_code(
    license_key_id: int,
    code_data: str,
    code_type: str = QRCodeType.CUSTOM,
    purpose: str = QRCodePurpose.OTHER,
    title: Optional[str] = None,
    description: Optional[str] = None,
    expires_in_days: Optional[int] = None,
    max_uses: Optional[int] = None,
    created_by: Optional[int] = None,
    metadata: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Generate a new QR code
    
    Args:
        license_key_id: The license key ID this QR code belongs to
        code_data: The data to encode in the QR code
        code_type: Type of QR code (license_key, share_link, etc.)
        purpose: Purpose of the QR code
        title: Optional title for the QR code
        description: Optional description
        expires_in_days: Number of days until expiration (None = never)
        max_uses: Maximum number of times this QR code can be used (None = unlimited)
        created_by: User ID who created this QR code
        metadata: Additional metadata as dictionary
    
    Returns:
        Dictionary with QR code details including the code to encode
    """
    async with get_db() as db:
        # Generate unique code
        unique_id = secrets.token_urlsafe(32)
        code_hash = hashlib.sha256(unique_id.encode()).hexdigest()
        
        # Calculate expiration
        expires_at = None
        if expires_in_days:
            expires_at = datetime.now(timezone.utc) + timedelta(days=expires_in_days)
        
        # Prepare metadata JSON
        import json
        metadata_json = json.dumps(metadata) if metadata else None
        
        # Insert QR code
        await execute_sql(db, """
            INSERT INTO qr_codes (
                license_key_id, code_hash, code_data, code_type, purpose,
                is_active, is_used, max_uses, use_count,
                expires_at, title, description, metadata_json,
                created_by, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            license_key_id, code_hash, code_data, code_type, purpose,
            True, False, max_uses, 0,
            expires_at, title, description, metadata_json,
            created_by, datetime.now(timezone.utc)
        ])
        
        # Fetch the created QR code
        qr_code = await fetch_one(db, """
            SELECT * FROM qr_codes WHERE code_hash = ?
        """, [code_hash])
        
        return {
            "id": qr_code["id"],
            "code_hash": code_hash,
            "code_data": code_data,
            "code_type": code_type,
            "purpose": purpose,
            "title": title,
            "description": description,
            "expires_at": expires_at,
            "max_uses": max_uses,
            "is_active": True,
            "created_at": qr_code["created_at"],
            # The actual data to encode in QR (could be URL with hash)
            "qr_encode_data": code_data,
        }


async def verify_qr_code(
    code_hash: str,
    scanned_data: Optional[str] = None,
    device_info: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Verify a QR code and log the scan
    
    Args:
        code_hash: The hash of the QR code to verify
        scanned_data: Optional data from the scan
        device_info: Optional device information
        ip_address: Optional IP address of scanner
        user_agent: Optional user agent string
    
    Returns:
        Dictionary with verification result and QR code details
    """
    async with get_db() as db:
        from datetime import datetime, timezone
        
        # Fetch QR code
        qr_code = await fetch_one(db, """
            SELECT * FROM qr_codes 
            WHERE code_hash = ? AND deleted_at IS NULL
        """, [code_hash])
        
        if not qr_code:
            # Log failed scan
            await _log_scan(
                db=db,
                code_hash=code_hash,
                scan_result="invalid",
                scanned_data=scanned_data,
                device_info=device_info,
                ip_address=ip_address,
                user_agent=user_agent,
            )
            return {
                "valid": False,
                "error": "QR code not found",
                "error_code": "NOT_FOUND"
            }
        
        # Check if active
        if not qr_code["is_active"]:
            await _log_scan(
                db=db,
                qr_code_id=qr_code["id"],
                license_key_id=qr_code["license_key_id"],
                code_hash=code_hash,
                scan_result="inactive",
                scanned_data=scanned_data,
                device_info=device_info,
                ip_address=ip_address,
                user_agent=user_agent,
            )
            return {
                "valid": False,
                "error": "QR code is inactive",
                "error_code": "INACTIVE"
            }
        
        # Check expiration
        if qr_code["expires_at"]:
            expires_at = datetime.fromisoformat(qr_code["expires_at"]) if isinstance(qr_code["expires_at"], str) else qr_code["expires_at"]
            if expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
                await _log_scan(
                    db=db,
                    qr_code_id=qr_code["id"],
                    license_key_id=qr_code["license_key_id"],
                    code_hash=code_hash,
                    scan_result="expired",
                    scanned_data=scanned_data,
                    device_info=device_info,
                    ip_address=ip_address,
                    user_agent=user_agent,
                )
                return {
                    "valid": False,
                    "error": "QR code has expired",
                    "error_code": "EXPIRED"
                }
        
        # Check usage limit
        if qr_code["max_uses"] and qr_code["use_count"] >= qr_code["max_uses"]:
            await _log_scan(
                db=db,
                qr_code_id=qr_code["id"],
                license_key_id=qr_code["license_key_id"],
                code_hash=code_hash,
                scan_result="max_uses_reached",
                scanned_data=scanned_data,
                device_info=device_info,
                ip_address=ip_address,
                user_agent=user_agent,
            )
            return {
                "valid": False,
                "error": "QR code has reached maximum uses",
                "error_code": "MAX_USES_REACHED"
            }
        
        # Increment use count
        new_use_count = qr_code["use_count"] + 1
        is_now_used = new_use_count >= (qr_code["max_uses"] or 1) if qr_code["max_uses"] else False
        
        await execute_sql(db, """
            UPDATE qr_codes 
            SET use_count = ?, is_used = ?, last_used_at = ?, updated_at = ?
            WHERE id = ?
        """, [
            new_use_count,
            is_now_used,
            datetime.now(timezone.utc),
            datetime.now(timezone.utc),
            qr_code["id"]
        ])
        
        # Log successful scan
        await _log_scan(
            db=db,
            qr_code_id=qr_code["id"],
            license_key_id=qr_code["license_key_id"],
            code_hash=code_hash,
            scan_result="success",
            scanned_data=scanned_data,
            device_info=device_info,
            ip_address=ip_address,
            user_agent=user_agent,
        )
        
        return {
            "valid": True,
            "qr_code": {
                "id": qr_code["id"],
                "code_data": qr_code["code_data"],
                "code_type": qr_code["code_type"],
                "purpose": qr_code["purpose"],
                "title": qr_code["title"],
                "description": qr_code["description"],
                "license_key_id": qr_code["license_key_id"],
            },
            "use_count": new_use_count,
            "max_uses": qr_code["max_uses"],
            "expires_at": qr_code["expires_at"],
        }


async def _log_scan(
    db,
    code_hash: str,
    scan_result: str,
    qr_code_id: Optional[int] = None,
    license_key_id: Optional[int] = None,
    scanned_data: Optional[str] = None,
    device_info: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
):
    """Log a QR code scan attempt"""
    # If we don't have qr_code_id, try to get it from code_hash
    if not qr_code_id or not license_key_id:
        qr = await fetch_one(db, """
            SELECT id, license_key_id FROM qr_codes WHERE code_hash = ?
        """, [code_hash])
        if qr:
            qr_code_id = qr["id"]
            license_key_id = qr["license_key_id"]
    
    if qr_code_id and license_key_id:
        await execute_sql(db, """
            INSERT INTO qr_scan_logs (
                qr_code_id, license_key_id, scanned_data, scan_result,
                device_info, ip_address, user_agent, scanned_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            qr_code_id, license_key_id, scanned_data, scan_result,
            device_info, ip_address, user_agent, datetime.now(timezone.utc)
        ])


async def get_qr_code(qr_code_id: int, license_key_id: int) -> Optional[Dict[str, Any]]:
    """Get a specific QR code by ID"""
    async with get_db() as db:
        qr_code = await fetch_one(db, """
            SELECT * FROM qr_codes 
            WHERE id = ? AND license_key_id = ? AND deleted_at IS NULL
        """, [qr_code_id, license_key_id])
        return qr_code


async def list_qr_codes(
    license_key_id: int,
    code_type: Optional[str] = None,
    is_active: Optional[bool] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """List QR codes with filters"""
    async with get_db() as db:
        query = """
            SELECT * FROM qr_codes 
            WHERE license_key_id = ? AND deleted_at IS NULL
        """
        params = [license_key_id]
        
        if code_type:
            query += " AND code_type = ?"
            params.append(code_type)
        
        if is_active is not None:
            query += " AND is_active = ?"
            params.append(is_active)
        
        query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        return await fetch_all(db, query, params)


async def deactivate_qr_code(qr_code_id: int, license_key_id: int) -> bool:
    """Deactivate a QR code"""
    async with get_db() as db:
        result = await execute_sql(db, """
            UPDATE qr_codes 
            SET is_active = FALSE, updated_at = ?
            WHERE id = ? AND license_key_id = ?
        """, [datetime.now(timezone.utc), qr_code_id, license_key_id])
        return result is not None


async def delete_qr_code(qr_code_id: int, license_key_id: int) -> bool:
    """Soft delete a QR code"""
    async with get_db() as db:
        result = await execute_sql(db, """
            UPDATE qr_codes 
            SET deleted_at = ?, updated_at = ?
            WHERE id = ? AND license_key_id = ?
        """, [datetime.now(timezone.utc), datetime.now(timezone.utc), qr_code_id, license_key_id])
        return result is not None


async def get_qr_analytics(
    qr_code_id: int,
    license_key_id: int,
    days: int = 30,
) -> Dict[str, Any]:
    """Get analytics for a QR code"""
    async with get_db() as db:
        from datetime import timedelta
        
        start_date = datetime.now(timezone.utc) - timedelta(days=days)
        
        # Get scan count by result
        scan_counts = await fetch_all(db, """
            SELECT scan_result, COUNT(*) as count
            FROM qr_scan_logs
            WHERE qr_code_id = ? AND scanned_at >= ?
            GROUP BY scan_result
        """, [qr_code_id, start_date])
        
        # Get total scans
        total_scans = await fetch_one(db, """
            SELECT COUNT(*) as count
            FROM qr_scan_logs
            WHERE qr_code_id = ? AND scanned_at >= ?
        """, [qr_code_id, start_date])
        
        # Get recent scans
        recent_scans = await fetch_all(db, """
            SELECT * FROM qr_scan_logs
            WHERE qr_code_id = ?
            ORDER BY scanned_at DESC
            LIMIT 10
        """, [qr_code_id])
        
        return {
            "total_scans": total_scans["count"] if total_scans else 0,
            "scans_by_result": {row["scan_result"]: row["count"] for row in scan_counts},
            "recent_scans": recent_scans,
            "period_days": days,
        }
