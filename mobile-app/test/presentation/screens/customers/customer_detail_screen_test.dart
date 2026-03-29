import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/providers/customers_provider.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/providers/conversation_detail_provider.dart';

class MockCustomersProvider extends Mock implements CustomersProvider {}

class MockAuthProvider extends Mock implements AuthProvider {}

class MockConversationDetailProvider extends Mock
    implements ConversationDetailProvider {}

void main() {
  group('CustomerDetailScreen', () {
    late MockCustomersProvider mockCustomersProvider;
    late MockAuthProvider mockAuthProvider;
    late MockConversationDetailProvider mockConversationDetailProvider;

    final testCustomer = {
      'id': 1,
      'username': 'testuser',
      'name': 'Test User',
      'phone': '+966501234567',
      'profile_pic_url': null,
      'image': null,
      'is_almudeer_user': true,
      'is_online': false,
      'last_seen_at': '2024-01-15T10:30:00Z',
      'is_vip': false,
    };

    setUp(() {
      mockCustomersProvider = MockCustomersProvider();
      mockAuthProvider = MockAuthProvider();
      mockConversationDetailProvider = MockConversationDetailProvider();

      // Setup CustomersProvider mocks
      when(mockCustomersProvider.customers).thenReturn([]);
      when(mockCustomersProvider.isCheckingUsername).thenReturn(false);
      when(mockCustomersProvider.foundUsernameDetails).thenReturn(null);
      when(mockCustomersProvider.usernameNotFound).thenReturn(false);
      when(mockCustomersProvider.addListener(() {})).thenAnswer((_) {});
      when(mockCustomersProvider.removeListener(() {})).thenAnswer((_) {});
      when(mockCustomersProvider.lookupUsername('__unused__')).thenAnswer((_) async {});
      when(mockCustomersProvider.clearUsernameLookup()).thenAnswer((_) {});
      when(mockCustomersProvider.refresh()).thenAnswer((_) async {});
      when(mockCustomersProvider.updateCustomerInList(<String, dynamic>{})).thenAnswer((_) {});
      when(mockCustomersProvider.getCustomerByContact('__unused__')).thenReturn(null);

      // Setup AuthProvider mocks
      when(mockAuthProvider.userInfo).thenReturn(null);

      // Setup ConversationDetailProvider mocks
      when(mockConversationDetailProvider.isPeerTyping).thenReturn(false);
      when(mockConversationDetailProvider.isPeerRecording).thenReturn(false);
      when(mockConversationDetailProvider.isPeerOnline).thenReturn(false);
      when(mockConversationDetailProvider.peerLastSeen).thenReturn(null);
      when(mockConversationDetailProvider.loadConversation(
        '__unused__',
        channel: null,
        fresh: true,
        lastSeenAt: null,
        isOnline: false,
        skipAutoRefresh: false,
      )).thenAnswer((_) async {});
    });

    Widget createTestWidget({Map<String, dynamic>? customer}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomersProvider>.value(
            value: mockCustomersProvider,
          ),
          ChangeNotifierProvider<AuthProvider>.value(
            value: mockAuthProvider,
          ),
          ChangeNotifierProvider<ConversationDetailProvider>.value(
            value: mockConversationDetailProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomerDetailScreen(
              customer: customer ?? testCustomer,
            ),
          ),
        ),
      );
    }

    group('UI Rendering', () {
      testWidgets('displays customer name correctly', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Test User'), findsWidgets);
      });

      testWidgets('displays back button', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byTooltip('ط±ط¬ظˆط¹'), findsOneWidget);
      });

      testWidgets('displays chat button for Almudeer user', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('ظ…ط±ط§ط³ظ„ط©'), findsOneWidget);
      });
    });

    group('Online Status', () {
      testWidgets('displays online status for online user', (tester) async {
        final onlineCustomer = {
          ...testCustomer,
          'is_online': true,
        };

        when(mockConversationDetailProvider.isPeerOnline).thenReturn(true);

        await tester.pumpWidget(createTestWidget(customer: onlineCustomer));
        await tester.pumpAndSettle();

        expect(find.text('ظ…طھظژظ‘طµظ„ ط§ظ„ط¢ظ†'), findsOneWidget);
      });

      testWidgets('displays typing status', (tester) async {
        when(mockConversationDetailProvider.isPeerTyping).thenReturn(true);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('ظٹظƒطھط¨...'), findsOneWidget);
      });

      testWidgets('displays recording status', (tester) async {
        when(mockConversationDetailProvider.isPeerRecording).thenReturn(true);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('ظٹط³ط¬ظگظ‘ظ„ ظ…ظ‚ط·ط¹ طµظˆطھظٹ...'), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('handles null customer data gracefully', (tester) async {
        final nullCustomer = {
          'id': null,
          'username': null,
          'name': null,
          'phone': null,
          'is_almudeer_user': false,
          'is_online': false,
        };

        await tester.pumpWidget(createTestWidget(customer: nullCustomer));
        await tester.pumpAndSettle();

        // Should not crash - check for default text instead
        expect(find.text('ط´ط®طµ'), findsOneWidget);
      });

      testWidgets('handles missing last_seen_at', (tester) async {
        final customerWithoutLastSeen = {
          ...testCustomer,
          'last_seen_at': null,
        };

        await tester.pumpWidget(createTestWidget(customer: customerWithoutLastSeen));
        await tester.pumpAndSettle();

        // Should render without crashing
        expect(find.text('Test User'), findsWidgets);
      });
    });

    group('Accessibility', () {
      testWidgets('has proper tooltip for back button', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final backButton = find.byTooltip('ط±ط¬ظˆط¹');
        expect(backButton, findsOneWidget);
      });
    });

    group('VIP Customer', () {
      testWidgets('renders VIP customer', (tester) async {
        final vipCustomer = {
          ...testCustomer,
          'is_vip': true,
        };

        await tester.pumpWidget(createTestWidget(customer: vipCustomer));
        await tester.pumpAndSettle();

        // Should render without crashing
        expect(find.text('Test User'), findsWidgets);
      });
    });

    group('Non-Almudeer User', () {
      testWidgets('hides chat button for non-Almudeer user', (tester) async {
        final nonAlmudeerCustomer = {
          ...testCustomer,
          'is_almudeer_user': false,
        };

        await tester.pumpWidget(createTestWidget(customer: nonAlmudeerCustomer));
        await tester.pumpAndSettle();

        expect(find.text('ظ…ط±ط§ط³ظ„ط©'), findsNothing);
      });
    });
  });
}
