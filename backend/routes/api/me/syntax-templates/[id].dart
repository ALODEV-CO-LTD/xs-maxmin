import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// DELETE: removes one of the caller's own syntax templates.
Response onRequest(RequestContext context, String id) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final db = context.read<Database>();
  db.execute('DELETE FROM customer_syntax_templates WHERE id = ? AND user_id = ?', [id, auth.userId]);
  return Response.json(body: {'ok': true});
}
