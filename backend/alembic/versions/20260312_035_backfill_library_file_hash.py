"""Backfill file_hash for existing library items

Revision ID: 035_backfill_library_file_hash
Revises: 034_add_library_share_expires_index
Create Date: 2026-03-12

Production Readiness Fix: Backfill file_hash for existing library items.
The migration 013_add_library_file_hash added the column but didn't backfill.
This migration computes SHA-256 hashes for all existing files.

"""
from typing import Union
from alembic import op
import sqlalchemy as sa
import hashlib
import logging

revision: str = '035_backfill_library_file_hash'
down_revision: Union[str, None] = '034_add_library_share_expires_index'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None

logger = logging.getLogger(__name__)


def upgrade() -> None:
    """Backfill file_hash for existing library items"""
    from services.file_storage_service import get_file_storage
    
    connection = op.get_bind()
    
    # Fetch all library items with file_path but no file_hash
    result = connection.execute(sa.text("""
        SELECT id, file_path FROM library_items
        WHERE file_path IS NOT NULL 
        AND file_hash IS NULL
        AND deleted_at IS NULL
    """))
    
    items = result.fetchall()
    file_storage = get_file_storage()
    
    logger.info(f"Backfilling file_hash for {len(items)} library items")
    
    updated_count = 0
    failed_count = 0
    
    for item_id, file_path in items:
        try:
            # Read file content and compute hash
            # Note: file_path is relative to storage root
            full_path = file_storage.get_full_path(file_path)
            
            hasher = hashlib.sha256()
            with open(full_path, 'rb') as f:
                # Read in chunks for memory efficiency
                for chunk in iter(lambda: f.read(8192), b''):
                    hasher.update(chunk)
            
            file_hash = hasher.hexdigest()
            
            # Update database
            connection.execute(sa.text("""
                UPDATE library_items
                SET file_hash = :file_hash
                WHERE id = :item_id
            """), {"file_hash": file_hash, "item_id": item_id})
            
            updated_count += 1
            
            if updated_count % 100 == 0:
                logger.info(f"Processed {updated_count}/{len(items)} items")
                
        except FileNotFoundError:
            logger.warning(f"File not found for item {item_id}: {file_path}")
            failed_count += 1
        except Exception as e:
            logger.error(f"Failed to compute hash for item {item_id}: {e}")
            failed_count += 1
    
    logger.info(f"Backfill complete: {updated_count} succeeded, {failed_count} failed")


def downgrade() -> None:
    """Clear file_hash values"""
    connection = op.get_bind()
    connection.execute(sa.text("""
        UPDATE library_items
        SET file_hash = NULL
        WHERE file_hash IS NOT NULL
    """))
