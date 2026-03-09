import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:almudeer_mobile_app/core/services/download_service.dart';

// Generate Mocks
@GenerateMocks([Dio, Response])
import 'download_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DownloadService service;
  late MockDio mockDio;

  setUp(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '.';
        });

    mockDio = MockDio();
    service = DownloadService.test(dio: mockDio);
  });

  group('DownloadService', () {
    test('downloadApk calls dio.download', () async {
      final mockResponse = MockResponse();
      when(mockResponse.statusCode).thenReturn(200);

      when(
        mockDio.download(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          deleteOnError: anyNamed('deleteOnError'),
          lengthHeader: anyNamed('lengthHeader'),
          data: anyNamed('data'),
          options: anyNamed('options'),
        ),
      ).thenAnswer((_) async => mockResponse);

      final stream = service.downloadApk('http://example.com/app.apk');
      await for (final _ in stream) {}

      verify(
        mockDio.download(
          argThat(equals('http://example.com/app.apk')),
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          deleteOnError: anyNamed('deleteOnError'),
          lengthHeader: anyNamed('lengthHeader'),
          data: anyNamed('data'),
          options: anyNamed('options'),
        ),
      ).called(1);
    });
  });
}
