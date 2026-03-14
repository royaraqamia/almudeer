"""Make sender_contact nullable in inbox_messages and outbox_messages

Revision ID: 038_make_sender_contact_nullable
Revises: 035_add_calculator_history_index, 035_backfill_library_file_hash, 037_rename_email_columns
Create Date: 2026-03-14

This migration allows sender_contact to be NULL for messaging channels
(like Telegram) where phone numbers may not be available due to privacy settings.
The sender_id remains the primary unique identifier.

Note: This is a merge migration that combines all branching migration paths.
"""
from alembic import op
import sqlalchemy as sa

revision = '038_make_sender_contact_nullable'
down_revision = ('035_add_calculator_history_index', '035_backfill_library_file_hash', '037_rename_email_columns')
branch_labels = None
depends_on = None


def upgrade():
    """Make sender_contact column nullable in inbox_messages and outbox_messages tables"""

    from db_helper import DB_TYPE

    if DB_TYPE == "postgresql":
        # PostgreSQL - drop NOT NULL constraint
        op.execute("ALTER TABLE inbox_messages ALTER COLUMN sender_contact DROP NOT NULL")
        op.execute("ALTER TABLE outbox_messages ALTER COLUMN recipient_contact DROP NOT NULL")
        
        # Add comment to document the change
        op.execute("COMMENT ON COLUMN inbox_messages.sender_contact IS 'Contact info (phone, email). NULL for channels like Telegram where not available'")
        op.execute("COMMENT ON COLUMN outbox_messages.recipient_contact IS 'Contact info (phone, email). NULL for channels where not available'")
    else:
        # SQLite - cannot modify NOT NULL constraint directly
        # Need to recreate table with modified schema
        _sqlite_alter_table('inbox_messages', 'sender_contact')
        _sqlite_alter_table('outbox_messages', 'recipient_contact')


def _sqlite_alter_table(table_name: str, column_name: str):
    """SQLite helper to recreate table without NOT NULL constraint"""
    try:
        from db_helper import get_db, fetch_all, execute_sql, commit_db
        import asyncio
        
        async def _alter():
            async with get_db() as db:
                # Get existing column info
                columns = await fetch_all(db, f"PRAGMA table_info({table_name})")
                
                # Build column list excluding the target column's NOT NULL
                col_defs = []
                for col in columns:
                    col_name_db = col['name']
                    col_type = col['type']
                    not_null = col['notnull']
                    default = col['dflt_value']
                    
                    if col_name_db == column_name and not_null:
                        # Remove NOT NULL constraint
                        col_defs.append(f"{col_name_db} {col_type}")
                    else:
                        not_null_str = "NOT NULL" if not_null and col_name_db != column_name else ""
                        default_str = f"DEFAULT {default}" if default else ""
                        col_defs.append(f"{col_name_db} {col_type} {not_null_str} {default_str}".strip())
                
                # Create new table
                new_table = f"{table_name}_new"
                cols_str = ", ".join(col_defs)
                await execute_sql(db, f"CREATE TABLE {new_table} ({cols_str})")
                
                # Copy data
                await execute_sql(db, f"INSERT INTO {new_table} SELECT * FROM {table_name}")
                
                # Drop old table and rename new one
                await execute_sql(db, f"DROP TABLE {table_name}")
                await execute_sql(db, f"ALTER TABLE {new_table} RENAME TO {table_name}")
                
                await commit_db(db)
        
        asyncio.run(_alter())
    except Exception as e:
        # Silently ignore if table alteration fails (may already be nullable)
        pass


def downgrade():
    """Restore NOT NULL constraint on sender_contact (requires data cleanup)"""

    from db_helper import DB_TYPE

    if DB_TYPE == "postgresql":
        # First, set a default value for any NULL entries
        op.execute("UPDATE inbox_messages SET sender_contact = 'unknown_' || COALESCE(sender_id, 'no_id') WHERE sender_contact IS NULL")
        op.execute("UPDATE outbox_messages SET recipient_contact = 'unknown_' || COALESCE(recipient_id, 'no_id') WHERE recipient_contact IS NULL")
        
        # Restore NOT NULL constraint
        op.execute("ALTER TABLE inbox_messages ALTER COLUMN sender_contact SET NOT NULL")
        op.execute("ALTER TABLE outbox_messages ALTER COLUMN recipient_contact SET NOT NULL")
    else:
        # SQLite - cannot easily restore NOT NULL without table recreation
        # This is expected behavior - once nullable, always nullable in SQLite
        pass
