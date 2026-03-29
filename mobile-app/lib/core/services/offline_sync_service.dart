import 'dart:async';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'pending_operations_service.dart';
import 'package:almudeer_mobile_app/features/inbox/data/repositories/inbox_repository.dart';
import 'package:almudeer_mobile_app/features/customers/data/repositories/customers_repository.dart';
import 'package:almudeer_mobile_app/features/auth/data/repositories/auth_repository.dart';
import '../api/endpoints.dart';
import '../api/api_client.dart';
// Removed unused import

/// Sync status for UI display
enum SyncStatus { idle, syncing, success, error }

/// Service that orchestrates syncing operations (Two-Way Sync).
class OfflineSyncService extends ChangeNotifier {
  final ConnectivityService _connectivityService;
  final PendingOperationsService _pendingOperationsService;
  final InboxRepository _inboxRepository;
  final CustomersRepository _customersRepository;
  final ApiClient _apiClient;

  SyncStatus _status = SyncStatus.idle;
  int _syncedCount = 0;
  int _totalCount = 0;
  String? _lastError;
  DateTime? _lastSyncTime;

  bool _isSyncing = false;

  Timer? _syncTimer;

  bool _isInitialized = false;

  OfflineSyncService({
    ConnectivityService? connectivityService,
    PendingOperationsService? pendingOperationsService,
    InboxRepository? inboxRepository,
    CustomersRepository? customersRepository,
    ApiClient? apiClient,
  }) : _connectivityService = connectivityService ?? ConnectivityService(),
       _pendingOperationsService =
           pendingOperationsService ?? PendingOperationsService(),
       _inboxRepository = inboxRepository ?? InboxRepository(),
       _customersRepository = customersRepository ?? CustomersRepository(),
       _apiClient = apiClient ?? ApiClient();

  // P0-2 FIX: Cache account hash to avoid repeated lookups
  String? _cachedAccountHash;

  /// Get current account hash for operation isolation
  Future<String> _getAccountHash() async {
    if (_cachedAccountHash != null) {
      return _cachedAccountHash!;
    }
    _cachedAccountHash = await _apiClient.getAccountCacheHash();
    return _cachedAccountHash!;
  }

