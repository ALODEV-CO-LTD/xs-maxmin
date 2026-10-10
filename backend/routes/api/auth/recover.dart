import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Wrong tries allowed per IP (across ALL usernames) before it is slowed down.
/// Looser than the per-account+IP limit (5) so a shared office IP is not
/// locked by a few typos, but it still caps name-guessing from one address.
const _ipFreeAttempts = 20;

/// "Quên mật khẩu" (K08): username + mã khôi phục + new password -> sets the
/// new password, rotates the code (old one stops working), signs out EVERY
/// device of the account, and returns the NEW code once. Does not log the
/// caller in.
///
/// Anti-enumeration / anti-lockout: every failure (unknown name, admin, user
/// without a code, wrong code) takes the same path - one bcrypt, the same
/// 401 text, and the same counters - so a name cannot be probed by status or
/// timing. Counting is per account+IP (a stranger can't lock the owner out of
/// recovering from the owner's own IP) plus a per-IP ceiling across names; the
/// old global per-account lock (users.recovery_locked_until) is no longer used
/// here for exactly that reason. The code has ~80 bits of entropy, so
/// guessing across many IPs is not a practical attack.
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

  if (!fieldsAreStrings(body, ['username', 'recoveryCode', 'newPassword'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  final username = (body['username'] as String?)?.trim();
  final code = body['recoveryCode'] as String?;
  final newPassword = body['newPassword'] as String?;
  if (username == null || username.isEmpty || username.length > 64 || code == null || code.trim().isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Vui lòng nhập tên đăng nhập và mã khôi phục'},
    );
  }
  // Depends only on the input, so it says nothing about the account.
  final policyError = newPassword == null ? 'Vui lòng nhập mật khẩu mới' : validateNewPassword(newPassword);
  if (policyError != null || newPassword == null) {
    return Response.json(statusCode: 400, body: {'error': policyError});
  }

  const badCode = 'Tên đăng nhập hoặc mã khôi phục không đúng';
  final db = context.read<Database>();
  final ip = clientIp(context);
  final acctKey = 'recover:$username';
  const ipKey = '-recover-ip';

  final ipWait = lockedSecondsLeft(db, ipKey, ip);
  if (ipWait > 0) return lockedResponse(ipWait);
  final wait = lockedSecondsLeft(db, acctKey, ip);
  if (wait > 0) return lockedResponse(wait);

  final rows = db.select('SELECT * FROM users WHERE username = ?', [username]);
  // Admin accounts cannot use recovery: treated exactly like "no such user".
  final row = (rows.isEmpty || rows.first['role'] == 'admin') ? null : rows.first;
  final storedHash = row?['recovery_code_hash'] as String?;
  // One bcrypt whatever the case (dummy hash when there is nothing to check).
  final codeOk = BCrypt.checkpw(normalizeRecoveryCode(code), storedHash ?? dummyPasswordHash);
  if (row == null || storedHash == null || !codeOk) {
    final userId = row?['id'] as String?;
    final a = recordLoginFailure(db, acctKey, ip, userId: userId);
    final b = recordLoginFailure(db, ipKey, ip, freeAttempts: _ipFreeAttempts);
    final lock = a > b ? a : b;
    if (lock > 0) return lockedResponse(lock);
    return Response.json(statusCode: 401, body: {'error': badCode});
  }

  final id = row['id'] as String;
  if (row['status'] == 'locked') {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Tài khoản đã bị khoá. Vui lòng liên hệ quản trị viên.'},
    );
  }

  // Same distinctness rules as POST /api/me/password.
  final wipe = row['wipe_password_hash'] as String?;
  if (wipe != null && BCrypt.checkpw(newPassword, wipe)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu xoá dữ liệu'},
    );
  }

  db.execute(
    'UPDATE users SET password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(newPassword, BCrypt.gensalt()), id],
  );
  final newCode = rotateRecoveryCode(db, id);
  clearLoginFailures(db, acctKey, ip);
  // Whoever held the old password (possibly the reason for recovering) is
  // signed out on every device.
  revokeAllSessions(db, id, by: id, ip: ip);
  logSecurityEvent(db, 'password_recovered', userId: id, username: username, ip: ip, detail: 'Khôi phục mật khẩu bằng mã khôi phục; đã đăng xuất mọi thiết bị');
  return Response.json(body: {'reset': true, 'recoveryCode': newCode});
}
