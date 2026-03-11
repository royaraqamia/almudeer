import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../api/api_client.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  static Database? _database;
  static String? _currentAccountHash;

  factory LocalDatabaseService() {
    return _instance;
  }

  LocalDatabaseService._internal();

  /// Get the singleton database instance.
  /// Re-initializes if the account hash changes (multi-tenant support).
  Future<Database> get database async {
    final newHash = await ApiClient().getAccountCacheHash();

    // If account changed, close old connection
    if (_database != null && _currentAccountHash != newHash) {
      await _database!.close();
      _database = null;
    }

    if (_database != null) return _database!;

    _currentAccountHash = newHash;
    _database = await _initDB(newHash);
    return _database!;
  }

  Future<Database> _initDB(String hash) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'almudeer_$hash.db');

    debugPrint('[DB] Initializing database for hash: $hash');

    // Open/Create the database first so we can check its content
    final Database db = await openDatabase(
      path,
      version: 22, // Added share_permission to CREATE TABLE and migration
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );

    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Customers Table
    await db.execute('''
      CREATE TABLE customers (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id INTEGER UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        last_contact_at TEXT,
        profile_pic_url TEXT,
        is_vip INTEGER DEFAULT 0,
        has_whatsapp INTEGER DEFAULT 0,
        has_telegram INTEGER DEFAULT 0,

        -- Sync Fields
        sync_status TEXT DEFAULT 'synced', -- 'synced', 'dirty', 'new', 'deleted'
        last_updated_at INTEGER,
        dirty_fields TEXT, -- JSON list of fields changed offline
        username TEXT,
        is_almudeer_user INTEGER DEFAULT 0
      )
    ''');

    // 2. Inbox Messages Table (Active Context)
    await db.execute('''
      CREATE TABLE inbox_messages (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id INTEGER UNIQUE,
        sender_contact TEXT NOT NULL,
        channel TEXT,
        body TEXT,
        media_url TEXT,
        created_at TEXT,
        status TEXT, -- 'unread', 'read', 'replied'
        intent TEXT,

        -- Reply Fields
        reply_to_id INTEGER,
        reply_to_platform_id TEXT,
        reply_to_body_preview TEXT,
        reply_to_sender_name TEXT,

        -- Sync Fields
        sync_status TEXT DEFAULT 'synced',
        last_updated_at INTEGER,
        attachments TEXT, -- JSON string for attachments
        is_forwarded INTEGER DEFAULT 0,
        
        -- P1-1 FIX: Retry tracking for offline message send
        retry_count INTEGER DEFAULT 0,
        last_retry_at INTEGER,
        max_retries INTEGER DEFAULT 3,

        -- v9 Fields
        sender_name TEXT,
        channel_message_id TEXT,
        platform_message_id TEXT,
        direction TEXT DEFAULT 'incoming',

        -- v12 Fields
        edited_at TEXT
      )
    ''');

    // 3. Sync Queue (For robust offline operations)
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL, -- 'POST', 'PATCH', 'DELETE'
        payload TEXT, -- JSON body
        retry_count INTEGER DEFAULT 0,
        created_at INTEGER,
        last_attempt_at INTEGER
      )
    ''');

    // 4. Tasks Table (Migrated from feature-specific DB)
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        is_completed INTEGER NOT NULL,
        due_date INTEGER,
        priority INTEGER DEFAULT 0,
        color INTEGER,
        sub_tasks TEXT,
        alarm_enabled INTEGER NOT NULL DEFAULT 0,
        alarm_time INTEGER,
        recurrence TEXT,
        category TEXT,
        order_index REAL DEFAULT 0.0,
        created_by TEXT,
        assigned_to TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        is_synced INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        attachments TEXT,
        visibility TEXT DEFAULT 'shared',
        share_permission TEXT
      )
    ''');

    // 5. Task Comments Table
    await db.execute('''
      CREATE TABLE task_comments (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT,
        content TEXT NOT NULL,
        attachments TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
      )
    ''');

    // 7. Indexes for Keyboard Performance
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // ... (previous upgrade logic)
    if (oldVersion < 20) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
      );
    }
    final columns = await db.rawQuery('PRAGMA table_info(customers)');
    final columnNames = columns.map((c) => c['name']).toSet();

    if (oldVersion < 2) {
      if (!columnNames.contains('has_whatsapp')) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN has_whatsapp INTEGER DEFAULT 0',
        );
      }
      if (!columnNames.contains('has_telegram')) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN has_telegram INTEGER DEFAULT 0',
        );
      }
    }

    // Versions 3 and 4 both introduced/checked for 'username'
    if (oldVersion < 4) {
      if (!columnNames.contains('username')) {
        await db.execute('ALTER TABLE customers ADD COLUMN username TEXT');
      }
    }

    if (oldVersion < 5) {
      if (!columnNames.contains('is_almudeer_user')) {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN is_almudeer_user INTEGER DEFAULT 0',
        );
      }
    }

    if (oldVersion < 6) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('reply_to_id')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN reply_to_id INTEGER',
        );
      }
      if (!inboxColumnNames.contains('reply_to_platform_id')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN reply_to_platform_id TEXT',
        );
      }
      if (!inboxColumnNames.contains('reply_to_body_preview')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN reply_to_body_preview TEXT',
        );
      }
      if (!inboxColumnNames.contains('reply_to_sender_name')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN reply_to_sender_name TEXT',
        );
      }
    }

    if (oldVersion < 7) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('attachments')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN attachments TEXT',
        );
      }
    }

    if (oldVersion < 8) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('is_forwarded')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN is_forwarded INTEGER DEFAULT 0',
        );
      }
    }
    if (oldVersion < 9) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('sender_name')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN sender_name TEXT',
        );
      }
      if (!inboxColumnNames.contains('channel_message_id')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN channel_message_id TEXT',
        );
      }
      if (!inboxColumnNames.contains('platform_message_id')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN platform_message_id TEXT',
        );
      }
      if (!inboxColumnNames.contains('direction')) {
        await db.execute(
          "ALTER TABLE inbox_messages ADD COLUMN direction TEXT DEFAULT 'incoming'",
        );
      }
    }

    if (oldVersion < 10) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('intent')) {
        await db.execute('ALTER TABLE inbox_messages ADD COLUMN intent TEXT');
      }
    }

    if (oldVersion < 11) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();

      if (!taskColumnNames.contains('alarm_enabled')) {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN alarm_enabled INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!taskColumnNames.contains('alarm_time')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN alarm_time INTEGER');
      }
    }

    if (oldVersion < 12) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('edited_at')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN edited_at TEXT',
        );
      }
    }

    if (oldVersion < 14) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();

      if (!taskColumnNames.contains('category')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN category TEXT');
      }
      if (!taskColumnNames.contains('order_index')) {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN order_index REAL DEFAULT 0.0',
        );
      }
      // sub_tasks column already exists but we'll ensure it just in case of inconsistency
      if (!taskColumnNames.contains('sub_tasks')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN sub_tasks TEXT');
      }
    }
    if (oldVersion < 15) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();

      if (!taskColumnNames.contains('created_by')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN created_by TEXT');
      }
      if (!taskColumnNames.contains('assigned_to')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN assigned_to TEXT');
      }
    }

    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS task_comments (
          id TEXT PRIMARY KEY,
          task_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          user_name TEXT,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 17) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();
      if (!taskColumnNames.contains('attachments')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN attachments TEXT');
      }

      final commentColumns = await db.rawQuery(
        'PRAGMA table_info(task_comments)',
      );
      final commentColumnNames = commentColumns.map((c) => c['name']).toSet();
      if (!commentColumnNames.contains('attachments')) {
        await db.execute(
          'ALTER TABLE task_comments ADD COLUMN attachments TEXT',
        );
      }
    }
    if (oldVersion < 19) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();
      if (!taskColumnNames.contains('visibility')) {
        await db.execute(
          "ALTER TABLE tasks ADD COLUMN visibility TEXT DEFAULT 'shared'",
        );
      }
    }

    // P1-1 FIX: Add retry tracking columns for offline message send
    if (oldVersion < 20) {
      final inboxColumns = await db.rawQuery(
        'PRAGMA table_info(inbox_messages)',
      );
      final inboxColumnNames = inboxColumns.map((c) => c['name']).toSet();

      if (!inboxColumnNames.contains('retry_count')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN retry_count INTEGER DEFAULT 0',
        );
      }
      if (!inboxColumnNames.contains('last_retry_at')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN last_retry_at INTEGER',
        );
      }
      if (!inboxColumnNames.contains('max_retries')) {
        await db.execute(
          'ALTER TABLE inbox_messages ADD COLUMN max_retries INTEGER DEFAULT 3',
        );
      }
    }

    // Add share_permission column for shared tasks
    if (oldVersion < 21) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();
      if (!taskColumnNames.contains('share_permission')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN share_permission TEXT');
      }
    }

    // Version 22: Ensure share_permission column exists (fix for fresh installs at v21)
    if (oldVersion < 22) {
      final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
      final taskColumnNames = taskColumns.map((c) => c['name']).toSet();
      if (!taskColumnNames.contains('share_permission')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN share_permission TEXT');
      }
    }
  }
}
