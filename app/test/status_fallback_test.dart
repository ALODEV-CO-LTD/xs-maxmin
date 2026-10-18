import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/api_client.dart';

void main() {
  test('413 and 429 without a JSON body get a clear Vietnamese message', () {
    expect(statusFallbackMessage(413), contains('quá lớn'));
    expect(statusFallbackMessage(429), contains('quá nhanh'));
    expect(statusFallbackMessage(500), 'Lỗi máy chủ (500)');
  });
}
