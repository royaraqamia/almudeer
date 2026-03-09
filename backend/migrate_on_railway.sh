#!/bin/bash
# Migration script to run on Railway
# This uses the internal Railway URL which works from within Railway

echo "Starting migration on Railway..."
echo "Using internal Railway PostgreSQL connection..."

# Railway automatically sets DATABASE_URL with internal URL
export DB_TYPE=postgresql

# Run migration
python migrate_to_postgresql.py

echo "Migration complete!"

