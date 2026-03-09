import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/core/services/offline_sync_service.dart';

void main() {
  group('SyncStatus', () {
    test('has correct enum values', () {
      expect(SyncStatus.values.length, equals(4));
      expect(SyncStatus.values, contains(SyncStatus.idle));
      expect(SyncStatus.values, contains(SyncStatus.syncing));
      expect(SyncStatus.values, contains(SyncStatus.success));
      expect(SyncStatus.values, contains(SyncStatus.error));
    });
  });

  group('OfflineSyncService', () {
    late OfflineSyncService service;

    setUp(() {
      service = OfflineSyncService();
    });

    test('initial status is idle', () {
      expect(service.status, equals(SyncStatus.idle));
    });

    test('isSyncing is false initially', () {
      expect(service.isSyncing, isFalse);
    });

    test('progress is 0.0 when totalCount is 0', () {
      expect(service.progress, equals(0.0));
    });

    test('lastSyncTime is null initially', () {
      expect(service.lastSyncTime, isNull);
    });

    test('lastError is null initially', () {
      expect(service.lastError, isNull);
    });

    test('syncedCount and totalCount are 0 initially', () {
      expect(service.syncedCount, equals(0));
      expect(service.totalCount, equals(0));
    });
  });
}
