import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/presentation/providers/settings_provider.dart';
import 'package:almudeer_mobile_app/data/repositories/settings_repository.dart';
import 'package:almudeer_mobile_app/data/repositories/knowledge_repository.dart';
import 'package:almudeer_mobile_app/data/models/user_preferences.dart';

@GenerateMocks([SettingsRepository, KnowledgeRepository])
import 'settings_provider_test.mocks.dart';

void main() {
  late SettingsProvider provider;
  late MockSettingsRepository mockRepository;
  late MockKnowledgeRepository mockKnowledgeRepository;

  setUp(() {
    mockRepository = MockSettingsRepository();
    mockKnowledgeRepository = MockKnowledgeRepository();
    provider = SettingsProvider(
      repository: mockRepository,
      knowledgeRepository: mockKnowledgeRepository,
    );
  });

  group('SettingsProvider', () {
    final testPreferences = UserPreferences(
      notificationsEnabled: true,
      tone: 'formal',
      preferredLanguages: ['ar'],
      replyLength: 'medium',
    );

    test('loadSettings fetches data and updates state', () async {
      // Arrange
      when(
        mockRepository.getPreferences(),
      ).thenAnswer((_) async => testPreferences);
      when(
        mockKnowledgeRepository.getKnowledgeDocuments(),
      ).thenAnswer((_) async => []);

      // Act
      await provider.loadSettings();

      // Assert
      expect(provider.preferences, equals(testPreferences));
      expect(provider.state, SettingsState.loaded);
      verify(mockRepository.getPreferences()).called(1);
    });

    test('savePreferences updates state and calls repository', () async {
      // Arrange
      // Need to load first to set initial state if checking optimistic update,
      // but here we just test savePreferences logic directly.
      when(mockRepository.updatePreferences(any)).thenAnswer((_) async => true);

      final newPrefs = testPreferences.copyWith(notificationsEnabled: false);

      // Act
      final result = await provider.savePreferences(newPrefs);

      // Assert
      expect(result, true);
      expect(provider.preferences?.notificationsEnabled, false);
      verify(mockRepository.updatePreferences(newPrefs)).called(1);
    });

    test('savePreferences reverts on failure', () async {
      // Arrange
      // Load initial state
      when(
        mockRepository.getPreferences(),
      ).thenAnswer((_) async => testPreferences);
      when(
        mockKnowledgeRepository.getKnowledgeDocuments(),
      ).thenAnswer((_) async => []);
      await provider.loadSettings();

      when(
        mockRepository.updatePreferences(any),
      ).thenThrow(Exception('Failed to save'));

      final newPrefs = testPreferences.copyWith(tone: 'friendly');

      // Act
      final result = await provider.savePreferences(newPrefs);

      // Assert
      expect(result, false);
      expect(provider.preferences?.tone, 'formal'); // Should revert to old
      expect(provider.errorMessage, isNotNull);
    });

    test(
      'loadSettings handles error gracefully by checking local cache',
      () async {
        // Arrange
        when(
          mockRepository.getPreferences(),
        ).thenThrow(Exception('Network error'));
        when(
          mockKnowledgeRepository.getKnowledgeDocuments(),
        ).thenAnswer((_) async => []);

        when(
          mockRepository.getLocalPreferences(),
        ).thenAnswer((_) async => testPreferences);

        // Act
        await provider.loadSettings();

        // Assert
        expect(provider.state, SettingsState.loaded);
        expect(provider.preferences, equals(testPreferences));
      },
    );

    test('loadSettings sets error state if cache also fails', () async {
      // Arrange
      when(
        mockRepository.getPreferences(),
      ).thenThrow(Exception('Network error'));
      when(
        mockKnowledgeRepository.getKnowledgeDocuments(),
      ).thenAnswer((_) async => []);

      when(
        mockRepository.getLocalPreferences(),
      ).thenThrow(Exception('Cache error'));

      // Act
      await provider.loadSettings();

      // Assert
      expect(provider.state, SettingsState.error);
    });
  });
}
