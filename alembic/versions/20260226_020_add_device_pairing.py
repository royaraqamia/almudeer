"""Add device pairing table for nearby sharing

Revision ID: 020_add_device_pairing
Revises: 019_add_share_features
Create Date: 2026-02-26

P3-1/Nearby: Device pairing for trusted transfers

"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = '023_add_device_pairing'
down_revision: Union[str, None] = '022_add_share_features'
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    """Create device_pairing table and indexes"""
    
    op.create_table(
        'device_pairing',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('license_key_id', sa.Integer(), nullable=False),
        sa.Column('device_id_a', sa.Text(), nullable=False),
        sa.Column('device_id_b', sa.Text(), nullable=False),
        sa.Column('device_name_a', sa.Text(), nullable=True),
        sa.Column('device_name_b', sa.Text(), nullable=True),
        sa.Column('paired_at', sa.DateTime(), nullable=True),
        sa.Column('paired_by', sa.Text(), nullable=True),
        sa.Column('is_trusted', sa.Boolean(), default=True),
        sa.Column('last_connected_at', sa.DateTime(), nullable=True),
        sa.Column('connection_count', sa.Integer(), default=0),
        sa.Column('deleted_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['license_key_id'], ['license_keys.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('device_id_a', 'device_id_b', name='uq_pair_devices')
    )
    
    # Indexes for common queries
    op.execute("""
        CREATE INDEX idx_pairing_license_device_a
        ON device_pairing(license_key_id, device_id_a)
        WHERE deleted_at IS NULL
    """)
    
    op.execute("""
        CREATE INDEX idx_pairing_license_device_b
        ON device_pairing(license_key_id, device_id_b)
        WHERE deleted_at IS NULL
    """)
    
    op.execute("""
        CREATE INDEX idx_pairing_trusted
        ON device_pairing(license_key_id, is_trusted)
        WHERE is_trusted = TRUE AND deleted_at IS NULL
    """)
    
    op.execute("""
        CREATE INDEX idx_pairing_last_connected
        ON device_pairing(last_connected_at DESC)
    """)


def downgrade() -> None:
    """Drop device_pairing table and indexes"""
    op.execute("DROP INDEX IF EXISTS idx_pairing_last_connected")
    op.execute("DROP INDEX IF EXISTS idx_pairing_trusted")
    op.execute("DROP INDEX IF EXISTS idx_pairing_license_device_b")
    op.execute("DROP INDEX IF EXISTS idx_pairing_license_device_a")
    op.drop_table('device_pairing')
