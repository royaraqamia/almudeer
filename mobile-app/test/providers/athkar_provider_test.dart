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
    // Initialize SharedPreferences before each test
    SharedPreferences.setMockInitialValues({});
    mockSyncService = MockOfflineSyncService();
  });

  tearDown(() async {
    provider.dispose();
    // Clear SharedPreferences after each test
    await SharedPreferences.getInstance().then((prefs) {
      prefs.clear();
    });
  });

  group('AthkarProvider - Initialization', () {
    test('should initialize with empty counts', () async {
      provider = AthkarProvider();
      
      // Wait for async initialization
      await Future.delayed(const Duration(milliseconds: 100));
      
      expect(provider.counts, isEmpty);
      expect(provider.misbahaCount, equals(0));
      expect(provider.isLoading, isFalse);
    });

    test('should load counts from SharedPreferences', () async {
      // Set initial values in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('athkar_counts', '{"m_ayatal_kursi": 1, "m_subhan_allah_bihamdihi": 50}');
      await prefs.setInt('misbaha_count', 100);
      
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      expect(provider.getCount('m_ayatal_kursi'), equals(1));
      expect(provider.getCount('m_subhan_allah_bihamdihi'), equals(50));
      expect(provider.misbahaCount, equals(100));
    });
  });

  group('AthkarProvider - Daily Reset', () {
    test('should reset counts when date changes', () async {
      // Set initial values
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('athkar_counts', '{"m_ayatal_kursi": 1}');
      await prefs.setInt('misbaha_count', 100);
      // Set last reset date to yesterday
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      await prefs.setString('athkar_last_reset_date', yesterdayStr);
      
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Should have been reset
      expect(provider.counts, isEmpty);
      expect(provider.misbahaCount, equals(0));
    });

    test('should not reset counts on same day', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('athkar_counts', '{"m_ayatal_kursi": 1}');
      await prefs.setInt('misbaha_count', 100);
      // Set last reset date to today
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await prefs.setString('athkar_last_reset_date', todayStr);
      
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Should NOT be reset
      expect(provider.getCount('m_ayatal_kursi'), equals(1));
      expect(provider.misbahaCount, equals(100));
    });
  });

  group('AthkarProvider - Increment/Decrement', () {
    test('should increment count correctly', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      
      expect(provider.getCount(item.id), equals(1));
    });

    test('should not increment beyond target count', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      // Increment multiple times beyond the target
      for (int i = 0; i < item.count + 5; i++) {
        provider.increment(item);
      }
      
      // Should not exceed the target count
      expect(provider.getCount(item.id), equals(item.count));
    });

    test('should decrement count correctly', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      provider.increment(item);
      provider.decrement(item);
      
      expect(provider.getCount(item.id), equals(1));
    });

    test('should not decrement below zero', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      provider.decrement(item); // Try to decrement when at 0
      
      expect(provider.getCount(item.id), equals(0));
    });

    test('isCompleted should return true when count reaches target', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      expect(provider.isCompleted(item), isFalse);
      
      // Increment to target
      for (int i = 0; i < item.count; i++) {
        provider.increment(item);
      }
      
      expect(provider.isCompleted(item), isTrue);
    });
  });

  group('AthkarProvider - Misbaha', () {
    test('should increment misbaha count', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      provider.incrementMisbaha();
      provider.incrementMisbaha();
      provider.incrementMisbaha();
      
      expect(provider.misbahaCount, equals(3));
    });

    test('should reset misbaha count', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      provider.incrementMisbaha();
      provider.incrementMisbaha();
      provider.resetMisbaha();
      
      expect(provider.misbahaCount, equals(0));
    });
  });

  group('AthkarProvider - Reset All', () {
    test('should reset all counts and misbaha', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      provider.incrementMisbaha();
      
      await provider.resetAll();
      
      expect(provider.counts, isEmpty);
      expect(provider.misbahaCount, equals(0));
    });
  });

  group('AthkarProvider - Server Sync', () {
    test('should load data from server', () async {
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': 5, 'm_subhan_allah_bihamdihi': 50},
                  'misbaha': 200,
                },
              });
      
      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 100));
      
      expect(provider.getCount('m_ayatal_kursi'), equals(5));
      expect(provider.getCount('m_subhan_allah_bihamdihi'), equals(50));
      expect(provider.misbahaCount, equals(200));
    });

    test('should validate server data - reject negative counts', () async {
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': -5},
                  'misbaha': 200,
                },
              });
      
      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Negative values should be sanitized to 0
      expect(provider.getCount('m_ayatal_kursi'), equals(0));
    });

    test('should validate server data - handle non-integer values', () async {
      when(mockSyncService.getAthkarProgress())
          .thenAnswer((_) async => {
                'success': true,
                'athkar': {
                  'counts': {'m_ayatal_kursi': 5.7},
                  'misbaha': 200,
                },
              });
      
      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Float values should be converted to int
      expect(provider.getCount('m_ayatal_kursi'), equals(5));
    });

    test('should handle server sync failure gracefully', () async {
      when(mockSyncService.getAthkarProgress())
          .thenThrow(Exception('Network error'));
      
      provider = AthkarProvider(syncService: mockSyncService);
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Should still work with local data
      expect(provider.counts, isNotNull);
      expect(provider.misbahaCount, equals(0));
    });
  });

  group('AthkarProvider - Memory Leak Protection', () {
    test('should not notifyListeners after dispose', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      provider.dispose();

      // Should not throw or notify after dispose
      final item = AthkarData.morningAthkar.first;
      provider.increment(item);

      // Test passes if no exception is thrown
      expect(provider.disposed, isTrue);
    });

    test('should not save to storage after dispose', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      provider.dispose();

      // Wait for any pending debounce timer
      await Future.delayed(const Duration(milliseconds: 600));

      // Test passes if no exception is thrown
      expect(provider.disposed, isTrue);
    });
  });

  group('AthkarProvider - Debounced Save', () {
    test('should save to SharedPreferences after debounce', () async {
      provider = AthkarProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      
      final item = AthkarData.morningAthkar.first;
      provider.increment(item);
      
      // Wait for debounce timer (500ms) + buffer
      await Future.delayed(const Duration(milliseconds: 600));
      
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('athkar_counts');
      
      expect(savedData, isNotNull);
      expect(savedData!.contains(item.id), isTrue);
    });
  });
}
