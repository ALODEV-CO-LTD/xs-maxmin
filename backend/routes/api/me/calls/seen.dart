import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST /api/me/calls/seen` `{ friendId }` - the callee opened the
/// conversation, so that friend's missed calls stop counting as unseen.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final friendId = body['friendId'];
  if (friendId is! String || friendId.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu friendId'});
  }
  context.read<Database>().execute(
    'UPDATE call_logs SET callee_seen = 1 WHERE callee_id = ? AND caller_id = ? AND callee_seen = 0',
    [auth.userId, friendId],
  );
  return Response.json(body: {'ok': true});
}
