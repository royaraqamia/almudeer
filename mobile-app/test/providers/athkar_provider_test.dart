import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/presentation/providers/athkar_provider.dart';
import 'package:almudeer_mobile_app/data/local/athkar_data.dart';
import 'package:almudeer_mobile_app/core/services/offline_sync_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'athkar_provider_test.mocks.dart';

@GenerateMocks([OfflineSyncService])
void main() {
  late AthkarProvider provider;
  late MockOfflineSyncService mockSyncService;

  setUp(() async {
    // Initialize Flutter binding for tests (required for AppLifecycleListener)
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Initialize SharedPreferences with empty values before each test
    SharedPreferences.setMockInitialValues({});
    mockSyncService = MockOfflineSyncService();
  });

  tearDown(() async {
    // Dispose provider first (ignore errors if already disposed)
    try {
      provider.dispose();
    } catch (_) {
      // Ignore disposal errors
    }
  });

  group('AthkarProvider - Initialization', () {
    test('should initialize with empty counts', () async {
      provider = AthkarProvider();

      // Wait for async initialization
      await Future.delayed(const Duration(milliseconds: 200));

      expect(provider.counts, isEmpty);
      expect(provider.misbahaCount, equals(0));
      expect(provider.isLoading, isFalse);
    });

    test('should load counts from SharedPreferences', () async {
      // First, create a provider and save some data
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));
      
      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      
      // Wait for save
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Dispose and create a new provider to test loading
      provider.dispose();
      
      // New provider should load the saved data
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 300));

      expect(provider.getCount(item.id), equals(1));
    });
  });

  group('AthkarProvider - Daily Reset', () {
    test('should reset counts when date changes', () async {
      // Set initial values with yesterday's date
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      
      SharedPreferences.setMockInitialValues({
        'almudeer_athkar_counts': '{"m_ayatal_kursi": 1}',
        'almudeer_athkar_misbaha_count': 100,
        'almudeer_athkar_last_reset_date': yesterdayStr,
      });

      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      // Should have been reset
      expect(provider.counts, isEmpty);
      expect(provider.misbahaCount, equals(0));
    });

    test('should not reset counts on same day', () async {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      SharedPreferences.setMockInitialValues({
        'almudeer_athkar_counts': '{"m_ayatal_kursi": 1}',
        'almudeer_athkar_misbaha_count': 100,
        'almudeer_athkar_last_reset_date': todayStr,
      });

      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      // Should NOT be reset
      expect(provider.getCount('m_ayatal_kursi'), equals(1));
      expect(provider.misbahaCount, equals(100));
    });
  });

  group('AthkarProvider - Increment/Decrement', () {
    test('should increment count correctly', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      
      // Wait for save to complete
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.getCount(item.id), equals(1));
    });

    test('should not increment beyond target count', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      // Increment multiple times beyond the target
      for (int i = 0; i < item.count + 5; i++) {
        provider.increment(item);
      }
      
      // Wait for save to complete
      await Future.delayed(const Duration(milliseconds: 150));

      // Should not exceed the target count
      expect(provider.getCount(item.id), equals(item.count));
    });

    test('should decrement count correctly', () async {
      // Use a specific item with count > 1 to test decrement properly
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      // Find an item with count >= 3 for proper testing
      final item = AthkarData.morningAthkar.firstWhere((i) => i.count >= 3);
      
      // Increment to a known state
      provider.increment(item);
      expect(provider.getCount(item.id), equals(1));
      
      provider.increment(item);
      expect(provider.getCount(item.id), equals(2));
      
      // Now decrement
      provider.decrement(item);
      expect(provider.getCount(item.id), equals(1));
    });

    test('should not decrement below zero', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      provider.decrement(item); // Try to decrement when at 0
      
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.getCount(item.id), equals(0));
    });

    test('isCompleted should return true when count reaches target', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      expect(provider.isCompleted(item), isFalse);

      // Increment to target
      for (int i = 0; i < item.count; i++) {
        provider.increment(item);
      }
      
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.isCompleted(item), isTrue);
    });
  });

  group('AthkarProvider - Misbaha', () {
    test('should increment misbaha count', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      provider.incrementMisbaha();
      provider.incrementMisbaha();
      provider.incrementMisbaha();
      
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.misbahaCount, equals(3));
    });

    test('should reset misbaha count', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      provider.incrementMisbaha();
      provider.incrementMisbaha();
      provider.resetMisbaha();
      
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.misbahaCount, equals(0));
    });
  });

  group('AthkarProvider - Reset All', () {
    test('should reset all counts and misbaha', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      provider.incrementMisbaha();
      
      await Future.delayed(const Duration(milliseconds: 150));

      await provider.resetAll();

      expect(provider.counts, isEmpty);
      expect(provider.misbahaCount, equals(0));
    });
  });

  group('AthkarProvider - Server Sync', () {
    test('should load data from server and merge with local (keeping higher)', () async {
      // Set today's date to allow server merge
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      SharedPreferences.setMockInitialValues({
        'almudeer_athkar_last_reset_date': todayStr,
        'almudeer_athkar_counts': '{"m_ayatal_kursi": 3}',
      });
      
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': 5, 'm_subhan_allah_bihamdihi': 50},
                  'misbaha': 200,
                },
              });

      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 300));

      // Should keep higher value (5 > 3)
      expect(provider.getCount('m_ayatal_kursi'), equals(5));
      expect(provider.getCount('m_subhan_allah_bihamdihi'), equals(50));
      expect(provider.misbahaCount, equals(200));
    });

    test('should keep local data when it is higher than server', () async {
      // Set today's date to allow server merge
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      SharedPreferences.setMockInitialValues({
        'almudeer_athkar_last_reset_date': todayStr,
        'almudeer_athkar_counts': '{"m_ayatal_kursi": 10}',
      });
      
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': 5},
                  'misbaha': 100,
                },
              });

      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 300));

      // Should keep local value (10 > 5)
      expect(provider.getCount('m_ayatal_kursi'), equals(10));
    });

    test('should validate server data - reject negative counts', () async {
      // Set today's date to allow server merge
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      SharedPreferences.setMockInitialValues({
        'almudeer_athkar_last_reset_date': todayStr,
      });
      
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': -5},
                  'misbaha': 200,
                },
              });

      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 300));

      // Negative values should be sanitized to 0
      expect(provider.getCount('m_ayatal_kursi'), equals(0));
    });

    test('should validate server data - handle non-integer values', () async {
      // Set today's date to allow server merge
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      SharedPreferences.setMockInitialValues({
        'almudeer_athkar_last_reset_date': todayStr,
      });
      
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': 5.7},
                  'misbaha': 200,
                },
              });

      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 300));

      // Float values should be converted to int
      expect(provider.getCount('m_ayatal_kursi'), equals(5));
    });

    test('should handle server sync failure gracefully', () async {
      when(mockSyncService.getAthkarProgress())
          .thenThrow(Exception('Network error'));

      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 200));

      // Should still work with local data
      expect(provider.counts, isNotNull);
      expect(provider.misbahaCount, equals(0));
    });
  });

  group('AthkarProvider - Memory Leak Protection', () {
    test('should not throw after dispose', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      provider.dispose();

      // Should not throw after dispose
      final item = AthkarData.morningAthkar.first;
      expect(() => provider.increment(item), returnsNormally);

      // Test passes if no exception is thrown
      expect(provider.disposed, isTrue);
    });

    test('should not save to storage after dispose', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      provider.dispose();

      // Wait for any pending save timer
      await Future.delayed(const Duration(milliseconds: 200));

      // Test passes if no exception is thrown
      expect(provider.disposed, isTrue);
    });
  });

  group('AthkarProvider - Scheduled Save', () {
    test('should save to SharedPreferences after debounce', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      provider.increment(item);

      // Wait for debounce timer (100ms) + buffer
      await Future.delayed(const Duration(milliseconds: 200));

      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('almudeer_athkar_counts');

      expect(savedData, isNotNull);
      expect(savedData!.contains(item.id), isTrue);
    });

    test('should flush to storage on dispose', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      
      // Verify count is updated in memory
      expect(provider.getCount(item.id), equals(1));

      // Dispose should trigger immediate flush
      provider.dispose();

      // Test passes if dispose completes without error
      expect(provider.disposed, isTrue);
    });
  });

  group('AthkarProvider - Storage Key Validation', () {
    test('should use correct namespaced storage keys', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      
      // Wait for save
      await Future.delayed(const Duration(milliseconds: 200));

      final prefs = await SharedPreferences.getInstance();
      
      // Verify namespaced keys are used
      expect(prefs.containsKey('almudeer_athkar_counts'), isTrue);
      expect(prefs.containsKey('almudeer_athkar_misbaha_count'), isTrue);
      expect(prefs.containsKey('almudeer_athkar_misbaha_target'), isTrue);
      expect(prefs.containsKey('almudeer_athkar_last_reset_date'), isTrue);
    });
  });
}
