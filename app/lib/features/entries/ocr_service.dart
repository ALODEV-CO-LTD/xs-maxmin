import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'message_parser.dart';

/// On-device text recognition (ML Kit): the photo never leaves the phone. Throws on failure.
Future<String> recognizeImageText(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return result.text;
  } finally {
    await recognizer.close();
  }
}

/// Suggestions from OCR text. The message parser understands "de 12 34 x 10"; when it finds nothing, every group of
/// 2-4 digits becomes a row without a score (what the web app does). The result is only a SUGGESTION list.
List<ParsedRow> suggestionsFromOcr(String text, {List<String> betTypes = const ['de', 'lo'], SyntaxTemplate? template}) {
  final parsed = parseMessage(text, betTypes: betTypes, template: template).rows.where((r) => r.value.isNotEmpty).toList();
  if (parsed.isNotEmpty) {
    for (final r in parsed) {
      r.reasons.add('Đọc từ ảnh, hãy kiểm tra lại');
    }
    return parsed;
  }
  final type = template != null && template.defaultType.isNotEmpty ? template.defaultType : (betTypes.isNotEmpty ? betTypes.first : 'de');
  return [
    for (final m in RegExp(r'\d{2,4}').allMatches(text))
      ParsedRow(type: type, value: m.group(0)!, score: '', raw: m.group(0)!, reasons: ['Đọc từ ảnh, hãy kiểm tra lại', 'Chưa có điểm']),
  ];
}

/// Friendly message for a failed recognition.
String describeOcrError(Object e) {
  final t = '$e'.toLowerCase();
  if (t.contains('memory')) return 'Ảnh quá lớn hoặc thiết bị không đủ bộ nhớ để đọc. Hãy chụp ảnh nhỏ hơn rồi thử lại.';
  if (t.contains('model') || t.contains('download')) return 'Công cụ đọc ảnh chưa sẵn sàng. Hãy kết nối mạng một lần để tải mô hình rồi thử lại, hoặc nhập tay.';
  return 'Không đọc được ảnh. Bạn có thể nhập tay.';
}
