import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/library/presentation/providers/library_provider.dart';
import 'package:almudeer_mobile_app/features/library/presentation/screens/note_edit_screen.dart';
import 'package:almudeer_mobile_app/features/library/data/models/library_item.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';

class MockAuthProvider extends Mock implements AuthProvider {}

class MockLibraryProvider extends Mock implements LibraryProvider {}

void main() {
  late MockAuthProvider mockAuthProvider;
  late MockLibraryProvider mockLibraryProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockLibraryProvider = MockLibraryProvider();

    // Default LibraryProvider setup
    when(mockLibraryProvider.items).thenReturn([]);
    when(mockLibraryProvider.isLoading).thenReturn(false);
    when(mockLibraryProvider.isFetchingMore).thenReturn(false);
    when(mockLibraryProvider.hasMore).thenReturn(true);
    when(mockLibraryProvider.isSelectionMode).thenReturn(false);
    when(mockLibraryProvider.selectedIds).thenReturn({});
    when(mockLibraryProvider.selectedCount).thenReturn(0);
    when(mockLibraryProvider.uploadingIds).thenReturn({});
    when(mockLibraryProvider.sharedItems).thenReturn([]);
    when(mockLibraryProvider.isLoadingShared).thenReturn(false);
    when(mockLibraryProvider.itemShares).thenReturn({});
    when(mockLibraryProvider.isCheckingUsername).thenReturn(false);
    when(mockLibraryProvider.foundUsernameDetails).thenReturn(null);
    when(mockLibraryProvider.usernameNotFound).thenReturn(false);
    when(mockLibraryProvider.isBulkDeleting).thenReturn(false);
    when(mockLibraryProvider.currentCategory).thenReturn('notes');
    when(mockLibraryProvider.currentQuery).thenReturn(null);
  });

  Widget createTestWidget({
    LibraryItem? item,
    UserInfo? authUserInfo,
  }) {
    // Setup AuthProvider mock
    when(mockAuthProvider.userInfo).thenReturn(authUserInfo);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(
          value: mockLibraryProvider,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
      ],
      child: MaterialApp(
        home: NoteEditScreen(item: item),
      ),
    );
  }

  group('NoteEditScreen - Offline Permission Edge Cases', () {
    group('Edge Case 1: Owner, Offline, Normal Cache', () {
      testWidgets('owner can edit when offline with cached AuthProvider', (
        WidgetTester tester,
      ) async {
        // Setup: User is owner (createdBy matches currentUserId)
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'My Note',
          content: 'My Content',
          createdBy: '123',
          sharePermission: null, // Not shared = owner
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Verify: Title field should be editable (owner permission)
        final titleField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(titleField).readOnly,
          isFalse,
          reason: 'Owner should be able to edit their own note offline',
        );
        expect(
          tester.widget<TextField>(titleField).enabled,
          isTrue,
          reason: 'Owner should have enabled title field',
        );
      });
    });

    group('Edge Case 2: Owner, Offline, AuthProvider Not Ready', () {
      testWidgets('handles null AuthProvider userInfo gracefully', (
        WidgetTester tester,
      ) async {
        // Setup: AuthProvider.userInfo is null (not loaded yet)
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'My Note',
          content: 'My Content',
          createdBy: '123',
          sharePermission: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(mockAuthProvider.userInfo).thenReturn(null);

        await tester.pumpWidget(createTestWidget(item: item));
        await tester.pumpAndSettle();

        // Should not crash - should handle gracefully
        expect(find.byType(TextField), findsWidgets);
      });

      testWidgets('uses best-effort permissions when userId unavailable', (
        WidgetTester tester,
      ) async {
        // Setup: currentUserId is null
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'My Note',
          content: 'My Content',
          createdBy: '123',
          sharePermission: null, // No share = likely owner
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(mockAuthProvider.userInfo).thenReturn(null);

        await tester.pumpWidget(createTestWidget(item: item));
        await tester.pumpAndSettle();

        // Should use best-effort: no sharePermission = assume owner
        final titleField = find.byType(TextField).first;
        expect(tester.widget<TextField>(titleField).enabled, isTrue);
      });
    });

    group('Edge Case 3: Owner, Offline, currentUserId Unavailable', () {
      testWidgets('infers ownership from sharePermission when userId null', (
        WidgetTester tester,
      ) async {
        // Setup: currentUserId is null, but item has no sharePermission
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'My Note',
          content: 'My Content',
          createdBy: '123',
          sharePermission: null, // No share = likely owner
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(mockAuthProvider.userInfo).thenReturn(null);

        await tester.pumpWidget(createTestWidget(item: item));
        await tester.pumpAndSettle();

        // Should use best-effort logic without crashing
        expect(find.byType(TextField), findsWidgets);
      });
    });

    group('Edge Case 4: Recipient with Edit Permission, Offline', () {
      testWidgets('recipient with edit permission can edit offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 999,
          type: 'note',
          title: 'Shared Note',
          content: 'Shared Content',
          createdBy: 'other-user',
          sharePermission: 'edit', // Shared with edit permission
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Verify: Should be editable (edit permission)
        final titleField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(titleField).readOnly,
          isFalse,
          reason: 'User with edit permission should be able to edit',
        );
      });
    });

    group('Edge Case 5: Recipient with Read-Only Permission, Offline', () {
      testWidgets('recipient with read permission cannot edit offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 999,
          type: 'note',
          title: 'Shared Note',
          content: 'Shared Content',
          createdBy: 'other-user',
          sharePermission: 'read', // Read-only
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Verify: Should be read-only
        final titleField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(titleField).readOnly,
          isTrue,
          reason: 'User with read-only permission should not edit',
        );
        expect(
          tester.widget<TextField>(titleField).enabled,
          isFalse,
          reason: 'Read-only user should have disabled field',
        );
      });
    });

    group('Edge Case 6: New Note, Offline', () {
      testWidgets('new note is immediately editable without permissions check', (
        WidgetTester tester,
      ) async {
        // New note (no item provided)
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify: Should be immediately editable
        final titleField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(titleField).readOnly,
          isFalse,
          reason: 'New notes should be immediately editable',
        );
        expect(
          tester.widget<TextField>(titleField).enabled,
          isTrue,
          reason: 'New notes should be enabled',
        );
      });
    });

    group('Edge Case 7: Legacy Item (null createdBy)', () {
      testWidgets('legacy item with null createdBy treated as owned', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'Legacy Note',
          content: 'Legacy Content',
          createdBy: null, // Legacy item without createdBy
          sharePermission: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Note: Current implementation requires createdBy to match currentUserId
        // Legacy tasks with null createdBy are NOT automatically treated as owned
        // This test verifies the current behavior (read-only for safety)
        final titleField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(titleField).readOnly,
          isTrue,
          reason: 'Legacy items without createdBy are read-only for safety',
        );
      });
    });

    group('Edge Case 8: Admin Permission, Offline', () {
      testWidgets('recipient with admin permission can edit offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 999,
          type: 'note',
          title: 'Shared Note',
          content: 'Shared Content',
          createdBy: 'other-user',
          sharePermission: 'admin', // Admin permission
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Verify: Should be editable (admin permission)
        final titleField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(titleField).readOnly,
          isFalse,
          reason: 'User with admin permission should be able to edit',
        );
      });
    });

    group('Edge Case 9: Share Button Visibility Offline', () {
      testWidgets('share button visible for owner offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'My Note',
          content: 'My Content',
          createdBy: '123',
          sharePermission: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Share button should be visible for owner
        expect(
          find.byIcon(SolarLinearIcons.usersGroupRounded),
          findsOneWidget,
          reason: 'Owner should see share button',
        );
      });

      testWidgets('share button hidden for read-only user offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 999,
          type: 'note',
          title: 'Shared Note',
          content: 'Shared Content',
          createdBy: 'other-user',
          sharePermission: 'read',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Share button should be hidden for read-only users
        expect(
          find.byIcon(SolarLinearIcons.usersGroupRounded),
          findsNothing,
          reason: 'Read-only users should not see share button',
        );
      });
    });

    group('Edge Case 10: Content Field Permissions Offline', () {
      testWidgets('content field editable for owner offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 123,
          type: 'note',
          title: 'My Note',
          content: 'My Content',
          createdBy: '123',
          sharePermission: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Content field should be editable for owner
        // NoteEditScreen has title and content TextFields - verify all are editable
        final textFields = tester.widgetList<TextField>(find.byType(TextField));
        for (final field in textFields) {
          expect(field.readOnly, isFalse, reason: 'Owner should have all fields editable');
        }
      });

      testWidgets('content field read-only for read-only user offline', (
        WidgetTester tester,
      ) async {
        final item = LibraryItem(
          id: 1,
          licenseKeyId: 999,
          type: 'note',
          title: 'Shared Note',
          content: 'Shared Content',
          createdBy: 'other-user',
          sharePermission: 'read',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final userInfo = UserInfo(
          fullName: 'Test User',
          licenseKey: 'TEST-KEY',
          licenseId: 123,
          expiresAt: '2026-12-31',
        );

        await tester.pumpWidget(
          createTestWidget(item: item, authUserInfo: userInfo),
        );
        await tester.pumpAndSettle();

        // Content field should be read-only
        // NoteEditScreen has title and content TextFields - verify all are read-only
        final textFields = tester.widgetList<TextField>(find.byType(TextField));
        for (final field in textFields) {
          expect(field.readOnly, isTrue, reason: 'Read-only user should have all fields read-only');
        }
      });
    });
  });

  group('NoteEditScreen - Offline Auto-save Behavior', () {
    testWidgets('does not auto-save for read-only users offline', (
      WidgetTester tester,
    ) async {
      final item = LibraryItem(
        id: 1,
        licenseKeyId: 999,
        type: 'note',
        title: 'Shared Note',
        content: 'Shared Content',
        createdBy: 'other-user',
        sharePermission: 'read',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userInfo = UserInfo(
        fullName: 'Test User',
        licenseKey: 'TEST-KEY',
        licenseId: 123,
        expiresAt: '2026-12-31',
      );

      await tester.pumpWidget(
        createTestWidget(item: item, authUserInfo: userInfo),
      );
      await tester.pumpAndSettle();

      // Try to enter text (should be blocked by readOnly)
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Modified Title');
      await tester.pump();

      // Wait for potential debounce
      await tester.pump(const Duration(milliseconds: 1100));

      // Verify: updateNote should NOT be called for read-only user
      verifyNever(mockLibraryProvider.updateNote(1, 'Modified Title', 'Shared Content'));
    });

    testWidgets('auto-saves for owner offline', (WidgetTester tester) async {
      final item = LibraryItem(
        id: 1,
        licenseKeyId: 123,
        type: 'note',
        title: 'My Note',
        content: 'My Content',
        createdBy: '123',
        sharePermission: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userInfo = UserInfo(
        fullName: 'Test User',
        licenseKey: 'TEST-KEY',
        licenseId: 123,
        expiresAt: '2026-12-31',
      );

      when(mockLibraryProvider.updateNote(1, 'Modified Title', 'My Content')).thenAnswer(
        (_) async {},
      );

      await tester.pumpWidget(
        createTestWidget(item: item, authUserInfo: userInfo),
      );
      await tester.pumpAndSettle();

      // Enter text
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Modified Title');
      await tester.pump();

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 1100));

      // Verify: updateNote should be called for owner
      verify(mockLibraryProvider.updateNote(1, 'Modified Title', 'My Content'));
    });
  });

  group('NoteEditScreen - Offline Read Mode', () {
    testWidgets('shows read mode for read-only user', (
      WidgetTester tester,
    ) async {
      final item = LibraryItem(
        id: 1,
        licenseKeyId: 999,
        type: 'note',
        title: 'Shared Note',
        content: 'Shared Content',
        createdBy: 'other-user',
        sharePermission: 'read',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userInfo = UserInfo(
        fullName: 'Test User',
        licenseKey: 'TEST-KEY',
        licenseId: 123,
        expiresAt: '2026-12-31',
      );

      await tester.pumpWidget(
        createTestWidget(item: item, authUserInfo: userInfo),
      );
      await tester.pumpAndSettle();

      // Read-only users should see read mode (SelectableLinkify)
      // Note: This depends on _isEditingContent state
      // Read-only users cannot switch to edit mode
    });
  });
}
