import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/database.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
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

  final db = context.read<Database>();
  // Wrong password -> 403 (not 401: that would log the user out) and, after
  // repeated failures, 429 with a growing lock.
  final denied = checkReauthPassword(
    db,
    self,
    body['currentPassword'] as String?,
    action: 'Đặt mật khẩu lớp hai',
    ip: clientIp(context),
  );
  if (denied != null) return denied;
  final secondPassword = body['secondPassword'] as String?;

  final secondError = secondPassword == null ? 'Vui lòng nhập mật khẩu lớp hai' : validateNewPassword(secondPassword);
  if (secondPassword == null || secondError != null) {
    return Response.json(statusCode: 400, body: {'error': secondError});
  }

  final wipeHash = self['wipe_password_hash'] as String?;
  if (wipeHash != null && BCrypt.checkpw(secondPassword, wipeHash)) {
    // Otherwise typing the second password at login would start the
    // emergency wipe flow and the real second layer could never be reached.
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu lớp hai phải khác mật khẩu xoá dữ liệu'},
    );
  }

  db.execute(
    'UPDATE users SET second_password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(secondPassword, BCrypt.gensalt()), auth.userId],
  );
  return Response.json(body: {'enabled': true});
}
