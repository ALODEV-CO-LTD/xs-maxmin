import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `DELETE` - admin revokes one session of user `id`.
Response onRequest(RequestContext context, String id, String sid) {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final db = context.read<Database>();
  final ok = revokeSession(db, id, sid, by: auth.userId, ip: clientIp(context));
  if (!ok) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy phiên đăng nhập'});
  }
  return Response.json(body: {'revoked': true});
}
