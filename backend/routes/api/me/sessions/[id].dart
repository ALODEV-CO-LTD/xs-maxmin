import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `DELETE` - remote sign-out of one of the caller's own devices. `id` may be
/// the literal `current` to sign out this very device (logout).
Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final sessionId = id == 'current' ? auth.sessionId : id;
  if (sessionId == null) {
    // Legacy token with no session row: nothing server-side to revoke.
    return Response.json(body: {'revoked': false});
  }
  final db = context.read<Database>();
  final ok = revokeSession(db, auth.userId, sessionId, by: auth.userId, ip: clientIp(context));
  if (!ok) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy phiên đăng nhập'});
  }
  return Response.json(body: {'revoked': true});
}
