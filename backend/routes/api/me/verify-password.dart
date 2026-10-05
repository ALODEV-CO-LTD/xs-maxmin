import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/user_repo.dart';

/// `POST` body `{"password": "..."}` - used by the client's auto-lock screen
/// (K09/K40): checks the caller's login password OR second-layer password
/// without issuing a new token. Wrong password answers 403 (not 401) on
/// purpose so the client does not treat it as an expired session and log out.
/// Failures are throttled per user in memory.
final _failures = <String, List<DateTime>>{};
const _maxFailures = 5;
const _window = Duration(minutes: 5);

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final password = body['password'] as String?;
  if (password == null || password.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập mật khẩu'});
  }

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final now = DateTime.now();
  final recent = (_failures[auth.userId] ?? []).where((t) => now.difference(t) < _window).toList();
  if (recent.length >= _maxFailures) {
    _failures[auth.userId] = recent;
    return Response.json(
      statusCode: 429,
      body: {'error': 'Nhập sai quá nhiều lần. Vui lòng thử lại sau ít phút.'},
    );
  }

  final second = self['second_password_hash'] as String?;
  final ok = BCrypt.checkpw(password, self['password_hash'] as String) ||
      (second != null && BCrypt.checkpw(password, second));
  if (!ok) {
    _failures[auth.userId] = [...recent, now];
    return Response.json(statusCode: 403, body: {'error': 'Mật khẩu không đúng'});
  }
  _failures.remove(auth.userId);
  return Response.json(body: {'ok': true});
}