  SyncStatus get status => _status;
  int get syncedCount => _syncedCount;
  int get totalCount => _totalCount;
  String? get lastError => _lastError;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _pendingOperationsService.pendingCount;
  double get progress => _totalCount > 0 ? _syncedCount / _totalCount : 0.0;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _connectivityService.initialize();
    await _pendingOperationsService.initialize();
    _connectivityService.addReconnectCallback(_onReconnected);

    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_connectivityService.isOnline) {
        syncAll();
      }
    });

    _isInitialized = true;
    debugPrint('[SyncManager] Initialized with periodic sync (1m)');
  }

  void _onReconnected() {
    debugPrint('[SyncManager] Reconnected, triggering sync');
    syncAll();
  }

  Future<void> syncAll() async {
    if (_isSyncing || !_connectivityService.isOnline) return;

    final accounts = await AuthRepository().getSavedAccounts();
    if (accounts.isEmpty) return;

    _isSyncing = true;
    _status = SyncStatus.syncing;
    notifyListeners();

    final apiClient = ApiClient();
    final activeKey = await apiClient.getLicenseKey();

    try {
      for (final account in accounts) {
        final key = account.licenseKey;
        if (key == null) continue;

        // Set temporary context for repositories
        apiClient.setTemporaryOverride(key);

        try {
          // Sync pending operations for THIS account
          await _syncPendingOperations();

          // Only perform full down-sync for the active account
          if (key == activeKey) {
            await _syncActiveContext();
          }
        } catch (e) {
          debugPrint('[SyncManager] Sync failed for $key: $e');
        } finally {
          apiClient.setTemporaryOverride(null);
        }
      }

      _status = SyncStatus.success;
      _lastError = null;
      _lastSyncTime = DateTime.now();
    } catch (e) {
      debugPrint('[SyncManager] Global sync error: $e');
      _lastError = e.toString();
      _status = SyncStatus.error;
    } finally {
      _isSyncing = false;
      notifyListeners();

      Future.delayed(const Duration(seconds: 3), () {
        if (_status == SyncStatus.success) {
          _status = SyncStatus.idle;
          notifyListeners();
        }
      });
    }
  }

  Future<void> syncPendingOperations() async => syncAll();
  Future<void> forceSync() async => syncAll();

  Future<void> _syncPendingOperations() async {
    final operations = _pendingOperationsService.getRetryableOperations();
    if (operations.isEmpty) return;

    _totalCount = operations.length;
    _syncedCount = 0;

    // Get current account hash for verification
    final currentAccountHash = await _apiClient.getAccountCacheHash();

    for (final operation in operations) {
      // P0-2 FIX: Verify account isolation before processing
      if (operation.accountHash != currentAccountHash) {
        debugPrint('[SyncManager] Skipping operation ${operation.id} - account mismatch (op: ${operation.accountHash}, current: $currentAccountHash)');
        continue; // Skip operations for different account
      }

      try {
        await _processOperation(operation);
        await _pendingOperationsService.removeOperation(operation.id);
        _syncedCount++;
        notifyListeners();
      } catch (e) {
        debugPrint('[SyncManager] Operation ${operation.id} failed: $e');
        await _pendingOperationsService.markRetryFailed(
          operation.id,
          e.toString(),
        );
        // If it's a network error, stop processing the rest of the queue
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Timeout')) {
          break;
        }
      }
    }
  }

  Future<void> _syncActiveContext() async {
    try {
      await _customersRepository.getCustomers(page: 1, pageSize: 50);
      final conversations = await _inboxRepository.getConversations(limit: 10);
      final list = conversations.conversations;

      await Future.wait(
        list
            .where((conv) => conv.senderContact != null)
            .map(
              (conv) => _inboxRepository.getConversationDetail(
                conv.senderContact!,
                limit: 20,
              ),
            ),
      );
    } catch (e) {
      debugPrint('[SyncManager] Down-Sync warning: $e');
    }
  }

  /// Maximum retry attempts for failed operations
  static const int _maxRetryAttempts = 3;

  /// Base delay for exponential backoff (milliseconds)
  static const int _retryBaseDelayMs = 1000;

  /// Process operation with retry logic and exponential backoff
  Future<void> _processOperation(PendingOperation operation) async {
    int attempt = 0;
    int delayMs = _retryBaseDelayMs;

    while (attempt < _maxRetryAttempts) {
      try {
        await _executeOperation(operation);
        return; // Success
      } catch (e) {
        attempt++;
        final errorMsg = e.toString();
        
        // Don't retry validation errors (400 Bad Request)
        if (errorMsg.contains('400') || 
            errorMsg.contains('validation') ||
            errorMsg.contains('Invalid')) {
          debugPrint('[SyncManager] Operation ${operation.id} failed validation (not retrying): $e');
          rethrow;
        }
        
        if (attempt >= _maxRetryAttempts) {
          debugPrint('[SyncManager] Operation ${operation.id} failed after $attempt attempts: $e');
          rethrow;
        }
        
        // Exponential backoff with jitter
        final jitter = DateTime.now().millisecondsSinceEpoch % 500;
        final totalDelay = delayMs + jitter;
        debugPrint('[SyncManager] Operation ${operation.id} failed (attempt $attempt/$_maxRetryAttempts), retrying in ${totalDelay}ms...');

        await Future.delayed(Duration(milliseconds: totalDelay));
        delayMs *= 2; // Exponential backoff
      }
    }
  }

  /// Execute the actual operation (switch statement)
  Future<void> _executeOperation(PendingOperation operation) async {
    switch (operation.type) {
      case 'send':
        await _inboxRepository.sendMessage(
          operation.payload['senderContact'],
          message: operation.payload['body'],
          channel: operation.payload['channel'] ?? 'whatsapp',
          attachments: operation.payload['mediaPath'] != null
              ? [
                  {'path': operation.payload['mediaPath'], 'type': 'image'},
                ]
              : null,
          replyToMessageId: operation.payload['replyToMessageId'],
          replyToPlatformId: operation.payload['replyToPlatformId'],
          replyToBodyPreview: operation.payload['replyToBodyPreview'],
        );
        break;
      case 'edit':
        await _inboxRepository.editMessage(
          operation.payload['message_id'],
          operation.payload['new_body'],
        );
        break;
      case 'delete':
        await _inboxRepository.deleteMessage(operation.payload['messageId']);
        break;
      case 'mark_read':
        await _inboxRepository.markConversationRead(
          operation.payload['senderContact'],
        );
        break;
      case 'delete_conversation':
        await _inboxRepository.deleteConversation(
          operation.payload['senderContact'],
        );
        break;
      case 'add_library_note':
        await _inboxRepository.apiClient.post(
          Endpoints.libraryNote,
          body: {
            'title': operation.payload['title'],
            'content': operation.payload['content'],
            'customer_id': operation.payload['customer_id'],
          },
        );
        break;
      case 'add_customer':
        await _customersRepository.addCustomer(
          Map<String, dynamic>.from(operation.payload),
        );
        break;
      case 'update_customer':
        await _customersRepository.updateCustomer(
          operation.payload['id'],
          Map<String, dynamic>.from(operation.payload),
        );
        break;
      // P0-2 FIX: Add missing delete_customer handler
      case 'delete_customer':
        await _customersRepository.deleteCustomer(
          operation.payload['customerId'],
        );
        break;
      case 'sync_quran_progress':
        await _inboxRepository.apiClient.post(
          Endpoints.syncBatch,
          body: {
            'operations': [
              {
                'id': operation.id,
                'type': 'sync_quran_progress',
                'idempotency_key': operation.id,
                'payload': operation.payload,
              },
            ],
          },
        );
        break;
      case 'sync_athkar_counts':
        await _inboxRepository.apiClient.post(
          Endpoints.syncBatch,
          body: {
            'operations': [
              {
                'id': operation.id,
                'type': 'sync_athkar_counts',
                'idempotency_key': operation.id,
                'payload': operation.payload,
              },
            ],
          },
        );
        break;
      default:
        break;
    }
  }

  /// Maximum number of verses in any surah (Al-Baqarah)
  static const int _maxVersesInSurah = 286;

  /// Validate Quran progress data before syncing
  bool _isValidQuranProgress(int surah, int verse) {
    return surah >= 1 && surah <= 114 && verse >= 1 && verse <= _maxVersesInSurah;
  }

  Future<void> queueQuranProgress(int surah, int verse) async {
    // Validate before queuing to prevent server rejections
    if (!_isValidQuranProgress(surah, verse)) {
      debugPrint('Invalid Quran progress skipped: surah=$surah, verse=$verse');
      return;
    }

    final accountHash = await _getAccountHash();
    await _pendingOperationsService.addOperation(
      type: 'sync_quran_progress',
      accountHash: accountHash,
      payload: {
        'data': {'last_surah': surah, 'last_verse': verse},
      },
    );
    syncAll();
  }

  Future<Map<String, dynamic>?> getQuranProgress() async {
    try {
      final response = await _inboxRepository.apiClient.get(
        Endpoints.quranProgress,
      );
      return response;
    } catch (e) {
      debugPrint('Error fetching quran progress: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAthkarProgress() async {
    try {
      final response = await _inboxRepository.apiClient.get(
        Endpoints.athkarProgress,
      );
      return response;
    } catch (e) {
      debugPrint('Error fetching athkar progress: $e');
    }
    return null;
  }

  Future<void> queueAthkarProgress(Map<String, int> counts, int misbaha) async {
    final accountHash = await _getAccountHash();
    await _pendingOperationsService.addOperation(
      type: 'sync_athkar_counts',
      accountHash: accountHash,
      payload: {
        'data': {'counts': counts, 'misbaha': misbaha},
      },
    );
    syncAll();
  }

  Future<void> queueSendMessage(
    String senderContact,
    String body, {
    String? mediaPath,
    String channel = 'whatsapp',
    int? replyToMessageId,
    String? replyToPlatformId,
    String? replyToBodyPreview,
  }) async {
    final accountHash = await _getAccountHash();
    try {
      final result = await _inboxRepository.sendMessage(
        senderContact,
        message: body,
        channel: channel,
        attachments: mediaPath != null
            ? [
                {'path': mediaPath, 'type': 'image'},
              ]
            : null,
        replyToMessageId: replyToMessageId,
        replyToPlatformId: replyToPlatformId,
        replyToBodyPreview: replyToBodyPreview,
      );

      if (result['pending'] == true) {
        await _pendingOperationsService.addOperation(
          type: 'send',
          accountHash: accountHash,
          payload: {
            'senderContact': senderContact,
            'body': body,
            'mediaPath': mediaPath,
            'channel': channel,
            'replyToMessageId': replyToMessageId,
            'replyToPlatformId': replyToPlatformId,
            'replyToBodyPreview': replyToBodyPreview,
          },
        );
        syncAll();
      }
    } catch (e) {
      debugPrint('[SyncManager] Send failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'send',
        accountHash: accountHash,
        payload: {
          'senderContact': senderContact,
          'body': body,
          'mediaPath': mediaPath,
          'channel': channel,
          'replyToMessageId': replyToMessageId,
          'replyToPlatformId': replyToPlatformId,
          'replyToBodyPreview': replyToBodyPreview,
        },
      );
      syncAll();
    }
  }

  Future<void> queueDelete(int messageId) async {
    final accountHash = await _getAccountHash();
    try {
      final result = await _inboxRepository.deleteMessage(messageId);
      if (result['pending'] == true) {
        await _pendingOperationsService.addOperation(
          type: 'delete',
          accountHash: accountHash,
          payload: {'messageId': messageId},
        );
        syncAll();
      }
    } catch (e) {
      debugPrint('[SyncManager] Delete failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'delete',
        accountHash: accountHash,
        payload: {'messageId': messageId},
      );
      syncAll();
    }
  }

  Future<void> queueDeleteConversation(String senderContact) async {
    final accountHash = await _getAccountHash();
    try {
      if (_connectivityService.isOffline) {
        await _pendingOperationsService.addOperation(
          type: 'delete_conversation',
          accountHash: accountHash,
          payload: {'senderContact': senderContact},
        );
        syncAll();
        return;
      }
      await _inboxRepository.deleteConversation(senderContact);
    } catch (e) {
      debugPrint('[SyncManager] Delete conversation failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'delete_conversation',
        accountHash: accountHash,
        payload: {'senderContact': senderContact},
      );
      syncAll();
    }
  }

  Future<void> queueAddCustomer(Map<String, dynamic> customerData) async {
    final accountHash = await _getAccountHash();
    try {
      final result = await _customersRepository.addCustomer(customerData);
      if (result['pending'] == true) {
        await _pendingOperationsService.addOperation(
          type: 'add_customer',
          accountHash: accountHash,
          payload: customerData,
        );
        syncAll();
      }
    } catch (e) {
      debugPrint('[SyncManager] Add customer failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'add_customer',
        accountHash: accountHash,
        payload: customerData,
      );
      syncAll();
    }
  }

  Future<void> queueUpdateCustomer(
    int remoteId,
    Map<String, dynamic> updates,
  ) async {
    final accountHash = await _getAccountHash();
    try {
      if (_connectivityService.isOffline) {
        await _pendingOperationsService.addOperation(
          type: 'update_customer',
          accountHash: accountHash,
          payload: {'id': remoteId, ...updates},
        );
        syncAll();
        return;
      }
      final result = await _customersRepository.updateCustomer(
        remoteId,
        updates,
      );
      if (result['pending'] == true) {
        await _pendingOperationsService.addOperation(
          type: 'update_customer',
          accountHash: accountHash,
          payload: {'id': remoteId, ...updates},
        );
        syncAll();
      }
    } catch (e) {
      debugPrint('[SyncManager] Update customer failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'update_customer',
        accountHash: accountHash,
        payload: {'id': remoteId, ...updates},
      );
      syncAll();
    }
  }

  Future<void> queueDeleteCustomer(int customerId) async {
    final accountHash = await _getAccountHash();
    try {
      if (_connectivityService.isOffline) {
        await _pendingOperationsService.addOperation(
          type: 'delete_customer',
          accountHash: accountHash,
          payload: {'customerId': customerId},
        );
        syncAll();
        return;
      }
      final result = await _customersRepository.deleteCustomer(customerId);
      if (result['pending'] == true) {
        await _pendingOperationsService.addOperation(
          type: 'delete_customer',
          accountHash: accountHash,
          payload: {'customerId': customerId},
        );
        syncAll();
      }
    } catch (e) {
      debugPrint('[SyncManager] Delete customer failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'delete_customer',
        accountHash: accountHash,
        payload: {'customerId': customerId},
      );
      syncAll();
    }
  }

  Future<void> queueAddLibraryNote({
    required String title,
    required String content,
    int? customerId,
  }) async {
    final accountHash = await _getAccountHash();
    try {
      final response = await _inboxRepository.apiClient.post(
        Endpoints.libraryNote,
        body: {'title': title, 'content': content, 'customer_id': customerId},
      );

      if (response['success'] != true) {
        throw Exception(response['detail'] ?? 'Failed to add note');
      }
    } catch (e) {
      debugPrint('[SyncManager] Add library note failed, queuing: $e');
      await _pendingOperationsService.addOperation(
        type: 'add_library_note',
        accountHash: accountHash,
        payload: {
          'title': title,
          'content': content,
          'customer_id': customerId,
        },
      );
      syncAll();
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
