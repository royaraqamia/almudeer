import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/local_database_service.dart';

class CustomersLocalDataSource {
  final LocalDatabaseService _dbService;

  CustomersLocalDataSource({LocalDatabaseService? dbService})
    : _dbService = dbService ?? LocalDatabaseService();

  Future<Database> get _db async => _dbService.database;

  /// Insert or Update a customer (Sync Down)
  Future<void> cacheCustomer(Map<String, dynamic> customer) async {
    final db = await _db;
    final remoteId = customer['id'] ?? customer['remote_id'];
    if (remoteId == null) return;

    // Check if customer exists to determine whether to insert or update
    final Map<String, dynamic> data = {
      'remote_id': remoteId,
      if (customer.containsKey('name')) 'name': customer['name'],
      if (customer.containsKey('phone')) 'phone': customer['phone'],
      if (customer.containsKey('last_contact_at'))
        'last_contact_at': customer['last_contact_at'],
      if (customer.containsKey('profile_pic_url') ||
          customer.containsKey('image'))
        'profile_pic_url': customer['profile_pic_url'] ?? customer['image'],
      if (customer.containsKey('is_vip'))
        'is_vip': (customer['is_vip'] == true) ? 1 : 0,
      if (customer.containsKey('has_whatsapp'))
        'has_whatsapp': (customer['has_whatsapp'] == true) ? 1 : 0,
      if (customer.containsKey('has_telegram'))
        'has_telegram': (customer['has_telegram'] == true) ? 1 : 0,
      if (customer.containsKey('username')) 'username': customer['username'],
      if (customer.containsKey('is_almudeer_user'))
        'is_almudeer_user':
            (customer['is_almudeer_user'] == true ||
                customer['is_almudeer_user'] == 1)
            ? 1
            : 0,
      if (customer.containsKey('isAlmudeerUser'))
        'is_almudeer_user': (customer['isAlmudeerUser'] == true) ? 1 : 0,
      'sync_status': 'synced',
      'dirty_fields': null,
    };

    // 1. Try matching by remote_id (the ideal case)
    final existingById = await db.query(
      'customers',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );

    if (existingById.isNotEmpty) {
      final existing = existingById.first;
      final syncStatus = existing['sync_status'] as String?;

      // If we have pending local edits, DO NOT overwrite the dirty fields with incoming server data
      // This prevents data loss when pulling down to refresh while offline edits are pending push
      if (syncStatus == 'dirty' || syncStatus == 'new') {
        try {
          final dirtyFieldsRaw = existing['dirty_fields'] as String?;
          if (dirtyFieldsRaw != null && dirtyFieldsRaw.isNotEmpty) {
            final dirtyFields = List<String>.from(jsonDecode(dirtyFieldsRaw));
            // Remove dirty keys from the incoming payload so we don't overwrite them
            data.removeWhere((key, value) => dirtyFields.contains(key));
          }
        } catch (e) {
          debugPrint('[CustomersLocalSync] Error parsing dirty fields: $e');
        }

        // Ensure we maintain the dirty status if there are still pending edits
        data['sync_status'] = syncStatus;
        data['dirty_fields'] = existing['dirty_fields'];
      }

      await db.update(
        'customers',
        data,
        where: 'remote_id = ?',
        whereArgs: [remoteId],
      );
      return;
    }

    // 2. SELF-HEALING: Try matching by phone/username if remote_id didn't match
    // This repairs records that were saved with the wrong ID (e.g. local ID instead of server ID)
    final phone = customer['phone'];
    if (phone != null && phone.isNotEmpty) {
      final existingByContact = await db.query(
        'customers',
        where: 'phone = ?',
        whereArgs: [phone],
      );

      if (existingByContact.isNotEmpty) {
        debugPrint(
          '[CustomersLocalSync] Found match by contact for remote_id $remoteId, repairing record...',
        );
        await db.update(
          'customers',
          data,
          where: 'local_id = ?',
          whereArgs: [existingByContact.first['local_id']],
        );
        return;
      }
    }

    // 3. If no match at all, insert as new
    await db.insert('customers', data);
  }

  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) async {
    final db = await _db;
    final batch = db.batch();

    // Pre-fetch all existing customers by remote_id to check sync_status
    final remoteIds = customers.map((c) => c['id']).whereType<int>().toList();
    final existingCustomers = <int, Map<String, dynamic>>{};

    if (remoteIds.isNotEmpty) {
      final placeholders = List.filled(remoteIds.length, '?').join(',');
      final existingRows = await db.query(
        'customers',
        where: 'remote_id IN ($placeholders)',
        whereArgs: remoteIds,
      );
      for (var row in existingRows) {
        if (row['remote_id'] != null) {
          existingCustomers[row['remote_id'] as int] = row;
        }
      }
    }

    for (var customer in customers) {
      final remoteId = customer['id'];
      final existing = existingCustomers[remoteId];
      final syncStatus = existing?['sync_status'] as String?;

      final data = {
        'remote_id': remoteId,
        'name': customer['name'],
        'phone': customer['phone'],
        'last_contact_at': customer['last_contact_at'],
        'profile_pic_url': customer['profile_pic_url'] ?? customer['image'],
        'is_vip': (customer['is_vip'] == true || customer['is_vip'] == 1)
            ? 1
            : 0,
        'has_whatsapp':
            (customer['has_whatsapp'] == true || customer['has_whatsapp'] == 1)
            ? 1
            : 0,
        'has_telegram':
            (customer['has_telegram'] == true || customer['has_telegram'] == 1)
            ? 1
            : 0,
        'username': customer['username'],
        'is_almudeer_user':
            (customer['is_almudeer_user'] == true ||
                customer['is_almudeer_user'] == 1 ||
                customer['isAlmudeerUser'] == true ||
                customer['isAlmudeerUser'] == 1)
            ? 1
            : 0,
        'sync_status': 'synced',
        'dirty_fields': null,
      };

      if (existing != null && (syncStatus == 'dirty' || syncStatus == 'new')) {
        try {
          final dirtyFieldsRaw = existing['dirty_fields'] as String?;
          if (dirtyFieldsRaw != null && dirtyFieldsRaw.isNotEmpty) {
            final dirtyFields = List<String>.from(jsonDecode(dirtyFieldsRaw));
            // Remove dirty keys from the incoming payload so we don't overwrite them
            data.removeWhere((key, value) => dirtyFields.contains(key));
          }
        } catch (e) {
          debugPrint(
            '[CustomersLocalSync] Error parsing dirty fields in batch: $e',
          );
        }

        // Ensure we maintain the dirty status if there are still pending edits
        data['sync_status'] = syncStatus;
        data['dirty_fields'] = existing['dirty_fields'];

        batch.update(
          'customers',
          data,
          where: 'remote_id = ?',
          whereArgs: [remoteId],
        );
      } else if (existing != null) {
        batch.update(
          'customers',
          data,
          where: 'remote_id = ?',
          whereArgs: [remoteId],
        );
      } else {
        batch.insert('customers', data);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Create new customer locally (Offline Add)
  Future<int> addCustomerLocally(Map<String, dynamic> data) async {
    final db = await _db;
    return await db.insert('customers', {
      'name': data['name'],
      'phone': data['phone'],
      'has_whatsapp': (data['has_whatsapp'] == true) ? 1 : 0,
      'has_telegram': (data['has_telegram'] == true) ? 1 : 0,
      'username': data['username'],
      'sync_status': 'new',
      'last_updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Update customer locally (Offline Edit / Optimistic UI)
  Future<void> updateCustomerLocally(
    int remoteId,
    Map<String, dynamic> updates,
  ) async {
    final db = await _db;

    // Get existing dirty fields
    final List<Map<String, dynamic>> result = await db.query(
      'customers',
      columns: ['dirty_fields'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );

    List<String> dirtyFields = [];
    if (result.isNotEmpty && result.first['dirty_fields'] != null) {
      try {
        dirtyFields = List<String>.from(
          jsonDecode(result.first['dirty_fields'] as String),
        );
      } catch (_) {}
    }

    // Add new fields to dirty list
    final newKeys = updates.keys.toList();
    for (var key in newKeys) {
      if (!dirtyFields.contains(key)) {
        dirtyFields.add(key);
      }
    }

    // Prepare update payload
    final Map<String, dynamic> sqlUpdates = {
      ...updates,
      'sync_status': 'dirty',
      'dirty_fields': jsonEncode(dirtyFields),
      'last_updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    // Convert boolean to int if present
    if (sqlUpdates.containsKey('is_vip')) {
      sqlUpdates['is_vip'] =
          (sqlUpdates['is_vip'] == true || sqlUpdates['is_vip'] == 1) ? 1 : 0;
    }
    if (sqlUpdates.containsKey('has_whatsapp')) {
      sqlUpdates['has_whatsapp'] =
          (sqlUpdates['has_whatsapp'] == true ||
              sqlUpdates['has_whatsapp'] == 1)
          ? 1
          : 0;
    }
    if (sqlUpdates.containsKey('has_telegram')) {
      sqlUpdates['has_telegram'] =
          (sqlUpdates['has_telegram'] == true ||
              sqlUpdates['has_telegram'] == 1)
          ? 1
          : 0;
    }

    if (sqlUpdates.containsKey('is_almudeer_user')) {
      sqlUpdates['is_almudeer_user'] =
          (sqlUpdates['is_almudeer_user'] == true ||
              sqlUpdates['is_almudeer_user'] == 1)
          ? 1
          : 0;
    }
    if (sqlUpdates.containsKey('isAlmudeerUser')) {
      sqlUpdates['is_almudeer_user'] =
          (sqlUpdates['isAlmudeerUser'] == true ||
              sqlUpdates['isAlmudeerUser'] == 1)
          ? 1
          : 0;
      sqlUpdates.remove('isAlmudeerUser'); // Normalize to snake_case for DB
    }

    await db.update(
      'customers',
      sqlUpdates,
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Get all customers (Local Cache)
  Future<List<Map<String, dynamic>>> getCustomers({
    String? search,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await _db;
    String whereClause = '1=1'; // Always true
    final List<dynamic> whereArgs = [];

    if (search != null && search.isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR phone LIKE ? OR username LIKE ?)';
      whereArgs.add('%$search%');
      whereArgs.add('%$search%');
      whereArgs.add('%$search%');
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'last_contact_at DESC', // Or last_updated_at
      limit: limit,
      offset: offset,
    );

    return maps;
  }

  /// Check if a customer exists by phone or username (Optimized for speed)
  Future<bool> existsByContact({String? phone}) async {
    if (phone == null || phone.isEmpty) {
      return false;
    }

    final db = await _db;
    final result = await db.query(
      'customers',
      columns: ['local_id'],
      where: 'phone = ?',
      whereArgs: [phone],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// Get all customer phone numbers for duplicate detection (Bulk operations)
  /// For single existence checks, use [existsByContact]
  Future<Set<String>> getAllCustomerPhones() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      columns: ['phone'],
    );
    return maps
        .map((e) => e['phone']?.toString() ?? '')
        .where((phone) => phone.isNotEmpty)
        .toSet();
  }

  /// Get single customer
  Future<Map<String, dynamic>?> getCustomer(int remoteId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  /// Look up a customer by phone or username
  Future<Map<String, dynamic>?> getCustomerByContact({
    String? phone,
    String? username,
  }) async {
    if ((phone == null || phone.isEmpty) &&
        (username == null || username.isEmpty)) {
      return null;
    }

    final db = await _db;
    String whereClause = '';
    final List<dynamic> whereArgs = [];

    if (phone != null && phone.isNotEmpty) {
      whereClause = 'phone = ?';
      whereArgs.add(phone);
    }

    if (username != null && username.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' OR ';
      whereClause += 'username = ?';
      whereArgs.add(username);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  /// Get pending operations (for SyncService)
  Future<List<Map<String, dynamic>>> getPendingCustomers() async {
    final db = await _db;
    return await db.query(
      'customers',
      where: 'sync_status IN (?, ?)',
      whereArgs: ['new', 'dirty'],
    );
  }

  /// Mark as Synced (after successful upload)
  Future<void> markAsSynced(int localId, {int? remoteId}) async {
    final db = await _db;
    final Map<String, dynamic> updates = {
      'sync_status': 'synced',
      'dirty_fields': null,
    };

    if (remoteId != null) {
      updates['remote_id'] = remoteId;
    }

    await db.update(
      'customers',
      updates,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Delete customer locally
  Future<void> deleteCustomerLocally(int remoteId) async {
    final db = await _db;
    await db.delete('customers', where: 'remote_id = ?', whereArgs: [remoteId]);
  }

  /// Delete multiple customers locally
  Future<void> deleteCustomersLocally(List<int> remoteIds) async {
    if (remoteIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(remoteIds.length, '?').join(',');
    await db.delete(
      'customers',
      where: 'remote_id IN ($placeholders)',
      whereArgs: remoteIds,
    );
  }

  /// Clear all synced customers that are NOT in the provided server data
  /// This prevents deleting valid customers while cleaning up truly orphaned records
  Future<void> clearSyncedCustomers({List<int>? serverCustomerIds}) async {
    final db = await _db;

    // If we have the server's customer list, only delete records NOT in that list
    if (serverCustomerIds != null && serverCustomerIds.isNotEmpty) {
      // Delete synced customers whose remote_id is NOT in the server list
      final placeholders = List.filled(serverCustomerIds.length, '?').join(',');
      final deleted = await db.delete(
        'customers',
        where: 'sync_status = ? AND remote_id NOT IN ($placeholders)',
        whereArgs: ['synced', ...serverCustomerIds],
      );
      debugPrint(
        '[CustomersLocalDataSource] Purged $deleted truly orphaned local records.',
      );
    } else {
      // Fallback: Clear all synced (old behavior - use with caution)
      // This is safe only when called AFTER caching fresh server data
      final deleted = await db.delete(
        'customers',
        where: 'sync_status = ?',
        whereArgs: ['synced'],
      );
      debugPrint(
        '[CustomersLocalDataSource] Purged $deleted orphaned local records (full cleanup).',
      );
    }
  }
}
