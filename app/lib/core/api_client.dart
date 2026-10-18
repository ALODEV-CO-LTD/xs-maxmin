import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'config.dart';

/// Error from the backend. [message] is already a user-facing Vietnamese string (`{error: "..."}`); [status] 0 means
/// the server could not be reached. [data] is the parsed error body (e.g. a 409 payload).
class ApiError implements Exception {
  ApiError(this.status, this.message, [this.data]);
  final int status;
  final String message;
  final Map<String, dynamic>? data;
  @override
  String toString() => message;
}

/// Endpoints that ask the signed-in user to retype a password: a 401 there only means "wrong password", it must not
/// sign the user out (the same rule as frontend/src/api.js).
const _reauthPaths = {
  '/me/password',
  '/me/second-password',
  '/me/wipe-password',
  '/me/delete-data',
  '/me/recovery-code',
  '/me/verify-password',
};

bool _isReauth(String path, String method) {
  final p = path.split('?').first;
  if (p.startsWith('/auth/')) return true;
  if (p == '/me' && method != 'GET') return true;
  return _reauthPaths.contains(p);
}

/// Thin wrapper around the MAMBA REST API (same conventions as frontend/src/api.js): bearer token, JSON in and out,
/// [ApiError] on any non-2xx answer, and the session is cleared on a 401.
class ApiClient {
  ApiClient(this.auth, {http.Client? client}) : _http = client ?? http.Client();
  final AuthStore auth;
  final http.Client _http;

  Map<String, String> _headers({bool json = false}) => {
        if (json) 'content-type': 'application/json',
        if (auth.token != null) 'authorization': 'Bearer ${auth.token}',
      };

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('${AppConfig.api}$path');
    final req = http.Request(method, uri)..headers.addAll(_headers(json: body != null));
    if (body != null) req.body = body is String ? body : jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    } on Object {
      throw ApiError(0, 'Không thể kết nối tới máy chủ');
    }
    dynamic data;
    final text = utf8.decode(res.bodyBytes);
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = null;
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401 && !_isReauth(path, method)) auth.clear();
      final msg = data is Map && data['error'] is String ? data['error'] as String : statusFallbackMessage(res.statusCode);
      throw ApiError(res.statusCode, msg, data is Map<String, dynamic> ? data : null);
    }
    return data;
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? <String, dynamic>{});
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body ?? <String, dynamic>{});
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body ?? <String, dynamic>{});
  Future<dynamic> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  /// Authenticated binary download (chat attachments).
  Future<Uint8List> blob(String path) async {
    http.Response res;
    try {
      res = await _http.get(Uri.parse('${AppConfig.api}$path'), headers: _headers());
    } on Object {
      throw ApiError(0, 'Không thể kết nối tới máy chủ');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) auth.clear();
      throw ApiError(res.statusCode, statusFallbackMessage(res.statusCode));
    }
    return res.bodyBytes;
  }
}

/// Vietnamese text for responses without our JSON body (e.g. nginx answering 413/429 before the backend).
String statusFallbackMessage(int status) {
  if (status == 413) return 'Dữ liệu gửi lên quá lớn';
  if (status == 429) return 'Bạn thao tác quá nhanh, vui lòng thử lại sau ít phút';
  return 'Lỗi máy chủ ($status)';
}
