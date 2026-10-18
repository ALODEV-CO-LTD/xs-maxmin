import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST` body `{"currentPassword": "..."}` - creates the mã khôi phục for an
/// account that has none yet (older accounts) or replaces the existing one
/// (the old code stops working). Returns the new code ONCE; only its hash is
/// stored, so it can never be shown again - and never to an admin. Admin
/// accounts are not covered (they have no self-service recovery).
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
  if (self['role'] == 'admin') {
    return Response.json(statusCode: 403, body: {'error': 'Tài khoản quản trị không dùng mã khôi phục'});
  }

  final currentPassword = body['currentPassword'] as String?;
  if (currentPassword == null || !BCrypt.checkpw(currentPassword, self['password_hash'] as String)) {
    return Response.json(statusCode: 401, body: {'error': 'Mật khẩu hiện tại không đúng'});
  }

  final db = context.read<Database>();
  return Response.json(body: {'recoveryCode': rotateRecoveryCode(db, auth.userId)});
}
