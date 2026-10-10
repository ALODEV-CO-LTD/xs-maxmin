import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:server/src/recovery_requests.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

const _ipFreeAttempts = 20;

/// Finishes an admin-approved recovery (A06). Body `{username, ticket,
/// newPassword}`: the customer sets their OWN new password with the one-time
/// ticket the admin gave them, so the admin never knows it. On success the
/// ticket is spent, the recovery code is rotated (new one returned once), every
/// device is signed out and every login/re-auth throttle on the account is
/// cleared. Failures (unknown name, no approved request, expired, wrong
/// ticket) share one 401 text and one bcrypt, and are counted per account+IP
/// and per IP, exactly like /auth/recover.
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
  if (!fieldsAreStrings(body, ['username', 'ticket', 'newPassword'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  final username = (body['username'] as String?)?.trim() ?? '';
  final ticket = body['ticket'] as String? ?? '';
  final newPassword = body['newPassword'] as String?;
  if (username.isEmpty || username.length > 64 || ticket.trim().isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên đăng nhập và mã hỗ trợ'});
  }
  final policyError = newPassword == null ? 'Vui lòng nhập mật khẩu mới' : validateNewPassword(newPassword);
  if (policyError != null || newPassword == null) {
    return Response.json(statusCode: 400, body: {'error': policyError});
  }

  const bad = 'Tên đăng nhập hoặc mã hỗ trợ không đúng hoặc đã hết hạn';
  final db = context.read<Database>();
  final ip = clientIp(context);
  final acctKey = 'ticket:$username';
  const ipKey = '-ticket-ip';

  final ipWait = lockedSecondsLeft(db, ipKey, ip);
  if (ipWait > 0) return lockedResponse(ipWait);
  final wait = lockedSecondsLeft(db, acctKey, ip);
  if (wait > 0) return lockedResponse(wait);

  expireRecoveryTickets(db);
  final reqs = db.select(
    '''
    SELECT r.id AS rid, r.ticket_hash, u.* FROM recovery_requests r
    JOIN users u ON u.id = r.user_id
    WHERE u.username = ? AND u.role = 'user' AND r.status = 'approved'
    ORDER BY r.created_at DESC LIMIT 1
    ''',
    [username],
  );
  final row = reqs.isEmpty ? null : reqs.first;
  final ok = BCrypt.checkpw(normalizeRecoveryCode(ticket), (row?['ticket_hash'] as String?) ?? dummyPasswordHash);
  if (row == null || !ok) {
    final a = recordLoginFailure(db, acctKey, ip, userId: row?['id'] as String?);
    final b = recordLoginFailure(db, ipKey, ip, freeAttempts: _ipFreeAttempts);
    final lock = a > b ? a : b;
    if (lock > 0) return lockedResponse(lock);
    return Response.json(statusCode: 401, body: {'error': bad});
  }

  final id = row['id'] as String;
  if (row['status'] == 'locked') {
    return Response.json(statusCode: 403, body: {'error': 'Tài khoản đã bị khoá. Vui lòng liên hệ quản trị viên.'});
  }
  final wipe = row['wipe_password_hash'] as String?;
  if (wipe != null && BCrypt.checkpw(newPassword, wipe)) {
    return Response.json(statusCode: 400, body: {'error': 'Mật khẩu mới phải khác mật khẩu xoá dữ liệu'});
  }

  db.execute('UPDATE users SET password_hash = ? WHERE id = ?', [BCrypt.hashpw(newPassword, BCrypt.gensalt()), id]);
  final newCode = rotateRecoveryCode(db, id);
  db.execute(
    "UPDATE recovery_requests SET status = 'completed', completed_at = ?, ticket_hash = NULL WHERE id = ?",
    [DateTime.now().toUtc().toIso8601String(), row['rid']],
  );
  clearLoginFailures(db, acctKey, ip);
  db.execute('DELETE FROM login_attempts WHERE key LIKE ? ESCAPE ? OR key = ?', [
    '${username.toLowerCase().replaceAll('%', r'\%').replaceAll('_', r'\_')}|%',
    r'\',
    'reauth:$id|-',
  ]);
  revokeAllSessions(db, id, by: id, ip: ip);
  logSecurityEvent(db, 'password_recovered_ticket', userId: id, username: username, ip: ip, detail: 'Khách tự đặt lại mật khẩu bằng mã hỗ trợ do Admin duyệt; đã đăng xuất mọi thiết bị');
  return Response.json(body: {'reset': true, 'recoveryCode': newCode});
}
