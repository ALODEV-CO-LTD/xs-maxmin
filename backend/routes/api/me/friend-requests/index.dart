import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/friend_requests.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/me/friend-requests` -> pending `{incoming, outgoing}`, newest first, max 100 each.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role == 'admin') return forbidden();
  return Response.json(body: listRequests(context.read<Database>(), auth.userId));
}
