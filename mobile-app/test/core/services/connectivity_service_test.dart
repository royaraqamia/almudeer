import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:almudeer_mobile_app/core/services/connectivity_service.dart';

// Generate Mocks
@GenerateMocks([Connectivity, http.Client])
import 'connectivity_service_test.mocks.dart';

void main() {
  late ConnectivityService service;
  late MockConnectivity mockConnectivity;
  late MockClient mockClient;
  late StreamController<List<ConnectivityResult>> connectivityStream;

  setUp(() {
    mockConnectivity = MockConnectivity();
    mockClient = MockClient();
    connectivityStream = StreamController<List<ConnectivityResult>>();

    // Setup mocks
    when(
      mockClient.get(any, headers: anyNamed('headers')),
    ).thenAnswer((_) async => http.Response('ok', 200));

    when(
      mockConnectivity.onConnectivityChanged,
    ).thenAnswer((_) => connectivityStream.stream);

    when(
      mockConnectivity.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.wifi]);

    service = ConnectivityService.test(
      connectivity: mockConnectivity,
      client: mockClient,
    );
  });

  tearDown(() {
    connectivityStream.close();
    service.dispose();
  });

  group('ConnectivityService', () {
    test('initializes with correct status', () async {
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('ok', 200));

      await service.initialize();

      expect(service.status, ConnectivityStatus.online);
      verify(mockConnectivity.checkConnectivity()).called(1);
    });

    test('updates status on connectivity change', () async {
      await service.initialize();

      // Mock offline result
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('ok', 200));

      // Simulate going offline
      connectivityStream.add([ConnectivityResult.none]);
      await Future.delayed(Duration(milliseconds: 600)); // Debounce

      expect(service.status, ConnectivityStatus.offline);

      // Simulate coming back online
      connectivityStream.add([ConnectivityResult.wifi]);
      await Future.delayed(Duration(milliseconds: 600)); // Debounce

      expect(service.status, ConnectivityStatus.online);
    });

    test('verifies server reachability', () async {
      await service.initialize();

      // Simulate WiFi but server down (500)
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('server error', 500));

      connectivityStream.add([ConnectivityResult.wifi]);
      await Future.delayed(Duration(milliseconds: 600));

      // Should be offline because server is down
      expect(service.status, ConnectivityStatus.offline);
      expect(service.isServerReachable, false);
    });
  });
}
