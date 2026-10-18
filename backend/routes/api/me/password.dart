import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Lets the logged-in user change their primary (layer-1) login password.
///
/// A wrong current password is throttled like a failed login (5 free tries,
/// then 30s, 60s ... up to 15 min, 429) - a stolen token alone must not allow
/// guessing the password. The counter is per account (not per IP) because the
/// caller is already authenticated. On success every OTHER device is signed
/// out (this session stays), and a security event is written.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  if (!fieldsAreStrings(body, ['currentPassword', 'newPassword'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final db = context.read<Database>();
  final ip = clientIp(context);
  final throttleKey = 'chgpw:${auth.userId}';
  const throttleIp = '-'; // per account, whatever the IP
  final wait = lockedSecondsLeft(db, throttleKey, throttleIp);
  if (wait > 0) return lockedResponse(wait);

  final currentPassword = body['currentPassword'] as String?;
  if (currentPassword == null || !BCrypt.checkpw(currentPassword, self['password_hash'] as String)) {
    final lock = recordLoginFailure(db, throttleKey, throttleIp, userId: auth.userId);
    if (lock > 0) return lockedResponse(lock);
    return Response.json(statusCode: 401, body: {'error': 'Mật khẩu hiện tại không đúng'});
  }
  clearLoginFailures(db, throttleKey, throttleIp);

  final newPassword = body['newPassword'] as String?;
  final policyError = newPassword == null ? 'Vui lòng nhập mật khẩu mới' : validateNewPassword(newPassword);
  if (newPassword == null || policyError != null) {
    return Response.json(statusCode: 400, body: {'error': policyError});
  }
  if (newPassword == currentPassword) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu hiện tại'},
    );
  }
  final wipePasswordHash = self['wipe_password_hash'] as String?;
  if (wipePasswordHash != null && BCrypt.checkpw(newPassword, wipePasswordHash)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu mới phải khác mật khẩu xoá dữ liệu'},
    );
  }

  db.execute(
    'UPDATE users SET password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(newPassword, BCrypt.gensalt()), auth.userId],
  );
  // Sign out every other device; keep the one the user is on right now.
  final others = revokeAllSessions(db, auth.userId, by: auth.userId, exceptSessionId: auth.sessionId, ip: ip);
  logSecurityEvent(db, 'password_changed', userId: auth.userId, ip: ip, detail: 'Đổi mật khẩu; đăng xuất $others thiết bị khác');
  return Response.json(body: {'changed': true});
}
