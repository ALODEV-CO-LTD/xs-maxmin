import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/database.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';

/// Only reachable with a [wipeToken] from a login attempt that matched the
/// account's wipe-password (see routes/api/auth/login.dart). The Flutter
/// client is required to show the user an explicit "this will permanently
/// delete your data - confirm?" dialog before it ever calls this endpoint;
/// nothing here runs implicitly or silently. Deletes data_entries,
/// messages and transactions for the account and returns a plain result -
/// it never issues a session token, so this never logs anyone in.
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

  final wipeToken = body['wipeToken'] as String?;
  if (wipeToken == null) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu thông tin xác thực'});
  }

  final userId = verifyPendingWipeToken(wipeToken);
  if (userId == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Yêu cầu đã hết hạn, vui lòng thử đăng nhập lại'},
    );
  }

  final db = context.read<Database>();
  db.execute('DELETE FROM data_entries WHERE user_id = ?', [userId]);
  db.execute('DELETE FROM messages WHERE user_id = ?', [userId]);
  db.execute('DELETE FROM transactions WHERE user_id = ?', [userId]);
  db.execute('UPDATE users SET data_used = 0 WHERE id = ?', [userId]);

  return Response.json(body: {'ok': true});
}
