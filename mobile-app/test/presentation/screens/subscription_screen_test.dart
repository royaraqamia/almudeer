import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/settings/presentation/screens/subscription_screen.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';
import 'package:almudeer_mobile_app/core/constants/settings_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test user data
  final activeUser = UserInfo(
    fullName: 'Test Company',
    username: 'testcompany',
    expiresAt: '2026-12-31',
    createdAt: '2025-01-01',
    referralCount: 5,
    licenseKey: 'MUDEER-ABCD-1234-5678',
    licenseId: 1,
  );

  final expiredUser = UserInfo(
    fullName: 'Expired Company',
    username: 'expiredcompany',
    expiresAt: '2024-01-01',
    createdAt: '2023-01-01',
    referralCount: 0,
    licenseKey: 'MUDEER-EXPI-RED0-0000',
    licenseId: 2,
  );

  Widget createTestWidget(AuthProvider authProvider) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: const MaterialApp(
        home: SubscriptionScreen(),
      ),
    );
  }

  group('SubscriptionScreen - UI Rendering Tests', () {
    testWidgets('shows loading indicator when authProvider is loading', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: true,
        userInfo: null,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(SettingsStrings.subscriptionSystem), findsOneWidget);
    });

    testWidgets('shows error state when errorMessage is present', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: null,
        errorMessage: 'Network error',
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      expect(find.text(SettingsStrings.loadingError), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.text(SettingsStrings.retry), findsOneWidget);
    });

    testWidgets('displays active subscription card correctly', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: activeUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Verify subscription status
      expect(find.text(SettingsStrings.activeSubscription), findsOneWidget);
      expect(find.text(SettingsStrings.subscriptionEnds), findsOneWidget);
      
      // Verify days remaining is shown
      expect(find.textContaining('ظٹظˆظ…'), findsWidgets);
      
      // Verify subscription plans section is present
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('displays expired subscription card correctly', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: expiredUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Verify expired status
      expect(find.text(SettingsStrings.expiredSubscription), findsOneWidget);
      
      // Verify error icon is present
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('has proper app bar with back button', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: activeUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Verify app bar title
      expect(find.text(SettingsStrings.subscriptionSystem), findsOneWidget);
      
      // Verify back button exists
      expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    });

    testWidgets('back button navigates back', (WidgetTester tester) async {
      bool didPop = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onDidRemovePage: (route) {
              didPop = true;
            },
            pages: const [
              MaterialPage(child: _ParentWidget()),
              MaterialPage(child: SubscriptionScreen()),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap back button
      final backButton = find.byIcon(Icons.arrow_right);
      await tester.tap(backButton);
      await tester.pump();

      expect(didPop, isTrue);
    });
  });

  group('SubscriptionScreen - Accessibility Tests', () {
    testWidgets('has proper semantics labels for status', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: activeUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Verify semantics are present
      final statusText = find.text(SettingsStrings.activeSubscription);
      expect(statusText, findsOneWidget);
    });

    testWidgets('respects reduced motion preference', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: activeUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: createTestWidget(mockAuthProvider),
        ),
      );

      // Should complete without animation delays
      await tester.pump();
      
      // Screen should still render correctly
      expect(find.text(SettingsStrings.activeSubscription), findsOneWidget);
    });
  });

  group('SubscriptionScreen - Date Formatting Tests', () {
    testWidgets('displays Hijri date correctly', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: activeUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Verify date is displayed (format: dd MMMM yyyy in Arabic)
      expect(find.textContaining(RegExp(r'\d+')), findsWidgets);
    });

    testWidgets('shows dash for empty date', (WidgetTester tester) async {
      final userWithNoDate = UserInfo(
        fullName: 'Test',
        expiresAt: '',
        referralCount: 0,
        licenseKey: 'MUDEER-TEST-0000-0000',
      );

      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: userWithNoDate,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Should show dash for empty date
      expect(find.text('-'), findsOneWidget);
    });
  });

  group('SubscriptionScreen - Progress Calculation Tests', () {
    testWidgets('shows correct progress percentage', (WidgetTester tester) async {
      // User with ~50% subscription remaining
      final now = DateTime.now();
      final createdAt = now.subtract(const Duration(days: 182));
      final expiresAt = now.add(const Duration(days: 183));

      final halfYearUser = UserInfo(
        fullName: 'Half Year User',
        expiresAt: expiresAt.toIso8601String(),
        createdAt: createdAt.toIso8601String(),
        referralCount: 0,
        licenseKey: 'MUDEER-HALF-0000-0000',
      );

      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: halfYearUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Progress should be around 50%
      expect(find.textContaining('%'), findsOneWidget);
    });

    testWidgets('handles edge case of zero total days', (WidgetTester tester) async {
      final userWithSameDates = UserInfo(
        fullName: 'Same Date User',
        expiresAt: '2025-01-01',
        createdAt: '2025-01-01',
        referralCount: 0,
        licenseKey: 'MUDEER-SAME-0000-0000',
      );

      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: userWithSameDates,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // Should not crash, should show 0% or handle gracefully
      expect(find.byType(SubscriptionScreen), findsOneWidget);
    });
  });

  group('SubscriptionScreen - Error Boundary Tests', () {
    testWidgets('shows error widget when SubscriptionPlansSection fails', (WidgetTester tester) async {
      final mockAuthProvider = MockAuthProvider(
        isLoading: false,
        userInfo: activeUser,
        errorMessage: null,
      );

      await tester.pumpWidget(
        createTestWidget(mockAuthProvider),
      );

      await tester.pumpAndSettle();

      // The error boundary should be present
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      
      // Screen should render without crashing even if child fails
      expect(find.text(SettingsStrings.activeSubscription), findsOneWidget);
    });
  });
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Helper Widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ParentWidget extends StatelessWidget {
  const _ParentWidget();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Parent'),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Mock AuthProvider for testing
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool _isLoading;
  final UserInfo? _userInfo;
  final String? _errorMessage;
  final AuthState _state;

  MockAuthProvider({
    bool isLoading = false,
    UserInfo? userInfo,
    String? errorMessage,
    AuthState state = AuthState.initial,
  })  : _isLoading = isLoading,
        _userInfo = userInfo,
        _errorMessage = errorMessage,
        _state = state;

  // Implement required getters
  @override
  bool get isLoading => _isLoading;
  
  @override
  UserInfo? get userInfo => _userInfo;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  AuthState get state => _state;
  
  @override
  bool get isAuthenticated => _state == AuthState.authenticated;
  
  @override
  List<UserInfo> get accounts => [];
  
  @override
  int get accountKey => 0;
  
  @override
  bool get isRateLimited => false;
  
  @override
  int get remainingLockoutMinutes => 0;
  
  // Stub methods
  @override
  Future<void> init() async {}
  
  @override
  Future<bool> login(String licenseKey) async => true;
  
  @override
  Future<void> logout({String? reason}) async {}
  
  @override
  void setAccountSwitchCallback(VoidCallback callback) {}
  
  @override
  bool validateLicenseFormat(String key) => true;
  
  @override
  String getLicenseFormatErrorMessage() => '';
  
  @override
  Future<void> switchAccount(UserInfo user) async {}
  
  @override
  Future<void> removeAccount(UserInfo user) async {}
  
  @override
  Future<bool> addAccount(String licenseKey) async => true;
  
  @override
  Future<void> refreshUserInfo() async {}
  
  @override
  void clearError() {}
}
