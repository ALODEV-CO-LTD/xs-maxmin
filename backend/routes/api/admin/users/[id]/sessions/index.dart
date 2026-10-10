import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET` - admin view of one user's active device sessions.
/// `DELETE` - revokes all of that user's sessions (forces re-login).
Response onRequest(RequestContext context, String id) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'users.lock');
  if (denied != null) return denied;

  final db = context.read<Database>();
  final exists = db.select("SELECT 1 FROM users WHERE id = ? AND role = 'user'", [id]);
  if (exists.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy khách hàng'});
  }

  return switch (context.request.method) {
    HttpMethod.get => Response.json(body: {'sessions': listSessions(db, id)}),
    HttpMethod.delete => Response.json(
        body: {'revoked': revokeAllSessions(db, id, by: auth.userId, ip: clientIp(context))},
      ),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}
