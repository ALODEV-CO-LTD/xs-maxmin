import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// User-initiated, transparent data wipe: the app must show a confirmation
/// warning before collecting the password for this call, and must show the
/// result afterward - this is never triggered implicitly from login.
/// Deletes the user's own data_entries, messages and transactions; the
/// account itself (and its package/subscription) is untouched.
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

  final password = body['password'] as String?;
  if (password == null || !BCrypt.checkpw(password, self['password_hash'] as String)) {
    return Response.json(statusCode: 401, body: {'error': 'Mật khẩu không đúng'});
  }

  final db = context.read<Database>();
  final userId = auth.userId;
  db.execute('DELETE FROM data_entries WHERE user_id = ?', [userId]);
  db.execute('DELETE FROM messages WHERE user_id = ?', [userId]);
  db.execute('DELETE FROM transactions WHERE user_id = ?', [userId]);
  db.execute('UPDATE users SET data_used = 0 WHERE id = ?', [userId]);

  return Response.json(body: {'ok': true});
}
