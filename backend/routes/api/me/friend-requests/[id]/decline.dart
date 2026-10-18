import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/friend_requests.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST /api/me/friend-requests/{id}/decline` - recipient only.
Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role == 'admin') return forbidden();
  return declineRequest(context.read<Database>(), auth.userId, id);
}
