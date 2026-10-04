import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Lets the logged-in user set or change the second-layer login password on
/// their own account. Every account is required to have one (set at
/// registration) - this endpoint can only replace it, never remove it.
/// Requires re-entering the primary password as confirmation.
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

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final currentPassword = body['currentPassword'] as String?;
  if (currentPassword == null || !BCrypt.checkpw(currentPassword, self['password_hash'] as String)) {
    return Response.json(statusCode: 401, body: {'error': 'Mật khẩu hiện tại không đúng'});
  }

  final db = context.read<Database>();
  final secondPassword = body['secondPassword'] as String?;

  if (secondPassword == null || secondPassword.length < 4) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu lớp hai phải có ít nhất 4 ký tự'},
    );
  }
  if (BCrypt.checkpw(secondPassword, self['password_hash'] as String)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu lớp hai phải khác mật khẩu đăng nhập'},
    );
  }

  db.execute(
    'UPDATE users SET second_password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(secondPassword, BCrypt.gensalt()), auth.userId],
  );
  return Response.json(body: {'enabled': true});
}
