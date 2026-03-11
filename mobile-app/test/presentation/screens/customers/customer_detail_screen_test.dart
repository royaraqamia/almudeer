import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/presentation/screens/customers/customer_detail_screen.dart';
import 'package:almudeer_mobile_app/presentation/providers/customers_provider.dart';
import 'package:almudeer_mobile_app/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/presentation/providers/conversation_detail_provider.dart';

import 'customer_detail_screen_test.mocks.dart';

@GenerateMocks([
  CustomersProvider,
  AuthProvider,
  ConversationDetailProvider,
])
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
      'email': 'test@example.com',
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
      when(mockCustomersProvider.addListener(any)).thenAnswer((_) {});
      when(mockCustomersProvider.removeListener(any)).thenAnswer((_) {});
      when(mockCustomersProvider.lookupUsername(any)).thenAnswer((_) async {});
      when(mockCustomersProvider.clearUsernameLookup()).thenAnswer((_) {});
      when(mockCustomersProvider.refresh()).thenAnswer((_) async {});
      when(mockCustomersProvider.updateCustomerInList(any)).thenAnswer((_) {});
      when(mockCustomersProvider.getCustomerByContact(any)).thenReturn(null);

      // Setup AuthProvider mocks
      when(mockAuthProvider.userInfo).thenReturn(null);

      // Setup ConversationDetailProvider mocks
      when(mockConversationDetailProvider.isPeerTyping).thenReturn(false);
      when(mockConversationDetailProvider.isPeerRecording).thenReturn(false);
      when(mockConversationDetailProvider.isPeerOnline).thenReturn(false);
      when(mockConversationDetailProvider.peerLastSeen).thenReturn(null);
      when(mockConversationDetailProvider.loadConversation(
        any,
        channel: anyNamed('channel'),
        fresh: anyNamed('fresh'),
        lastSeenAt: anyNamed('lastSeenAt'),
        isOnline: anyNamed('isOnline'),
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

        expect(find.byTooltip('رجوع'), findsOneWidget);
      });

      testWidgets('displays chat button for Almudeer user', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('مراسلة'), findsOneWidget);
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

        expect(find.text('متَّصل الآن'), findsOneWidget);
      });

      testWidgets('displays typing status', (tester) async {
        when(mockConversationDetailProvider.isPeerTyping).thenReturn(true);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('يكتب...'), findsOneWidget);
      });

      testWidgets('displays recording status', (tester) async {
        when(mockConversationDetailProvider.isPeerRecording).thenReturn(true);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('يسجِّل مقطع صوتي...'), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('handles null customer data gracefully', (tester) async {
        final nullCustomer = {
          'id': null,
          'username': null,
          'name': null,
          'phone': null,
          'email': null,
          'is_almudeer_user': false,
          'is_online': false,
        };

        await tester.pumpWidget(createTestWidget(customer: nullCustomer));
        await tester.pumpAndSettle();

        // Should not crash - check for default text instead
        expect(find.text('شخص'), findsOneWidget);
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

        final backButton = find.byTooltip('رجوع');
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

        expect(find.text('مراسلة'), findsNothing);
      });
    });
  });
}
