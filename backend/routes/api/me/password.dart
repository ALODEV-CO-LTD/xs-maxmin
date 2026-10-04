import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Lets the logged-in user change their primary (layer-1) login password.
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

  final newPassword = body['newPassword'] as String?;
  if (newPassword == null || newPassword.length < 6) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải có ít nhất 6 ký tự'},
    );
  }
  if (newPassword == currentPassword) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu hiện tại'},
    );
  }
  final secondPasswordHash = self['second_password_hash'] as String?;
  if (secondPasswordHash != null && BCrypt.checkpw(newPassword, secondPasswordHash)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu lớp hai'},
    );
  }
  final wipePasswordHash = self['wipe_password_hash'] as String?;
  if (wipePasswordHash != null && BCrypt.checkpw(newPassword, wipePasswordHash)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu xoá dữ liệu'},
    );
  }

  final db = context.read<Database>();
  db.execute(
    'UPDATE users SET password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(newPassword, BCrypt.gensalt()), auth.userId],
  );
  return Response.json(body: {'changed': true});
}
