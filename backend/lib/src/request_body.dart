import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';

/// Body limits (bytes) used by the routes.
const authBodyMaxBytes = 8 * 1024;
const smallBodyMaxBytes = 256 * 1024;

/// A chat message with a 5 MB image: base64 is 4/3 of the file, plus room for the text and the JSON envelope.
const messageBodyMaxBytes = 7 * 1024 * 1024 + 512 * 1024;

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
