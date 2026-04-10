import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/library/presentation/providers/library_provider.dart';
import 'package:almudeer_mobile_app/features/library/presentation/screens/library_screen.dart';
import 'package:almudeer_mobile_app/features/library/data/models/library_item.dart';
import 'package:almudeer_mobile_app/features/library/data/repositories/library_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';

class MockLibraryRepository extends Mock implements LibraryRepository {}

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockLibraryRepository mockRepository;
  late MockApiClient mockApiClient;
  late LibraryProvider provider;

  setUp(() {
    mockRepository = MockLibraryRepository();
    mockApiClient = MockApiClient();

    // Stub apiClient getter
    when(mockRepository.apiClient).thenReturn(mockApiClient);

    // Stub getAccountCacheHash
    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test_hash');

    // Stub syncStream
    when(mockRepository.syncStream).thenAnswer((_) => const Stream.empty());

    // Stub getItemsStream
    when(
      mockRepository.getItemsStream(
        customerId: anyNamed('customerId'),
        category: anyNamed('category'),
        searchQuery: anyNamed('searchQuery'),
      ),
    ).thenAnswer((invocation) {
      final searchQuery =
          invocation.namedArguments[const Symbol('searchQuery')] as String?;

      if (searchQuery != null && searchQuery == 'Test') {
        return Stream.value([
          LibraryItem(
            id: 1,
            title: 'Test Item',
            type: 'note',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            licenseKeyId: 1,
          ),
        ]);
      }

      // Default return (simulate items)
      final items = List.generate(
        50,
        (index) => LibraryItem(
          id: index,
          title: 'Item $index',
          type: 'note',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          licenseKeyId: 1,
        ),
      );
      return Stream.value(items);
    });

    // Stub updateItem
    when(
      mockRepository.updateItem(
        1,
        title: 'Test Item',
        content: anyNamed('content'),
        customerId: anyNamed('customerId'),
      ),
    ).thenAnswer((_) async => true);
    when(
      mockRepository.updateItem(
        0,
        title: 'Item 0',
        content: anyNamed('content'),
        customerId: anyNamed('customerId'),
      ),
    ).thenAnswer((_) async => true);

    provider = LibraryProvider(repository: mockRepository);
  });

  group('LibraryScreen Integration Tests', () {
    testWidgets('renders list of items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: provider,
            child: const LibraryScreen(),
          ),
        ),
      );

      provider.fetchItems(refresh: true);
      await tester.pumpAndSettle();

      expect(find.text('Item 0'), findsOneWidget);
    });

    testWidgets('search filters items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: provider,
            child: const LibraryScreen(),
          ),
        ),
      );

      provider.fetchItems(query: 'Test', refresh: true);
      await tester.pumpAndSettle();

      expect(provider.items.length, 1);
      expect(provider.items.first.title, 'Test Item');
    });

    test('Provider Logic: Pagination', () async {
      // Page 1
      provider.fetchItems(refresh: true);
      expect(provider.isLoading, true); // Loading starts

      // Wait for stream to emit
      await Future.delayed(Duration.zero);

      // Since stream is async, we can't easily sync check items immediately without waiting for stream
      // But verify call was made
      verify(
        mockRepository.getItemsStream(
          category: anyNamed('category'),
          searchQuery: anyNamed('searchQuery'),
          customerId: anyNamed('customerId'),
        ),
      ).called(greaterThan(0));
    });
  });
}
