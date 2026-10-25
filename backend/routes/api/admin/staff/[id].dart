import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/admin_trash.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

import 'index.dart' show parsePermissions, staffJson;

/// One staff account - root Admin only (A07).
/// `PATCH {permissions?, name?, locked?, newPassword?}`; permission changes
/// apply on the very next request (they are read from the database each time),
/// locking or resetting the password also signs the staff member out everywhere.
/// `DELETE` removes the account.
/// The root Admin itself cannot be edited or removed through this route.
Future<Response> onRequest(RequestContext context, String id) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnlessRoot(context, auth);
  if (denied != null) return denied;
  final db = context.read<Database>();

  final rows = db.select(
    "SELECT * FROM users WHERE id = ? AND role = 'admin' AND staff_permissions IS NOT NULL",
    [id],
  );
  if (rows.isEmpty) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy tài khoản thứ cấp'});
  final username = rows.first['username'] as String;
  final ip = clientIp(context);

  if (context.request.method == HttpMethod.delete) {
    // payment_requests.decided_by and announcements.created_by reference users(id) without ON DELETE, so a staff
    // member with history could not be deleted (FK error => 500). Keep the history, drop only the reference.
    db.execute('BEGIN');
    try {
      trashAccount(db, id, staff: true, deletedBy: auth.userId);
      db.execute('UPDATE payment_requests SET decided_by = NULL WHERE decided_by = ?', [id]);
      db.execute('UPDATE announcements SET created_by = NULL WHERE created_by = ?', [id]);
      db.execute('DELETE FROM users WHERE id = ?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      return Response.json(statusCode: 409, body: {'error': 'Không xoá được tài khoản (còn dữ liệu liên quan)'});
    }
    logSecurityEvent(db, 'staff_deleted', userId: id, username: username, ip: ip, detail: 'Admin xoá tài khoản thứ cấp');
    return Response.json(body: {'deleted': true});
  }
  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  final perms = body.containsKey('permissions') ? parsePermissions(body['permissions']) : null;
  if (body.containsKey('permissions') && (perms == null || perms.isEmpty)) {
    return Response.json(statusCode: 400, body: {'error': 'Hãy chọn ít nhất một quyền hợp lệ'});
  }
  final name = (body['name'] as String?)?.trim();
  if (name != null && name.isEmpty) return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên hiển thị'});
  final newPassword = body['newPassword'] as String?;
  if (newPassword != null) {
    final pwError = validateNewPassword(newPassword);
    if (pwError != null) return Response.json(statusCode: 400, body: {'error': pwError});
  }
  final locked = body['locked'];

  var signOut = false;
  if (perms != null) {
    db.execute('UPDATE users SET staff_permissions = ? WHERE id = ?', [jsonEncode(perms), id]);
    logSecurityEvent(db, 'staff_permissions_changed', userId: id, username: username, ip: ip, detail: 'Admin đổi quyền (${perms.length} quyền)');
  }
  if (name != null) db.execute('UPDATE users SET name = ? WHERE id = ?', [name, id]);
  if (locked is bool) {
    db.execute('UPDATE users SET status = ? WHERE id = ?', [locked ? 'locked' : 'active', id]);
    logSecurityEvent(db, locked ? 'staff_locked' : 'staff_unlocked', userId: id, username: username, ip: ip);
    if (locked) signOut = true;
  }
  if (newPassword != null) {
    db.execute('UPDATE users SET password_hash = ? WHERE id = ?', [BCrypt.hashpw(newPassword, BCrypt.gensalt()), id]);
    logSecurityEvent(db, 'staff_password_reset', userId: id, username: username, ip: ip, detail: 'Admin đặt lại mật khẩu tài khoản thứ cấp');
    signOut = true;
  }
  if (signOut) revokeAllSessions(db, id, by: auth.userId, ip: ip);

  return Response.json(body: staffJson(db.select('SELECT * FROM users WHERE id = ?', [id]).first));
}
