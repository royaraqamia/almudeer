import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String path;
  MockPathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('media_cache_test');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('MediaCacheManager Tests', () {
    test('Hashed filename generation is stable', () async {
      final manager = MediaCacheManager();
      const url = 'https://example.com/files/image.jpg?token=123';

      final path1 = await manager.getPredictedPath(url);
      final path2 = await manager.getPredictedPath(url);

      expect(path1, isNotNull);
      expect(path1, equals(path2));
      expect(path1.contains('media_'), isTrue);
      expect(path1.endsWith('.jpg'), isTrue);
    });

    test('Different URLs generate different filenames', () async {
      final manager = MediaCacheManager();
      const url1 = 'https://example.com/a.jpg';
      const url2 = 'https://example.com/b.jpg';

      final path1 = await manager.getPredictedPath(url1);
      final path2 = await manager.getPredictedPath(url2);

      expect(path1, isNot(equals(path2)));
    });

    test('Hashing is stable across query parameter changes', () async {
      final manager = MediaCacheManager();
      const url1 = 'https://example.com/file.pdf?token=abc';
      const url2 = 'https://example.com/file.pdf?token=xyz';

      final path1 = await manager.getPredictedPath(url1);
      final path2 = await manager.getPredictedPath(url2);

      expect(path1, equals(path2));
    });

    test('Manual filename extension preference', () async {
      final manager = MediaCacheManager();
      const url = 'https://example.com/dynamic_file';
      const filename = 'document.pdf';

      final path = await manager.getPredictedPath(url, filename: filename);

      expect(path.endsWith('.pdf'), isTrue);
    });
  });
}
