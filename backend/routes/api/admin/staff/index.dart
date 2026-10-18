import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Staff (secondary Admin) accounts - root Admin only (A07).
///
/// `GET`  -> `{permissions: {key: label}, staff: [...]}`: the permission
///           catalogue to tick from, and every staff account.
/// `POST {name, username, password, permissions: [key]}` -> creates one.
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnlessRoot(context, auth);
  if (denied != null) return denied;
  final db = context.read<Database>();

  if (context.request.method == HttpMethod.get) {
    final rows = db.select(
      "SELECT * FROM users WHERE role = 'admin' AND staff_permissions IS NOT NULL ORDER BY created_at DESC",
    );
    return Response.json(body: {
      'permissions': adminPermissions,
      'staff': [for (final r in rows) staffJson(r)],
    });
  }
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final name = (body['name'] as String?)?.trim() ?? '';
  final username = (body['username'] as String?)?.trim() ?? '';
  final password = body['password'] as String? ?? '';
  final perms = parsePermissions(body['permissions']);
  if (name.isEmpty) return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên hiển thị'});
  if (username.length < 3) return Response.json(statusCode: 400, body: {'error': 'Tên đăng nhập phải có ít nhất 3 ký tự'});
  final pwError = validateNewPassword(password);
  if (pwError != null) return Response.json(statusCode: 400, body: {'error': pwError});
  if (perms == null || perms.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Hãy chọn ít nhất một quyền cho tài khoản này'});
  }
  if (db.select('SELECT 1 FROM users WHERE username = ?', [username]).isNotEmpty) {
    return Response.json(statusCode: 409, body: {'error': 'Tên đăng nhập đã được sử dụng'});
  }

  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    '''
    INSERT INTO users (id, name, username, password_hash, role, package_type, status, staff_permissions, created_at)
    VALUES (?, ?, ?, ?, 'admin', 'none', 'active', ?, ?)
    ''',
    [id, name, username, BCrypt.hashpw(password, BCrypt.gensalt()), jsonEncode(perms), now],
  );
  logSecurityEvent(db, 'staff_created', userId: id, username: username, ip: clientIp(context), detail: 'Admin tạo tài khoản thứ cấp (${perms.length} quyền)');
  return Response.json(statusCode: 201, body: staffJson(db.select('SELECT * FROM users WHERE id = ?', [id]).first));
}

/// Valid, de-duplicated permission keys, or null when the input is not a list of known keys.
List<String>? parsePermissions(Object? raw) {
  if (raw is! List) return null;
  final out = <String>[];
  for (final p in raw) {
    if (p is! String || !adminPermissions.containsKey(p)) return null;
    if (!out.contains(p)) out.add(p);
  }
  return out;
}

Map<String, dynamic> staffJson(Row r) => {
      'id': r['id'],
      'name': r['name'],
      'username': r['username'],
      'permissions': permissionsOf(r) ?? const <String>[],
      'locked': r['status'] == 'locked',
      'createdAt': r['created_at'],
    };
