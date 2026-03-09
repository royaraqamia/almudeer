import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/transfer_models.dart';

/// Database for persisting transfer sessions and history
class TransferDatabase {
  static final TransferDatabase _instance = TransferDatabase._internal();
  factory TransferDatabase() => _instance;
  TransferDatabase._internal();

  Database? _database;
  bool _isInitialized = false;

  // Database configuration
  static const String _databaseName = 'transfer_database.db';
  static const int _databaseVersion = 1;

  // Table names
  static const String _tableSessions = 'transfer_sessions';
  static const String _tableChunks = 'transfer_chunks';
  static const String _tableDevices = 'transfer_devices';
  static const String _tableHistory = 'transfer_history';

  Future<void> initialize() async {
    if (_isInitialized) return;

    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, _databaseName);

    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    _isInitialized = true;
    debugPrint('[TransferDatabase] Initialized at $path');
  }

  Future<void> _onCreate(Database db, int version) async {
    // Transfer sessions table
    await db.execute('''
      CREATE TABLE $_tableSessions (
        session_id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        direction TEXT NOT NULL,
        state TEXT NOT NULL,
        metadata TEXT NOT NULL,
        completed_chunks INTEGER DEFAULT 0,
        failed_chunks INTEGER DEFAULT 0,
        started_at TEXT,
        completed_at TEXT,
        last_activity_at TEXT,
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        bytes_transferred INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // File chunks table for resume capability
    await db.execute('''
      CREATE TABLE $_tableChunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        start_byte INTEGER NOT NULL,
        end_byte INTEGER NOT NULL,
        checksum TEXT,
        is_received INTEGER DEFAULT 0,
        received_at TEXT,
        FOREIGN KEY (session_id) REFERENCES $_tableSessions(session_id) ON DELETE CASCADE
      )
    ''');

    // Known devices table
    await db.execute('''
      CREATE TABLE $_tableDevices (
        device_id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL,
        model TEXT,
        platform TEXT,
        endpoint_id TEXT,
        is_trusted INTEGER DEFAULT 0,
        discovered_at TEXT NOT NULL,
        last_connected_at TEXT,
        connection_count INTEGER DEFAULT 0,
        failed_connections INTEGER DEFAULT 0
      )
    ''');

    // Transfer history table
    await db.execute('''
      CREATE TABLE $_tableHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        file_type TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        completed_at TEXT,
        duration_seconds INTEGER,
        error_message TEXT
      )
    ''');

    // Indexes for performance
    await db.execute(
      'CREATE INDEX idx_chunks_session ON $_tableChunks(session_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sessions_state ON $_tableSessions(state)',
    );
    await db.execute(
      'CREATE INDEX idx_history_device ON $_tableHistory(device_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here
  }

  // ==================== SESSION OPERATIONS ====================

  Future<void> saveSession(TransferSession session) async {
    await _ensureInitialized();
    final db = _database!;

    await db.transaction((txn) async {
      await txn.insert(_tableSessions, {
        'session_id': session.sessionId,
        'device_id': session.deviceId,
        'device_name': session.deviceName,
        'direction': session.direction.name,
        'state': session.state.name,
        'metadata': jsonEncode(session.metadata.toJson()),
        'completed_chunks': session.completedChunks,
        'failed_chunks': session.failedChunks,
        'started_at': session.startedAt?.toIso8601String(),
        'completed_at': session.completedAt?.toIso8601String(),
        'last_activity_at': session.lastActivityAt?.toIso8601String(),
        'error_message': session.errorMessage,
        'retry_count': session.retryCount,
        'bytes_transferred': session.bytesTransferred,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Save chunks
      await txn.delete(
        _tableChunks,
        where: 'session_id = ?',
        whereArgs: [session.sessionId],
      );

      for (final chunk in session.chunks) {
        await txn.insert(_tableChunks, {
          'session_id': session.sessionId,
          'chunk_index': chunk.index,
          'start_byte': chunk.startByte,
          'end_byte': chunk.endByte,
          'checksum': chunk.checksum,
          'is_received': chunk.isReceived ? 1 : 0,
          'received_at': chunk.receivedAt?.toIso8601String(),
        });
      }
    });
  }

  Future<TransferSession?> getSession(String sessionId) async {
    await _ensureInitialized();
    final db = _database!;

    final sessionResult = await db.query(
      _tableSessions,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    if (sessionResult.isEmpty) return null;

    final sessionData = sessionResult.first;
    final chunksResult = await db.query(
      _tableChunks,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    final chunks = chunksResult
        .map(
          (c) => FileChunk(
            index: c['chunk_index'] as int,
            startByte: c['start_byte'] as int,
            endByte: c['end_byte'] as int,
            checksum: c['checksum'] as String?,
            isReceived: (c['is_received'] as int) == 1,
            receivedAt: c['received_at'] != null
                ? DateTime.parse(c['received_at'] as String)
                : null,
          ),
        )
        .toList();

    return TransferSession(
      sessionId: sessionData['session_id'] as String,
      deviceId: sessionData['device_id'] as String,
      deviceName: sessionData['device_name'] as String,
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == sessionData['direction'],
      ),
      state: TransferState.values.firstWhere(
        (s) => s.name == sessionData['state'],
      ),
      metadata: TransferMetadata.fromJson(
        jsonDecode(sessionData['metadata'] as String),
      ),
      chunks: chunks,
      completedChunks: sessionData['completed_chunks'] as int,
      failedChunks: sessionData['failed_chunks'] as int,
      startedAt: sessionData['started_at'] != null
          ? DateTime.parse(sessionData['started_at'] as String)
          : null,
      completedAt: sessionData['completed_at'] != null
          ? DateTime.parse(sessionData['completed_at'] as String)
          : null,
      lastActivityAt: sessionData['last_activity_at'] != null
          ? DateTime.parse(sessionData['last_activity_at'] as String)
          : null,
      errorMessage: sessionData['error_message'] as String?,
      retryCount: sessionData['retry_count'] as int,
      bytesTransferred: sessionData['bytes_transferred'] as int,
    );
  }

  Future<List<TransferSession>> getActiveSessions() async {
    await _ensureInitialized();
    final db = _database!;

    final results = await db.query(
      _tableSessions,
      where: 'state IN (?, ?, ?)',
      whereArgs: [
        TransferState.pending.name,
        TransferState.connecting.name,
        TransferState.transferring.name,
      ],
      orderBy: 'last_activity_at DESC',
    );

    final sessions = <TransferSession>[];
    for (final row in results) {
      final session = await getSession(row['session_id'] as String);
      if (session != null) sessions.add(session);
    }

    return sessions;
  }

  Future<List<TransferSession>> getResumableSessions() async {
    await _ensureInitialized();
    final db = _database!;

    final results = await db.query(
      _tableSessions,
      where: 'state IN (?, ?) AND retry_count < ?',
      whereArgs: [
        TransferState.paused.name,
        TransferState.failed.name,
        5, // Max retries
      ],
      orderBy: 'last_activity_at DESC',
    );

    final sessions = <TransferSession>[];
    for (final row in results) {
      final session = await getSession(row['session_id'] as String);
      if (session != null && session.canResume) sessions.add(session);
    }

    return sessions;
  }

  Future<void> updateSessionState(
    String sessionId,
    TransferState state, {
    String? errorMessage,
  }) async {
    await _ensureInitialized();
    final db = _database!;

    final updates = <String, dynamic>{
      'state': state.name,
      'last_activity_at': DateTime.now().toIso8601String(),
    };

    if (errorMessage != null) {
      updates['error_message'] = errorMessage;
    }

    if (state == TransferState.completed) {
      updates['completed_at'] = DateTime.now().toIso8601String();
    }

    await db.update(
      _tableSessions,
      updates,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> updateSessionProgress(
    String sessionId,
    int completedChunks,
    int bytesTransferred,
  ) async {
    await _ensureInitialized();
    final db = _database!;

    await db.update(
      _tableSessions,
      {
        'completed_chunks': completedChunks,
        'bytes_transferred': bytesTransferred,
        'last_activity_at': DateTime.now().toIso8601String(),
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> markChunkReceived(String sessionId, int chunkIndex) async {
    await _ensureInitialized();
    final db = _database!;

    await db.update(
      _tableChunks,
      {'is_received': 1, 'received_at': DateTime.now().toIso8601String()},
      where: 'session_id = ? AND chunk_index = ?',
      whereArgs: [sessionId, chunkIndex],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await _ensureInitialized();
    final db = _database!;

    await db.delete(
      _tableSessions,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // ==================== DEVICE OPERATIONS ====================

  Future<void> saveDevice(TransferDevice device) async {
    await _ensureInitialized();
    final db = _database!;

    await db.insert(_tableDevices, {
      'device_id': device.deviceId,
      'device_name': device.deviceName,
      'model': device.model,
      'platform': device.platform,
      'endpoint_id': device.endpointId,
      'is_trusted': device.isTrusted ? 1 : 0,
      'discovered_at': device.discoveredAt.toIso8601String(),
      'last_connected_at': device.lastConnectedAt?.toIso8601String(),
      'connection_count': device.connectionCount,
      'failed_connections': device.failedConnections,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TransferDevice?> getDevice(String deviceId) async {
    await _ensureInitialized();
    final db = _database!;

    final results = await db.query(
      _tableDevices,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    if (results.isEmpty) return null;

    final data = results.first;
    return TransferDevice(
      deviceId: data['device_id'] as String,
      deviceName: data['device_name'] as String,
      model: data['model'] as String?,
      platform: data['platform'] as String?,
      endpointId: data['endpoint_id'] as String?,
      isTrusted: (data['is_trusted'] as int) == 1,
      discoveredAt: DateTime.parse(data['discovered_at'] as String),
      lastConnectedAt: data['last_connected_at'] != null
          ? DateTime.parse(data['last_connected_at'] as String)
          : null,
      connectionCount: data['connection_count'] as int,
      failedConnections: data['failed_connections'] as int,
    );
  }

  Future<List<TransferDevice>> getTrustedDevices() async {
    await _ensureInitialized();
    final db = _database!;

    final results = await db.query(
      _tableDevices,
      where: 'is_trusted = ?',
      whereArgs: [1],
      orderBy: 'last_connected_at DESC',
    );

    return results
        .map(
          (data) => TransferDevice(
            deviceId: data['device_id'] as String,
            deviceName: data['device_name'] as String,
            model: data['model'] as String?,
            platform: data['platform'] as String?,
            endpointId: data['endpoint_id'] as String?,
            isTrusted: (data['is_trusted'] as int) == 1,
            discoveredAt: DateTime.parse(data['discovered_at'] as String),
            lastConnectedAt: data['last_connected_at'] != null
                ? DateTime.parse(data['last_connected_at'] as String)
                : null,
            connectionCount: data['connection_count'] as int,
            failedConnections: data['failed_connections'] as int,
          ),
        )
        .toList();
  }

  // ==================== HISTORY OPERATIONS ====================

  Future<void> addToHistory(TransferSession session) async {
    await _ensureInitialized();
    final db = _database!;

    int? durationSeconds;
    if (session.startedAt != null && session.completedAt != null) {
      durationSeconds = session.completedAt!
          .difference(session.startedAt!)
          .inSeconds;
    }

    await db.insert(_tableHistory, {
      'session_id': session.sessionId,
      'device_id': session.deviceId,
      'device_name': session.deviceName,
      'file_name': session.metadata.fileName,
      'file_size': session.metadata.fileSize,
      'file_type': session.metadata.fileType.name,
      'direction': session.direction.name,
      'status': session.state == TransferState.completed ? 'success' : 'failed',
      'completed_at': session.completedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'error_message': session.errorMessage,
    });
  }

  Future<List<Map<String, dynamic>>> getTransferHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    await _ensureInitialized();
    final db = _database!;

    return await db.query(
      _tableHistory,
      orderBy: 'completed_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  // ==================== UTILITY ====================

  Future<void> cleanupOldSessions({int daysToKeep = 7}) async {
    await _ensureInitialized();
    final db = _database!;

    final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));

    await db.delete(
      _tableSessions,
      where: 'created_at < ? AND state IN (?, ?)',
      whereArgs: [
        cutoff.toIso8601String(),
        TransferState.completed.name,
        TransferState.cancelled.name,
      ],
    );
  }

  Future<void> close() async {
    await _database?.close();
    _isInitialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
}
