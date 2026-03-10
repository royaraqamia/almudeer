import logging
from db_helper import get_db, execute_sql, commit_db, DB_TYPE, fetch_all

logger = logging.getLogger(__name__)

async def setup_full_text_search():
    """
    Sets up Full-Text Search (FTS) for messages.
    Supports SQLite (FTS5) and PostgreSQL (TSVector).
    """
    async with get_db() as db:
        if DB_TYPE == "sqlite":
            await _setup_sqlite_fts(db)
        elif DB_TYPE == "postgresql":
            await _setup_postgres_fts(db)
            
        await commit_db(db)
        logger.info("Full-text search setup complete.")

async def _setup_sqlite_fts(db):
    """
    Setup FTS5 for SQLite.
    Creates a unified virtual table 'messages_fts' that indexes both inbox and outbox messages.
    """
    logger.info("Setting up SQLite FTS5 table and triggers...")

    # FIX: Proper table existence check using sqlite_master
    try:
        result = await fetch_all(db, """
            SELECT name FROM sqlite_master 
            WHERE type='table' AND name='messages_fts'
        """)
        if result:
            logger.info("messages_fts table already exists, skipping creation.")
            return
    except Exception as e:
        logger.warning(f"Error checking messages_fts existence: {e}")
        # Continue anyway - CREATE VIRTUAL TABLE IF NOT EXISTS will handle it

    # Create the table
    await execute_sql(db, """
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            body,
            sender_name,
            source_table UNINDEXED, -- 'inbox' or 'outbox'
            source_id UNINDEXED,    -- original id
            license_id UNINDEXED
        )
    """)

    # 2. Create Triggers for Inbox Messages
    await execute_sql(db, """
        CREATE TRIGGER IF NOT EXISTS inbox_fts_insert AFTER INSERT ON inbox_messages
        BEGIN
            INSERT INTO messages_fts(body, sender_name, source_table, source_id, license_id)
            VALUES (new.body, new.sender_name, 'inbox', new.id, new.license_key_id);
        END;
    """)

    await execute_sql(db, """
        CREATE TRIGGER IF NOT EXISTS inbox_fts_delete AFTER DELETE ON inbox_messages
        BEGIN
            DELETE FROM messages_fts WHERE source_table = 'inbox' AND source_id = old.id;
        END;
    """)

    await execute_sql(db, """
        CREATE TRIGGER IF NOT EXISTS inbox_fts_update AFTER UPDATE ON inbox_messages
        BEGIN
            UPDATE messages_fts
            SET body = new.body, sender_name = new.sender_name
            WHERE source_table = 'inbox' AND source_id = new.id;
        END;
    """)

    # 3. Create Triggers for Outbox Messages
    await execute_sql(db, """
        CREATE TRIGGER IF NOT EXISTS outbox_fts_insert AFTER INSERT ON outbox_messages
        BEGIN
            INSERT INTO messages_fts(body, sender_name, source_table, source_id, license_id)
            VALUES (new.body, COALESCE(new.recipient_email, new.recipient_id), 'outbox', new.id, new.license_key_id);
        END;
    """)

    await execute_sql(db, """
        CREATE TRIGGER IF NOT EXISTS outbox_fts_delete AFTER DELETE ON outbox_messages
        BEGIN
            DELETE FROM messages_fts WHERE source_table = 'outbox' AND source_id = old.id;
        END;
    """)

    await execute_sql(db, """
        CREATE TRIGGER IF NOT EXISTS outbox_fts_update AFTER UPDATE ON outbox_messages
        BEGIN
            UPDATE messages_fts
            SET body = new.body, sender_name = COALESCE(new.recipient_email, new.recipient_id)
            WHERE source_table = 'outbox' AND source_id = new.id;
        END;
    """)

    # 4. Populate existing data (rebuild FTS index)
    logger.info("Populating FTS5 index from existing messages...")
    
    # Clear and rebuild - ensures index is consistent
    await execute_sql(db, "DELETE FROM messages_fts")

    await execute_sql(db, """
        INSERT INTO messages_fts(body, sender_name, source_table, source_id, license_id)
        SELECT body, sender_name, 'inbox', id, license_key_id FROM inbox_messages
        WHERE body IS NOT NULL
    """)

    await execute_sql(db, """
        INSERT INTO messages_fts(body, sender_name, source_table, source_id, license_id)
        SELECT body, COALESCE(recipient_email, recipient_id), 'outbox', id, license_key_id FROM outbox_messages
        WHERE body IS NOT NULL
    """)

    logger.info("SQLite FTS5 setup completed and populated.")


