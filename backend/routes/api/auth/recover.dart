import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:sqlite3/sqlite3.dart';

/// "Quên mật khẩu" (K08): username + mã khôi phục + new password -> sets the
/// new password and rotates the code (old one stops working), returning the
/// NEW code once. Does not log the caller in. Wrong codes are counted and the
/// account is locked from recovery for a while after too many failures.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final username = (body['username'] as String?)?.trim();
  final code = body['recoveryCode'] as String?;
  final newPassword = body['newPassword'] as String?;
  if (username == null || username.isEmpty || code == null || code.trim().isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Vui lòng nhập tên đăng nhập và mã khôi phục'},
    );
  }
  if (newPassword == null || newPassword.length < 6) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải có ít nhất 6 ký tự'},
    );
  }

  const badCode = 'Tên đăng nhập hoặc mã khôi phục không đúng';
  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM users WHERE username = ?', [username]);
  // Same answer for unknown user / no code / wrong code so usernames can't be probed.
  if (rows.isEmpty || rows.first['role'] == 'admin') {
    return Response.json(statusCode: 401, body: {'error': badCode});
  }
  final row = rows.first;
  final id = row['id'] as String;

  final locked = recoveryLockMinutesLeft(row);
  if (locked > 0) {
    return Response.json(
      statusCode: 429,
      body: {'error': 'Nhập sai quá nhiều lần. Vui lòng thử lại sau $locked phút.'},
    );
  }
  if (!checkRecoveryCode(db, row, code)) {
    return Response.json(statusCode: 401, body: {'error': badCode});
  }
  if (row['status'] == 'locked') {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Tài khoản đã bị khoá. Vui lòng liên hệ quản trị viên.'},
    );
  }

  // Same distinctness rules as POST /api/me/password.
  final second = row['second_password_hash'] as String?;
  final wipe = row['wipe_password_hash'] as String?;
  if ((second != null && BCrypt.checkpw(newPassword, second)) ||
      (wipe != null && BCrypt.checkpw(newPassword, wipe))) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu lớp hai và mật khẩu xoá dữ liệu'},
    );
  }

  db.execute(
    'UPDATE users SET password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(newPassword, BCrypt.gensalt()), id],
  );
  final newCode = rotateRecoveryCode(db, id);
  return Response.json(body: {'reset': true, 'recoveryCode': newCode});
}
