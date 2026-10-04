import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
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

  if (locked is! bool && (newPassword is! String || newPassword.trim().isEmpty)) {
    return Response.json(
      statusCode: 400,
      body: {'error': "Thiếu trường 'locked' (true/false) hoặc 'newPassword'"},
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

  if (locked is bool) {
    db.execute('UPDATE users SET status = ? WHERE id = ?', [
      locked ? 'locked' : 'active',
      id,
    ]);
  }

  if (newPassword is String && newPassword.trim().isNotEmpty) {
    if (newPassword.trim().length < 4) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Mật khẩu mới cần ít nhất 4 ký tự'},
      );
    }
    db.execute('UPDATE users SET password_hash = ? WHERE id = ?', [
      BCrypt.hashpw(newPassword.trim(), BCrypt.gensalt()),
      id,
    ]);
  }

  final updated = db.select('SELECT * FROM users WHERE id = ?', [id]);
  return Response.json(body: adminSubscriberJson(updated.first));
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
