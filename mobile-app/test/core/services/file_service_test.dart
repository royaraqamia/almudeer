import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:almudeer_mobile_app/core/services/file_service.dart';

// Generate Mocks
@GenerateMocks([FilePickerWrapper, FilePickerResult, PlatformFile])
import 'file_service_test.mocks.dart';

void main() {
  late FileService service;
  late MockFilePickerWrapper mockPicker;

  setUp(() {
    mockPicker = MockFilePickerWrapper();
    service = FileService.test(picker: mockPicker);
  });

  group('FileService', () {
    test('pickFiles returns list of files when success', () async {
      final mockResult = MockFilePickerResult();
      final mockFile = MockPlatformFile();

      when(mockResult.files).thenReturn([mockFile]);
      when(mockResult.paths).thenReturn(['/path/to/file']);

      when(
        mockPicker.pickFiles(
          type: anyNamed('type'),
          allowedExtensions: anyNamed('allowedExtensions'),
          allowMultiple: anyNamed('allowMultiple'),
        ),
      ).thenAnswer((_) async => mockResult);

      final result = await service.pickFiles();

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result.first.path, '/path/to/file');
    });

    test('pickFiles returns null when cancelled', () async {
      when(
        mockPicker.pickFiles(
          type: anyNamed('type'),
          allowedExtensions: anyNamed('allowedExtensions'),
          allowMultiple: anyNamed('allowMultiple'),
        ),
      ).thenAnswer((_) async => null);

      final result = await service.pickFiles();

      expect(result, isNull);
    });
  });
}
