import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';

/// Body limits (bytes) used by the routes.
const authBodyMaxBytes = 8 * 1024;
const smallBodyMaxBytes = 256 * 1024;

/// A chat message with a 25 MB image: base64 is 4/3 of the file, plus room for the text and the JSON envelope.
const messageBodyMaxBytes = 34 * 1024 * 1024;

/// Result of [readJsonBody]: either [body] (a JSON object) or the [error] response to return as is.
class JsonBodyResult {
  JsonBodyResult.ok(Map<String, dynamic> this.body) : error = null;
  JsonBodyResult.fail(Response this.error) : body = null;
  final Map<String, dynamic>? body;
  final Response? error;
}

Response payloadTooLarge() =>
    Response.json(statusCode: 413, body: {'error': 'Dữ liệu gửi lên quá lớn'});

/// Reads the request body as a JSON object, never holding more than [maxBytes] of it:
///  - a `Content-Length` above the limit is refused with 413 BEFORE any byte is read;
///  - a body without (or lying about) its length is counted while it streams and refused with 413 once over the limit;
///  - anything that is not a JSON object is a 400 `Body không hợp lệ`.
Future<JsonBodyResult> readJsonBody(RequestContext context, int maxBytes) async {
  final declared = int.tryParse(context.request.headers['content-length'] ?? '');
  if (declared != null && declared > maxBytes) return JsonBodyResult.fail(payloadTooLarge());

  final bytes = <int>[];
  try {
    await for (final chunk in context.request.bytes()) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) return JsonBodyResult.fail(payloadTooLarge());
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('not an object');
    return JsonBodyResult.ok(Map<String, dynamic>.from(decoded));
  } catch (_) {
    return JsonBodyResult.fail(Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'}));
  }
}

/// 400 response unless [value] is absent/null or a String of at most [max] characters.
bool isShortString(Object? value, int max) => value == null || (value is String && value.length <= max);

/// Text-field check for JSON bodies: every key of [maxLengths] that is present and non-null must be a String of at most
/// that many characters (after trimming). Returns a 400 response (never a 500 from a failed `as String?` cast), or null
/// when everything is fine.
Response? checkTextFields(Map<String, dynamic> body, Map<String, int> maxLengths) {
  for (final e in maxLengths.entries) {
    final v = body[e.key];
    if (v == null) continue;
    if (v is! String) return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
    if (v.trim().length > e.value) {
      return Response.json(statusCode: 400, body: {'error': 'Nội dung quá dài (tối đa ${e.value} ký tự)'});
    }
  }
  return null;
}

/// Generous caps for the free-text fields of an entry (the apps do not limit them; this only stops abuse).
const entryTextLimits = {
  'value': 2000,
  'note': 1000,
  'customerName': 100,
  'score': 200,
  'result': 200,
  'betType': 200,
  'station': 100,
  'entryDate': 40,
  'clientId': 64,
  'baseUpdatedAt': 64,
};
