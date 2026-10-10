import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET` - admin detail view for one subscriber. Deliberately returns the
/// same registration-only shape as the list endpoint - never data_entries.
///
/// `PATCH` body `{"locked": true|false}` - locks/unlocks the account
/// (blocks/allows login, see `routes/api/auth/login.dart`). Stored in the
/// existing `users.status` column ('locked' vs 'active'), which previously
/// had no reader/writer anywhere in the app.
///
/// `PATCH` body `{"newPassword": "..."}` - resets the account's login
/// password. The old password is never recoverable (only its bcrypt hash
/// is stored), so this is the only way admin can give a customer a working
/// password again; it's shown to admin once, right after they set it,
/// since the client already knows the plaintext it just typed.
///
/// Account-recovery support (A06). Setting `newPassword` also (a) signs the
/// account out everywhere, (b) clears every login / re-auth / recovery throttle
/// so the person can actually get back in, and (c) issues a NEW recovery code
/// (the old one may be exactly what leaked) - returned once as `recoveryCode`.
/// `{"reissueRecoveryCode": true}` does only (c) (+ clears the recovery lock) and
/// `{"clearLockouts": true}` only (b), for "I am locked out" tickets.
///
/// `DELETE` - permanently removes the account. `data_entries`,
/// `transactions`, `messages` and `customer_codes` all reference
/// `users(id) ON DELETE CASCADE`, so this also removes that user's own
/// data (the same data admin was never allowed to *read* - deleting it as
/// part of removing the account entirely is a different thing from
/// browsing it).
Future<Response> onRequest(RequestContext context, String id) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();
  // Per-method permissions (A07): viewing, locking, recovery support and
  // deleting are separate rights a staff account may or may not hold.
  final needed = switch (context.request.method) {
    HttpMethod.get => 'users.view',
    HttpMethod.delete => 'users.delete',
    _ => null, // PATCH: decided by the fields below
  };
  if (needed != null) {
    final denied = denyUnless(context, auth, needed);
    if (denied != null) return denied;
  }

  return switch (context.request.method) {
    HttpMethod.get => _get(context, id),
    HttpMethod.patch => _patch(context, id),
    HttpMethod.delete => _delete(context, id),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _get(RequestContext context, String id) {
  final db = context.read<Database>();
  final rows = db.select("SELECT * FROM users WHERE id = ? AND role = 'user'", [
    id,
  ]);
  if (rows.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Không tìm thấy khách hàng'},
    );
  }
  return Response.json(body: adminSubscriberJson(rows.first));
}

Future<Response> _patch(RequestContext context, String id) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final locked = body['locked'];
  final newPassword = body['newPassword'];
  final reissueCode = body['reissueRecoveryCode'] == true;
  final clearLockouts = body['clearLockouts'] == true;

  if (locked is! bool &&
      !reissueCode &&
      !clearLockouts &&
      (newPassword is! String || newPassword.trim().isEmpty)) {
    return Response.json(
      statusCode: 400,
      body: {'error': "Thiếu trường 'locked', 'newPassword', 'reissueRecoveryCode' hoặc 'clearLockouts'"},
    );
  }

  final db = context.read<Database>();
  final target = db.select(
    "SELECT * FROM users WHERE id = ? AND role = 'user'",
    [id],
  );
  if (target.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Không tìm thấy khách hàng'},
    );
  }

  final hasNewPassword = newPassword is String && newPassword.trim().isNotEmpty;
  if (locked is bool) {
    final denied = denyUnless(context, requireAuth(context)!, 'users.lock');
    if (denied != null) return denied;
  }
  if (hasNewPassword || reissueCode || clearLockouts) {
    final denied = denyUnless(context, requireAuth(context)!, 'users.recovery');
    if (denied != null) return denied;
  }
  // Validate before changing anything, so a bad password does not leave a
  // half-applied lock/unlock behind.
  if (newPassword is String && hasNewPassword) {
    final problem = validateNewPassword(newPassword.trim());
    if (problem != null) return Response.json(statusCode: 400, body: {'error': problem});
  }

  final ip = clientIp(context);
  final adminId = requireAuth(context)!.userId;
  final username = target.first['username'] as String;

  if (locked is bool) {
    db.execute('UPDATE users SET status = ? WHERE id = ?', [
      locked ? 'locked' : 'active',
      id,
    ]);
    if (locked) {
      // A locked account must not keep working: sign out every device now
      // (the auth middleware also rejects locked accounts on each request).
      revokeAllSessions(db, id, by: adminId, ip: ip);
    }
    logSecurityEvent(db, locked ? 'account_locked' : 'account_unlocked',
        userId: id,
        username: username,
        ip: ip,
        detail: locked ? 'Admin khoá tài khoản; đã đăng xuất mọi thiết bị' : 'Admin mở khoá tài khoản');
  }

  if (newPassword is String && hasNewPassword) {
    db.execute('UPDATE users SET password_hash = ? WHERE id = ?', [
      BCrypt.hashpw(newPassword.trim(), BCrypt.gensalt()),
      id,
    ]);
    // Whoever knew the old password is signed out everywhere. The event never
    // contains the new password.
    revokeAllSessions(db, id, by: adminId, ip: ip);
    logSecurityEvent(db, 'admin_password_reset',
        userId: id, username: username, ip: ip, detail: 'Admin đặt lại mật khẩu; đã đăng xuất mọi thiết bị');
  }

  String? newRecoveryCode;
  if ((newPassword is String && hasNewPassword) || reissueCode) {
    newRecoveryCode = rotateRecoveryCode(db, id);
    logSecurityEvent(db, 'admin_recovery_code_issued',
        userId: id, username: username, ip: ip, detail: 'Admin cấp lại mã khôi phục (mã cũ vô hiệu)');
  }
  if ((newPassword is String && hasNewPassword) || clearLockouts) {
    _clearLockouts(db, id, username);
    logSecurityEvent(db, 'admin_lockouts_cleared',
        userId: id, username: username, ip: ip, detail: 'Admin gỡ khoá đăng nhập/xác thực/khôi phục');
  }

  final updated = db.select('SELECT * FROM users WHERE id = ?', [id]);
  return Response.json(body: {
    ...adminSubscriberJson(updated.first),
    if (newRecoveryCode != null) 'recoveryCode': newRecoveryCode,
  });
}

/// Forget every throttle that could keep the person out: wrong-password locks
/// for their username (any IP), the re-auth limiter and the recovery-code lock.
void _clearLockouts(Database db, String userId, String username) {
  db.execute('DELETE FROM login_attempts WHERE key LIKE ? ESCAPE ? OR key = ?', [
    '${username.toLowerCase().replaceAll('%', r'\%').replaceAll('_', r'\_')}|%',
    r'\',
    'reauth:$userId|-',
  ]);
  db.execute(
    'UPDATE users SET recovery_failed_attempts = 0, recovery_locked_until = NULL WHERE id = ?',
    [userId],
  );
}

Response _delete(RequestContext context, String id) {
  final db = context.read<Database>();
  final target = db.select(
    "SELECT * FROM users WHERE id = ? AND role = 'user'",
    [id],
  );
  if (target.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Không tìm thấy khách hàng'},
    );
  }
  db.execute('DELETE FROM users WHERE id = ?', [id]);
  return Response.json(body: {'deleted': true});
}
