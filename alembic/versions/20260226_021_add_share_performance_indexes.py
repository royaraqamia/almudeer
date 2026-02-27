"""Add performance indexes for share queries

Revision ID: 021_add_share_performance_indexes
Revises: 020_add_device_pairing
Create Date: 2026-02-26

P6-1: Performance optimization indexes

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '024_add_share_performance_indexes'
down_revision: Union[str, None] = '023_add_device_pairing'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Add performance indexes for share-related queries"""
    
    # Composite index for get_shared_items query pattern
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_shares_active_user_permission
        ON library_shares(license_key_id, shared_with_user_id, permission, deleted_at)
        WHERE deleted_at IS NULL
    """)
    
    # Index for analytics queries by action
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_analytics_license_action
        ON library_analytics(license_key_id, action, timestamp)
    """)
    
    # Index for item access queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_library_access_desc
        ON library_items(license_key_id, access_count DESC, deleted_at)
        WHERE deleted_at IS NULL
    """)
    
    # Index for task visibility queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_tasks_visibility
        ON tasks(license_key_id, visibility, created_by, assigned_to)
        WHERE deleted_at IS NULL
    """)
    
    # Index for device pairing lookups
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_pairing_lookup
        ON device_pairing(license_key_id, device_id_a, device_id_b)
        WHERE deleted_at IS NULL
    """)
    
    print("Performance indexes added successfully")


def downgrade() -> None:
    """Remove performance indexes"""
    op.execute("DROP INDEX IF EXISTS idx_pairing_lookup")
    op.execute("DROP INDEX IF EXISTS idx_tasks_visibility")
    op.execute("DROP INDEX IF EXISTS idx_library_access_desc")
    op.execute("DROP INDEX IF EXISTS idx_analytics_license_action")
    op.execute("DROP INDEX IF EXISTS idx_shares_active_user_permission")
