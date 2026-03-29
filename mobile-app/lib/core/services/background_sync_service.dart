import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:almudeer_mobile_app/features/inbox/data/repositories/inbox_repository.dart';
import 'package:almudeer_mobile_app/features/customers/data/repositories/customers_repository.dart';
import 'package:almudeer_mobile_app/features/library/data/repositories/knowledge_repository.dart';
import 'package:almudeer_mobile_app/features/settings/data/repositories/subscriptions_repository.dart';
import 'package:almudeer_mobile_app/features/integrations/data/repositories/integrations_repository.dart';
import 'persistent_cache_service.dart';
import 'connectivity_service.dart';
import 'offline_sync_service.dart';
import 'package:almudeer_mobile_app/features/auth/data/repositories/auth_repository.dart';
import '../../core/api/api_client.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';

const String _syncDataTask = 'com.almudeer.app.syncData';

/// Background data sync service using Workmanager.
/// This service ensures that local caches are warmed up periodically
/// even when the app is in the background.
class BackgroundSyncService {
  static final BackgroundSyncService _instance =
      BackgroundSyncService._internal();
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();

  /// Initialize background data sync
  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await Workmanager().initialize(syncDispatcher);

      await Workmanager().registerPeriodicTask(
        'almudeer_data_sync',
        _syncDataTask,
        frequency: const Duration(hours: 1), // Sync data every hour
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        initialDelay: const Duration(minutes: 30),
      );

      if (kDebugMode) {
        debugPrint('[BackgroundSyncService] Data sync task registered');
      }
    } catch (e) {
      debugPrint('[BackgroundSyncService] Initialization failed: $e');
    }
  }
}

/// Global dispatcher for background data sync
@pragma('vm:entry-point')
void syncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _syncDataTask) {
      if (kDebugMode) {
        print('[BackgroundSync] Starting background data sync...');
      }

      try {
        // Initialize Hive for background process
        await Hive.initFlutter();
        await PersistentCacheService().initialize();

        final authRepo = AuthRepository();
        final accounts = await authRepo.getSavedAccounts();
        final apiClient = ApiClient();

        if (accounts.isEmpty) {
          if (kDebugMode) print('[BackgroundSync] No accounts found to sync');
          return Future.value(true);
        }

        bool allSuccessful = true;
        for (final account in accounts) {
          final key = account.licenseKey;
          if (key == null || key.isEmpty) continue;

          if (kDebugMode) print('[BackgroundSync] Syncing account: $key');

          // Set temporary context for this account's repositories
          apiClient.setTemporaryOverride(key);

          try {
            final success = await _performAccountSync(account);
            if (!success) allSuccessful = false;
          } catch (e) {
            allSuccessful = false;
            debugPrint('[BackgroundSync] Failed sync for $key: $e');
          } finally {
            // Restore context
            apiClient.setTemporaryOverride(null);
          }
        }

        return Future.value(allSuccessful);
      } catch (e) {
        if (kDebugMode) print('[BackgroundSync] Global sync failed: $e');
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

/// Helper to perform sync for a specific account context
Future<bool> _performAccountSync(UserInfo account) async {
  try {
    // Initialize repositories (they will use the current/temporary context of ApiClient)
    final inboxRepo = InboxRepository();
    final customersRepo = CustomersRepository();
    final knowledgeRepo = KnowledgeRepository();
    final subsRepo = SubscriptionsRepository();
    final integrationsRepo = IntegrationsRepository();

    // 1. Sync Conversations (Top 25)
    try {
      await inboxRepo.getConversations(limit: 25);
    } catch (e) {
      if (kDebugMode) print('[BackgroundSync] Inbox sync failed: $e');
    }

    // 2. Sync Unread Counts
    try {
      await inboxRepo.getUnreadCounts();
    } catch (_) {}

    // 3. Sync Customers (First Page)
    try {
      await customersRepo.getCustomers(page: 1, pageSize: 20);
    } catch (_) {}

    // 4. Sync Knowledge Documents
    try {
      await knowledgeRepo.getKnowledgeDocuments();
    } catch (_) {}

    // 5. Sync Integrations Status
    try {
      await integrationsRepo.getAccountsStatus();
    } catch (_) {}

    // 6. Sync Subscriptions
    try {
      await subsRepo.getSubscriptions();
    } catch (_) {}

    // 7. Trigger Offline Sync (Process pending outbox for this account)
    try {
      final connectivityService = ConnectivityService();
      await connectivityService.initialize();
      final offlineSync = OfflineSyncService(
        connectivityService: connectivityService,
        inboxRepository: inboxRepo,
      );
      await offlineSync.initialize();
      await offlineSync.syncPendingOperations();
    } catch (_) {}

    return true;
  } catch (e) {
    debugPrint('[BackgroundSync] _performAccountSync technical failure: $e');
    return false;
  }
}
