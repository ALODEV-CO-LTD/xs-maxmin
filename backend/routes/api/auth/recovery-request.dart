import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/database.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/recovery_requests.dart';
import 'package:sqlite3/sqlite3.dart';

/// "Mất mã khôi phục" (A06): a customer who lost both the password and the
/// recovery code asks the admin to help. Body `{username, note?}`; public.
///
/// The answer is ALWAYS the same `{ok: true}` whether or not the account exists
/// (or already has an open request), so this cannot be used to find out which
/// usernames exist. Unknown/admin names are stored as 'ignored' rows so the
/// per-IP limit (5 / hour) still counts them. Nothing is changed on the account
/// itself - an admin must approve first (routes/api/admin/recovery-requests).
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
  if (!fieldsAreStrings(body, ['username', 'note'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  final username = (body['username'] as String?)?.trim() ?? '';
  var note = (body['note'] as String?)?.trim() ?? '';
  if (username.isEmpty || username.length > 64) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên đăng nhập'});
  }
  if (note.length > 300) note = note.substring(0, 300);

  final db = context.read<Database>();
  final ip = clientIp(context);
  final now = DateTime.now().toUtc();

  final recent = db.select(
    'SELECT COUNT(*) AS n FROM recovery_requests WHERE ip = ? AND created_at > ?',
    [ip, now.subtract(const Duration(hours: 1)).toIso8601String()],
  ).first['n'] as int;
  if (recent >= maxRecoveryRequestsPerIpPerHour) return lockedResponse(600);

  final rows = db.select('SELECT id, role FROM users WHERE username = ?', [username]);
  final user = (rows.isEmpty || rows.first['role'] == 'admin') ? null : rows.first;
  var status = 'ignored';
  if (user != null) {
    expireRecoveryTickets(db);
    final open = db.select(
      "SELECT 1 FROM recovery_requests WHERE user_id = ? AND status IN ('pending', 'approved')",
      [user['id']],
    );
    if (open.isEmpty) status = 'pending';
  }
  db.execute(
    '''
    INSERT INTO recovery_requests (id, user_id, username, note, status, ip, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [newId(), user?['id'], username, note, status, ip, now.toIso8601String()],
  );
  if (status == 'pending') {
    logSecurityEvent(db, 'recovery_requested', userId: user!['id'] as String, username: username, ip: ip, detail: 'Khách gửi yêu cầu hỗ trợ khôi phục tài khoản');
  }
  return Response.json(body: {
    'ok': true,
    'message': 'Đã ghi nhận yêu cầu. Quản trị viên sẽ liên hệ xác minh bạn qua kênh hỗ trợ; khi được duyệt bạn sẽ nhận một mã hỗ trợ có hạn 24 giờ.',
  });
}
