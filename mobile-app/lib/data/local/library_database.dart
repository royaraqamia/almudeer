import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/library_item.dart';

/// Library Database - Local caching and offline action queue
///
/// Fixes applied:
/// - Issue #13: Added is_pending_delete column for safe deletes
/// - Issue #17: Fixed memory leak potential with proper cleanup
/// - P0-3: Added cached_at column and cache TTL validation
/// - FIX #7: Adaptive cache TTL based on connectivity (longer when offline)
class LibraryDatabase {
  static final LibraryDatabase _instance = LibraryDatabase._internal();
  static Database? _database;

  factory LibraryDatabase() => _instance;

  LibraryDatabase._internal();

  // FIX #7: Adaptive cache TTL - longer when offline to support offline scenarios
  // Standard TTL when online: 60 seconds for fresh data
  // Extended TTL when offline: 5 minutes to prevent "no data" states
  static const Duration _cacheTTLOnline = Duration(seconds: 60);
  static const Duration _cacheTTLOffline = Duration(minutes: 5);
  
  // Track last known connectivity state
  static bool _isOnline = true;
  
  /// Set connectivity state to adjust cache TTL dynamically
  static void setConnectivityState(bool isOnline) {
    _isOnline = isOnline;
  }
  
  /// Get current cache TTL based on connectivity state
  static Duration get _currentCacheTTL => _isOnline ? _cacheTTLOnline : _cacheTTLOffline;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'library.db');

    return await openDatabase(
      path,
      version: 8, // Added created_by column for library sharing
      onCreate: (db, version) async {
        // Table for caching library items
        await db.execute('''
          CREATE TABLE c_library_items (
            id INTEGER PRIMARY KEY,
            license_key_id INTEGER,
            customer_id INTEGER,
            type TEXT,
            title TEXT,
            content TEXT,
            file_path TEXT,
            file_size INTEGER,
            mime_type TEXT,
            created_at TEXT,
            updated_at TEXT,
            is_uploading INTEGER DEFAULT 0,
            upload_progress REAL DEFAULT 0.0,
            is_synced INTEGER DEFAULT 1,
            is_pending_delete INTEGER DEFAULT 0,
            has_error INTEGER DEFAULT 0,
            is_downloading INTEGER DEFAULT 0,
            download_progress REAL DEFAULT 0.0,
            local_path TEXT,
            user_id TEXT,
            created_by TEXT,
            is_shared INTEGER DEFAULT 0,
            shared_with TEXT,
            permission TEXT,
            share_permission TEXT,
            original_file_path TEXT,
            cached_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');

        // Issue #20: Performance indexes for common queries
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_library_license_id
          ON c_library_items(license_key_id)
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_library_type
          ON c_library_items(type)
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_library_created_at
          ON c_library_items(created_at DESC)
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_library_pending_delete
          ON c_library_items(is_pending_delete)
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_library_synced
          ON c_library_items(is_synced)
        ''');

        // Composite index for common query pattern
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_library_license_type_pending
          ON c_library_items(license_key_id, type, is_pending_delete)
        ''');

        // Table for pending offline actions
        await db.execute('''
          CREATE TABLE c_pending_actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT, -- 'create', 'update', 'delete', 'upload'
            item_type TEXT,
            payload TEXT, -- JSON string of data
            local_id INTEGER, -- temporary ID for optimistic UI
            created_at TEXT
          )
        ''');

        // Index for pending actions by action type
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_pending_action_type
          ON c_pending_actions(action_type)
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_pending_local_id
          ON c_pending_actions(local_id)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Issue #13: Add is_pending_delete column
        if (oldVersion < 3) {
          // Check if column already exists (defensive)
          final columns = await db.rawQuery(
            'PRAGMA table_info(c_library_items)',
          );
          final hasPendingDelete = columns.any(
            (col) => col['name'] == 'is_pending_delete',
          );

          if (!hasPendingDelete) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN is_pending_delete INTEGER DEFAULT 0',
            );
          }

          // Also ensure previous columns exist
          final hasUploading = columns.any(
            (col) => col['name'] == 'is_uploading',
          );
          final hasProgress = columns.any(
            (col) => col['name'] == 'upload_progress',
          );

          if (!hasUploading) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN is_uploading INTEGER DEFAULT 0',
            );
          }
          if (!hasProgress) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN upload_progress REAL DEFAULT 0.0',
            );
          }
        }

        // Issue #20: Add has_error column and performance indexes
        if (oldVersion < 4) {
          // Add has_error column
          final columns = await db.rawQuery(
            'PRAGMA table_info(c_library_items)',
          );
          final hasError = columns.any((col) => col['name'] == 'has_error');

          if (!hasError) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN has_error INTEGER DEFAULT 0',
            );
          }

          // Create performance indexes (IF NOT EXISTS handles duplicates)
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_license_id
            ON c_library_items(license_key_id)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_type
            ON c_library_items(type)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_created_at
            ON c_library_items(created_at DESC)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_pending_delete
            ON c_library_items(is_pending_delete)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_synced
            ON c_library_items(is_synced)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_license_type_pending
            ON c_library_items(license_key_id, type, is_pending_delete)
          ''');
        }

        // P0-3: Add cached_at column for cache TTL
        if (oldVersion < 5) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(c_library_items)',
          );
          final hasCachedAt = columns.any((col) => col['name'] == 'cached_at');

          if (!hasCachedAt) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN cached_at TEXT DEFAULT CURRENT_TIMESTAMP',
            );
          }
          
          // PERF-004 FIX: Add index on cached_at for faster cache expiration checks
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_library_cached_at
            ON c_library_items(cached_at DESC)
          ''');
        }

        // Fix: Add missing columns for download & sharing
        if (oldVersion < 6) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(c_library_items)',
          );
          final columnNames = columns
              .map((col) => col['name'] as String)
              .toSet();

          // Add download-related columns
          if (!columnNames.contains('is_downloading')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN is_downloading INTEGER DEFAULT 0',
            );
          }
          if (!columnNames.contains('download_progress')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN download_progress REAL DEFAULT 0.0',
            );
          }
          if (!columnNames.contains('local_path')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN local_path TEXT',
            );
          }

          // Add sharing-related columns
          if (!columnNames.contains('user_id')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN user_id TEXT',
            );
          }
          if (!columnNames.contains('is_shared')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN is_shared INTEGER DEFAULT 0',
            );
          }
          if (!columnNames.contains('shared_with')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN shared_with TEXT',
            );
          }
          if (!columnNames.contains('permission')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN permission TEXT',
            );
          }
          if (!columnNames.contains('original_file_path')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN original_file_path TEXT',
            );
          }
        }

        // Add share_permission column
        if (oldVersion < 7) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(c_library_items)',
          );
          final columnNames = columns
              .map((col) => col['name'] as String)
              .toSet();

          if (!columnNames.contains('share_permission')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN share_permission TEXT',
            );
          }
        }

        // Add created_by column for library sharing (P3-14)
        if (oldVersion < 8) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(c_library_items)',
          );
          final columnNames = columns
              .map((col) => col['name'] as String)
              .toSet();

          if (!columnNames.contains('created_by')) {
            await db.execute(
              'ALTER TABLE c_library_items ADD COLUMN created_by TEXT',
            );
          }
        }
      },
    );
  }

  // --- Caching Methods ---

  // P0-3: Check if cache is valid (not expired)
  // FIX #7: Uses adaptive TTL based on connectivity state
  Future<bool> isCacheValid({required int licenseKeyId, String? type}) async {
    final db = await database;

    // Get the most recent cache timestamp for this license
    final result = await db.query(
      'c_library_items',
      columns: ['MAX(cached_at) as latest_cache'],
      where: 'license_key_id = ?',
      whereArgs: [licenseKeyId],
    );

    if (result.isEmpty || result.first['latest_cache'] == null) {
      return false; // No cache exists
    }

    try {
      final lastCacheTime = DateTime.parse(
        result.first['latest_cache'] as String,
      );
      final age = DateTime.now().difference(lastCacheTime);
      // FIX #7: Use adaptive TTL based on connectivity
      return age < _currentCacheTTL;
    } catch (e) {
      return false; // Invalid timestamp
    }
  }

  Future<void> cacheItems(List<LibraryItem> items, {bool force = false}) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    final pendingItemIds = <int>{};
    if (!force) {
      // Get IDs of items with pending updates/deletes to avoid overwriting them with old remote data
      final pendingActions = await db.query(
        'c_pending_actions',
        columns: ['payload', 'action_type', 'local_id'],
      );

      for (var action in pendingActions) {
        if (action['action_type'] == 'update' ||
            action['action_type'] == 'delete') {
          try {
            final payload = jsonDecode(action['payload'] as String);
            if (payload['id'] != null) {
              pendingItemIds.add(payload['id'] as int);
            }
          } catch (_) {}
        } else if (action['action_type'] == 'create' &&
            action['local_id'] != null) {
          // Identify pending creations by local_id to avoid overwriting them during sync
          pendingItemIds.add(action['local_id'] as int);
        }
      }
    }

    // We replace existing items or insert new ones, respecting pending changes
    for (var item in items) {
      if (!force && pendingItemIds.contains(item.id)) {
        // Skip overwriting this item as we have a local pending change
        continue;
      }

      batch.insert('c_library_items', {
        ...item.toJson(),
        'is_synced': 1,
        'cached_at': now, // P0-3: Set cache timestamp
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<LibraryItem>> getCachedItems({
    required int licenseKeyId,
    String? type,
  }) async {
    final db = await database;
    final List<String> conditions = ['license_key_id = ?'];
    final List<dynamic> whereArgs = [licenseKeyId];

    if (type != null && type != 'all') {
      if (type == 'notes' || type == 'note') {
        conditions.add('type = ?');
        whereArgs.add('note');
      } else if (type == 'files') {
        conditions.add("type IN ('image', 'audio', 'video', 'file')");
      } else if (type == 'tools') {
        conditions.add('type = ?');
        whereArgs.add('tool');
      } else {
        // Fallback for specific other types if needed
        conditions.add('type = ?');
        whereArgs.add(type);
      }
    }

    // Issue #13: Filter out items marked for pending deletion
    conditions.add('is_pending_delete = 0');

    final List<Map<String, dynamic>> maps = await db.query(
      'c_library_items',
      where: conditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      final data = Map<String, dynamic>.from(maps[i]);
      // Remove DB specific fields if not in model, or ignore extra keys
      return LibraryItem.fromJson(data);
    });
  }

  Future<void> updateItem(int id, Map<String, dynamic> updates) async {
    final db = await database;

    // FIX: Convert boolean values to integers (1/0) as SQLite doesn't support booleans
    final sanitizedUpdates = <String, dynamic>{};
    for (final entry in updates.entries) {
      if (entry.value is bool) {
        sanitizedUpdates[entry.key] = entry.value == true ? 1 : 0;
      } else {
        sanitizedUpdates[entry.key] = entry.value;
      }
    }

    await db.update(
      'c_library_items',
      {...sanitizedUpdates, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Issue #13: Delete item from cache (only after successful sync)
  Future<void> deleteItem(int id) async {
    final db = await database;
    await db.delete('c_library_items', where: 'id = ?', whereArgs: [id]);
  }

  /// Issue #13: Check if item exists in cache
  Future<bool> itemExists(int id) async {
    final db = await database;
    final result = await db.query(
      'c_library_items',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty;
  }

  Future<void> clearCache() async {
    final db = await database;
    await db.delete('c_library_items');
  }

  // --- Offline Actions Methods ---

  Future<int> addPendingAction({
    required String actionType,
    required String itemType,
    required Map<String, dynamic> payload,
    int? localId,
  }) async {
    final db = await database;
    return await db.insert('c_pending_actions', {
      'action_type': actionType,
      'item_type': itemType,
      'payload': jsonEncode(payload),
      'local_id': localId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final db = await database;
    return await db.query('c_pending_actions', orderBy: 'created_at ASC');
  }

  Future<void> removePendingAction(int id) async {
    final db = await database;
    await db.delete('c_pending_actions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> removePendingCreateAction(int localId) async {
    final db = await database;
    return await db.delete(
      'c_pending_actions',
      where: "action_type = 'create' AND local_id = ?",
      whereArgs: [localId],
    );
  }

  /// Get all cached items with optional license filtering (Useful for keyboard global access)
  /// Now supports pagination and optional search filter.
  /// FIX Issue #23: Added licenseKeyId parameter for proper filtering
  Future<List<LibraryItem>> getAllCachedItems({
    int? licenseKeyId,
    int limit = 50,
    int offset = 0,
    String? query,
  }) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;

    // FIX Issue #23: Filter by license key if provided
    if (licenseKeyId != null) {
      where = 'license_key_id = ?';
      whereArgs = [licenseKeyId];

      if (query != null && query.isNotEmpty) {
        where += ' AND (title LIKE ? OR content LIKE ?)';
        whereArgs.addAll(['%$query%', '%$query%']);
      }
    } else if (query != null && query.isNotEmpty) {
      where = 'title LIKE ? OR content LIKE ?';
      whereArgs = ['%$query%', '%$query%'];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'c_library_items',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) {
      return LibraryItem.fromJson(maps[i]);
    });
  }
}
