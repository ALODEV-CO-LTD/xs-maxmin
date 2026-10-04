import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context, String friendId) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final db = context.read<Database>();
  db.execute(
    'DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
    [auth.userId, friendId, friendId, auth.userId],
  );
  return Response.json(body: {'ok': true});
}
