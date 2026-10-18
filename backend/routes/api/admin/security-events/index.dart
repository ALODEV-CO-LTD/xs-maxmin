import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET ?limit=100` - most recent security events (failed logins, lockouts,
/// session revocations, data wipes), newest first. Contains no passwords or
/// tokens - see sessions.dart `logSecurityEvent`.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final limit = (int.tryParse(context.request.uri.queryParameters['limit'] ?? '') ?? 100).clamp(1, 500);
  final db = context.read<Database>();
  final rows = db.select(
    'SELECT * FROM security_events ORDER BY created_at DESC LIMIT ?',
    [limit],
  );
  return Response.json(
    body: {
      'events': [
        for (final r in rows)
          {
            'id': r['id'],
            'type': r['type'],
            'userId': r['user_id'],
            'username': r['username'],
            'ip': r['ip'],
            'detail': r['detail'],
            'createdAt': r['created_at'],
          },
      ],
    },
  );
}
