"""
Run all pending migrations for chat read receipts feature

Usage: python run_read_receipt_migrations.py
"""

import asyncio
from migrations.add_conversation_delivery_status import add_delivery_status_column
from logging_config import get_logger

logger = get_logger(__name__)


async def run_migrations():
    """Run all read receipt related migrations."""
    print("Running read receipt migrations...")
    
    # Migration 1: Add delivery_status column to inbox_conversations
    print("  [1/1] Adding delivery_status column to inbox_conversations...")
    await add_delivery_status_column()
    
    print("\n[OK] All migrations completed successfully!")


if __name__ == "__main__":
    asyncio.run(run_migrations())
