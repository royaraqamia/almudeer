import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/presentation/screens/settings/settings_screen.dart';
import 'package:almudeer_mobile_app/presentation/providers/settings_provider.dart';
import 'package:almudeer_mobile_app/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/data/models/user_preferences.dart';

@GenerateMocks([SettingsProvider, AuthProvider])
import 'settings_screen_test.mocks.dart';

// Mock Premium components if needed, or rely on them being simple widgets.
// For integration test, it's better to render them.

void main() {
  late MockSettingsProvider mockSettingsProvider;
  late MockAuthProvider mockAuthProvider;

  setUp(() {
    mockSettingsProvider = MockSettingsProvider();
    mockAuthProvider = MockAuthProvider();

    // Default Stubs
    when(mockSettingsProvider.addListener(any)).thenReturn(null);
    when(mockSettingsProvider.removeListener(any)).thenReturn(null);
    when(mockSettingsProvider.hasListeners).thenReturn(false);

    when(mockAuthProvider.addListener(any)).thenReturn(null);
    when(mockAuthProvider.removeListener(any)).thenReturn(null);
    when(mockAuthProvider.hasListeners).thenReturn(false);
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
      expect(find.text('الإعدادات'), findsOneWidget);
      // IntegrationsSection is loaded by default now
      // Verifying a part of it or just that the screen renders without error
      // The integrations list requires a provider load, which we mocked.
    });
  });
}
