import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/data_wipe.dart';
import 'package:server/src/database.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Only reachable with a [wipeToken] from a login attempt that matched the
/// account's wipe-password (see routes/api/auth/login.dart). The Flutter
/// client is required to show the user an explicit "this will permanently
/// delete your data - confirm?" dialog before it ever calls this endpoint;
/// nothing here runs implicitly or silently. Deletes data_entries,
/// the account's data (see wipeUserData) and returns a plain result -
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

  final db = context.read<Database>();
  // Invalid/expired tokens count as failed attempts (per IP) so the endpoint
  // can't be hammered; a lock only delays, it never deletes anything.
  final ip = clientIp(context);
  final wait = lockedSecondsLeft(db, '-confirm-wipe', ip);
  if (wait > 0) return lockedResponse(wait);

  final userId = verifyPendingWipeToken(wipeToken);
  if (userId == null) {
    final lock = recordLoginFailure(db, '-confirm-wipe', ip);
    if (lock > 0) return lockedResponse(lock);
    return Response.json(
      statusCode: 401,
      body: {'error': 'Yêu cầu đã hết hạn, vui lòng thử đăng nhập lại'},
    );
  }

  wipeUserData(db, userId); // same scope as POST /me/delete-data
  // The wipe-password may have been typed by a stranger: sign out every device.
  revokeAllSessions(db, userId, by: userId, ip: ip);
  logSecurityEvent(db, 'data_wiped', userId: userId, ip: ip, detail: 'Xoá dữ liệu bằng mật khẩu xoá (đăng nhập)');

  return Response.json(body: {'ok': true});
}
