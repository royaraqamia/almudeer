"""
Al-Mudeer - Cleanup Orphaned Knowledge Files

This script cleans up orphaned knowledge base files that exist on disk
but have been deleted from the database.

Usage:
    python cleanup_orphaned_knowledge_files.py

This script can be run periodically (e.g., daily via cron) to reclaim
disk space from orphaned files.
"""

import os
import sys
import asyncio
import logging
from datetime import datetime, timezone

# Add the backend directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from db_helper import get_db, fetch_all, DB_TYPE
from services.file_storage_service import get_file_storage

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def cleanup_orphaned_knowledge_files():
    """
    Clean up orphaned knowledge base files.
    
    Files are considered orphaned if:
    1. They exist in the knowledge_documents table with deleted_at IS NOT NULL
    2. They exist on disk but have no corresponding database entry
    """
    logger.info("Starting cleanup of orphaned knowledge files...")
    
    file_storage = get_file_storage()
    knowledge_dir = os.path.join(file_storage.base_dir, "knowledge")
    
    if not os.path.exists(knowledge_dir):
        logger.info(f"Knowledge directory does not exist: {knowledge_dir}")
        return
    
    stats = {
        "deleted_db_files": 0,
        "deleted_orphan_files": 0,
        "errors": 0,
        "total_space_freed": 0
    }
    
    # Step 1: Clean up files marked as deleted in the database
    logger.info("Cleaning up files marked as deleted in database...")
    async with get_db() as db:
        # Find all deleted file documents with file_path
        query = """
            SELECT id, text, file_path, file_size 
            FROM knowledge_documents 
            WHERE file_path IS NOT NULL 
            AND deleted_at IS NOT NULL
            AND source = 'file'
        """
        
        if DB_TYPE == "postgresql":
            # For PostgreSQL, also get files that don't exist in DB at all (orphans)
            query_orphans = """
                SELECT DISTINCT file_path 
                FROM knowledge_documents 
                WHERE file_path IS NOT NULL 
                AND source = 'file'
                AND id NOT IN (
                    SELECT id FROM knowledge_documents 
                    WHERE deleted_at IS NULL
                )
            """
        else:
            query_orphans = None
        
        deleted_docs = await fetch_all(db, query, [])
        
        for doc in deleted_docs:
            file_path = doc.get("file_path")
            file_size = doc.get("file_size", 0) or 0
            
            if file_path:
                try:
                    # Extract relative path from public URL
                    # Public URL format: /static/uploads/knowledge/xxx
                    if file_path.startswith("/static/uploads/"):
                        relative_path = file_path.replace("/static/uploads/", "")
                    else:
                        relative_path = file_path
                    
                    # Try to delete the file
                    file_storage.delete_file(relative_path)
                    logger.info(f"Deleted file for document {doc['id']}: {file_path}")
                    stats["deleted_db_files"] += 1
                    stats["total_space_freed"] += file_size
                    
                    # Optionally: Remove the record completely from DB (hard delete)
                    # Uncomment the following lines if you want to permanently delete
                    # await execute_sql(
                    #     db,
                    #     "DELETE FROM knowledge_documents WHERE id = ?",
                    #     [doc['id']]
                    # )
                    
                except Exception as e:
                    logger.error(f"Failed to delete file for document {doc['id']}: {e}")
                    stats["errors"] += 1
    
    # Step 2: Find and clean up orphaned files on disk
    logger.info("Scanning for orphaned files on disk...")
    
    # Get all active file paths from database
    async with get_db() as db:
        active_files_query = """
            SELECT file_path 
            FROM knowledge_documents 
            WHERE file_path IS NOT NULL 
            AND deleted_at IS NULL
            AND source = 'file'
        """
        active_docs = await fetch_all(db, active_files_query, [])
        active_file_paths = {doc["file_path"] for doc in active_docs}
    
    # Scan the knowledge directory for files
    for root, dirs, files in os.walk(knowledge_dir):
        for filename in files:
            full_path = os.path.join(root, filename)
            relative_path = os.path.relpath(full_path, file_storage.base_dir)
            public_url = f"/static/uploads/{relative_path.replace(os.sep, '/')}"
            
            # Check if file is in active files
            if public_url not in active_file_paths:
                try:
                    file_size = os.path.getsize(full_path)
                    os.remove(full_path)
                    logger.info(f"Deleted orphaned file: {full_path}")
                    stats["deleted_orphan_files"] += 1
                    stats["total_space_freed"] += file_size
                except Exception as e:
                    logger.error(f"Failed to delete orphaned file {full_path}: {e}")
                    stats["errors"] += 1
    
    # Log summary
    logger.info("=" * 50)
    logger.info("Cleanup Summary:")
    logger.info(f"  - Deleted files from DB records: {stats['deleted_db_files']}")
    logger.info(f"  - Deleted orphaned files on disk: {stats['deleted_orphan_files']}")
    logger.info(f"  - Errors encountered: {stats['errors']}")
    logger.info(f"  - Total space freed: {stats['total_space_freed'] / 1024 / 1024:.2f} MB")
    logger.info("=" * 50)


def main():
    """Main entry point."""
    try:
        asyncio.run(cleanup_orphaned_knowledge_files())
    except KeyboardInterrupt:
        logger.info("Cleanup interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.exception(f"Cleanup failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
