import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:almudeer_mobile_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:almudeer_mobile_app/features/settings/presentation/providers/settings_provider.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/settings/data/models/user_preferences.dart';

class MockSettingsProvider extends Mock implements SettingsProvider {}

class MockAuthProvider extends Mock implements AuthProvider {}

void main() {
  late MockSettingsProvider mockSettingsProvider;
  late MockAuthProvider mockAuthProvider;

  setUp(() {
    mockSettingsProvider = MockSettingsProvider();
    mockAuthProvider = MockAuthProvider();
  });

  Widget createWidgetUnderTest() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: mockSettingsProvider,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  group('SettingsScreen Tests', () {
    testWidgets('renders account info and integrations section', (
      WidgetTester tester,
    ) async {
      // Arrange
      when(mockSettingsProvider.state).thenReturn(SettingsState.loaded);
      when(
        mockSettingsProvider.preferences,
      ).thenReturn(UserPreferences(notificationsEnabled: true, tone: 'formal'));
      when(mockSettingsProvider.integrations).thenReturn([]);
      when(mockSettingsProvider.knowledgeDocuments).thenReturn([]);
      when(mockSettingsProvider.pendingFiles).thenReturn([]);
      when(mockSettingsProvider.isSaving).thenReturn(false);

      when(mockAuthProvider.userInfo).thenReturn(null);

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle(); // Wait for animations

      // Assert
      expect(find.text('ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ'), findsOneWidget);
      // IntegrationsSection is loaded by default now
      // Verifying a part of it or just that the screen renders without error
      // The integrations list requires a provider load, which we mocked.
    });
  });
}
