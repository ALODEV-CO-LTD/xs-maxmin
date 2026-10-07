import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/data_wipe.dart';
import 'package:server/src/database.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// User-initiated, transparent data wipe: the app must show a confirmation
/// warning before collecting the password for this call, and must show the
/// result afterward - this is never triggered implicitly from login.
/// Deletes what [wipeUserData] defines (entries, customers, syntax templates,
/// deletion schedules, call logs, support messages, transactions, pending
/// payment requests); account, friends and friend chat are untouched.
/// Wrong password -> 403 (never 401, which would log the user out); repeated
/// failures -> 429 (see reauth_limit.dart).
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

  final db = context.read<Database>();
  final userId = auth.userId;
  final ip = clientIp(context);
  final denied = checkReauthPassword(
    db,
    self,
    body['password'] as String?,
    action: 'Xoá dữ liệu',
    ip: ip,
    wrongMessage: 'Mật khẩu không đúng',
  );
  if (denied != null) return denied;

  final counts = wipeUserData(db, userId);
  // The password may have been typed by a stranger holding a stolen token:
  // keep only this session, every other device must log in again.
  revokeAllSessions(db, userId, by: userId, exceptSessionId: auth.sessionId, ip: ip);
  logSecurityEvent(db, 'data_wiped', userId: userId, ip: ip, detail: 'Người dùng tự xoá dữ liệu');

  return Response.json(body: {'ok': true, 'deleted': counts});
}
