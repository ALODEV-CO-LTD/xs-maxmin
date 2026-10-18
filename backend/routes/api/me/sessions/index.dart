import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET` - the caller's own signed-in devices (active sessions only).
/// `DELETE` - signs out every OTHER device (the current one stays).
Response onRequest(RequestContext context) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final db = context.read<Database>();

  return switch (context.request.method) {
    HttpMethod.get => Response.json(
        body: {
          'sessions': listSessions(db, auth.userId, currentSessionId: auth.sessionId),
        },
      ),
    HttpMethod.delete => Response.json(
        body: {
          'revoked': revokeAllSessions(
            db,
            auth.userId,
            by: auth.userId,
            exceptSessionId: auth.sessionId,
            ip: clientIp(context),
          ),
        },
      ),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}