async def _setup_postgres_fts(db):
    """
    Setup Full Text Search for PostgreSQL using TSVECTOR.
    """
    # 1. Add search_vector column to inbox_messages
    try:
        await execute_sql(db, """
            ALTER TABLE inbox_messages 
            ADD COLUMN IF NOT EXISTS search_vector TSVECTOR
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS inbox_search_idx ON inbox_messages USING GIN(search_vector)
        """)
        # Update existing
        await execute_sql(db, """
            UPDATE inbox_messages 
            SET search_vector = to_tsvector('english', coalesce(body, '') || ' ' || coalesce(sender_name, ''))
            WHERE search_vector IS NULL
        """)
        
        # Trigger
        await execute_sql(db, """
            CREATE OR REPLACE FUNCTION inbox_tsvector_trigger() RETURNS trigger AS $$
            BEGIN
                new.search_vector := to_tsvector('english', coalesce(new.body, '') || ' ' || coalesce(new.sender_name, ''));
                RETURN new;
            END
            $$ LANGUAGE plpgsql;
        """)
        await execute_sql(db, """
            DROP TRIGGER IF EXISTS tsvectorupdate_inbox ON inbox_messages
        """)
        await execute_sql(db, """
            CREATE TRIGGER tsvectorupdate_inbox BEFORE INSERT OR UPDATE
            ON inbox_messages FOR EACH ROW EXECUTE PROCEDURE inbox_tsvector_trigger();
        """)
        
    except Exception as e:
        logger.error(f"Postgres Inbox FTS setup error: {e}")

    # 2. Add search_vector column to outbox_messages
    try:
        await execute_sql(db, """
            ALTER TABLE outbox_messages 
            ADD COLUMN IF NOT EXISTS search_vector TSVECTOR
        """)
        await execute_sql(db, """
            CREATE INDEX IF NOT EXISTS outbox_search_idx ON outbox_messages USING GIN(search_vector)
        """)
         # Update existing
        await execute_sql(db, """
            UPDATE outbox_messages 
            SET search_vector = to_tsvector('english', coalesce(body, '') || ' ' || coalesce(COALESCE(recipient_email, recipient_id), ''))
            WHERE search_vector IS NULL
        """)

        # Trigger
        await execute_sql(db, """
            CREATE OR REPLACE FUNCTION outbox_tsvector_trigger() RETURNS trigger AS $$
            BEGIN
                new.search_vector := to_tsvector('english', coalesce(new.body, '') || ' ' || coalesce(COALESCE(new.recipient_email, new.recipient_id), ''));
                RETURN new;
            END
            $$ LANGUAGE plpgsql;
        """)
        await execute_sql(db, """
            DROP TRIGGER IF EXISTS tsvectorupdate_outbox ON outbox_messages
        """)
        await execute_sql(db, """
            CREATE TRIGGER tsvectorupdate_outbox BEFORE INSERT OR UPDATE
            ON outbox_messages FOR EACH ROW EXECUTE PROCEDURE outbox_tsvector_trigger();
        """)

    except Exception as e:
        logger.error(f"Postgres Outbox FTS setup error: {e}")

    logger.info("PostgreSQL FTS setup completed.")
