import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  db.execute('DELETE FROM customer_codes WHERE id = ? AND user_id = ?', [id, auth.userId]);
  return Response.json(body: {'ok': true});
}
