import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/photo_errors.dart';
import 'package:mamba_app/features/results/ocr_service.dart' as results;

void main() {
  test('camera permission refused tells where to switch it on', () {
    final t = describePhotoError(PlatformException(code: 'camera_access_denied'))!;
    expect(t, contains('Cài đặt'));
    expect(t, contains('Camera'));
  });
  test('no camera (simulator) suggests the library; other errors are not photo errors', () {
    expect(describePhotoError(PlatformException(code: 'no_available_camera')), contains('thư viện'));
    expect(describePhotoError(Exception('x')), isNull);
    expect(describePhotoError(PlatformException(code: 'weird')), isNull);
  });
  test('the OCR reader uses the same sentences', () {
    expect(results.describeOcrError(PlatformException(code: 'camera_access_denied')), contains('Cài đặt'));
  });
}
