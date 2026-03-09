import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/data/repositories/customers_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/data/datasources/local/customers_local_datasource.dart';
import 'package:almudeer_mobile_app/core/services/connectivity_service.dart';

// Generate Mocks
@GenerateMocks([ApiClient, ConnectivityService, CustomersLocalDataSource])
import 'customers_repository_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CustomersRepository repository;
  late MockApiClient mockApiClient;
  late MockConnectivityService mockConnectivityService;
  late MockCustomersLocalDataSource mockLocalDataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    mockConnectivityService = MockConnectivityService();
    mockLocalDataSource = MockCustomersLocalDataSource();

    // Default stub for getAccountCacheHash
    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test-hash');
    when(mockConnectivityService.isOnline).thenReturn(true);
    when(mockConnectivityService.isOffline).thenReturn(false);

    repository = CustomersRepository(
      apiClient: mockApiClient,
      connectivityService: mockConnectivityService,
      localDataSource: mockLocalDataSource,
    );

    // Mock path_provider MethodChannel to avoid MissingPluginException
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  group('CustomersRepository', () {
    test('getCustomers returns Map response', () async {
      // Arrange
      final localCustomers = [
        {'id': 1, 'name': 'John'},
      ];

      when(
        mockLocalDataSource.getCustomers(
          search: anyNamed('search'),
          limit: anyNamed('limit'),
          offset: anyNamed('offset'),
        ),
      ).thenAnswer((_) async => localCustomers);

      // Act
      final result = await repository.getCustomers(page: 1);

      // Assert
      expect(result['results'].length, 1);
      expect(result['results'][0]['name'], 'John');
      verify(mockLocalDataSource.getCustomers(limit: 20, offset: 0)).called(1);
    });

    test('getCustomerDetail returns Local Data if available', () async {
      // Arrange
      final localCustomer = {'id': 1, 'name': 'John'};

      when(
        mockLocalDataSource.getCustomer(1),
      ).thenAnswer((_) async => localCustomer);

      // Act
      final result = await repository.getCustomerDetail(1);

      // Assert
      expect(result['id'], 1);
      verify(mockLocalDataSource.getCustomer(1)).called(1);
      verifyNever(mockApiClient.get(any));
    });

    test('updateCustomer calls patch and updates local', () async {
      // Arrange
      final updateData = {'name': 'Jane'};
      final responseData = {'id': 1, 'name': 'Jane'};

      when(
        mockApiClient.patch(any, body: anyNamed('body')),
      ).thenAnswer((_) async => responseData);

      // Act
      await repository.updateCustomer(1, updateData);

      // Assert
      verify(
        mockLocalDataSource.updateCustomerLocally(1, updateData),
      ).called(1);
      verify(
        mockApiClient.patch(Endpoints.customer(1), body: updateData),
      ).called(1);
      verify(mockLocalDataSource.cacheCustomer(responseData)).called(1);
    });
  });
}
