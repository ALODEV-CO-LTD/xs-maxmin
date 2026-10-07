import 'package:dart_frog/dart_frog.dart';

import 'database.dart';
import 'security.dart';
import 'sessions.dart';

/// Reads the `Authorization: Bearer <token>` header (if present) and
/// provides the decoded [AuthTokenPayload] to downstream handlers.
/// Does NOT reject unauthenticated requests by itself - routes that need
/// a logged-in user call [requireAuth] / [requireAdmin] themselves.
Handler authProvider(Handler handler) {
  return handler.use(
    provider<AuthTokenPayload?>((context) {
      final header = context.request.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) return null;
      final token = header.substring('Bearer '.length);
      final payload = verifyToken(token);
      if (payload == null) return null;
      // Revoked device session => treated as not logged in (401 downstream).
      // Uses appDatabase directly: this provider runs before the Database
      // provider in routes/_middleware.dart is in scope.
      // Same for an account an admin locked or that no longer exists.
      if (!sessionIsActive(appDatabase, payload.userId, payload.sessionId, issuedAtSeconds: payload.issuedAt)) return null;
      return payload;
    }),
  );
}

/// Returns the authenticated payload or a 401 [Response] wrapped in the
/// left side via throwing - callers should check with [requireAuth].
AuthTokenPayload? requireAuth(RequestContext context) {
  return context.read<AuthTokenPayload?>();
}

Response unauthorized([String message = 'Chưa đăng nhập']) =>
    Response.json(statusCode: 401, body: {'error': message});

Response forbidden([String message = 'Không có quyền truy cập']) =>
    Response.json(statusCode: 403, body: {'error': message});
