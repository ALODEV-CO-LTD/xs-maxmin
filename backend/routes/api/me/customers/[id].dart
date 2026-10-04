import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// Removes a customer from the roster - only removes them from the
/// picklist EntriesView reads; their historical data_entries rows (which
/// store the name as plain text, not a foreign key) are untouched and
/// still show up everywhere as before.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final existing = db.select(
    'SELECT id FROM customers WHERE id = ? AND user_id = ?',
    [id, auth.userId],
  );
  if (existing.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy khách hàng'});
  }

  db.execute('DELETE FROM customers WHERE id = ? AND user_id = ?', [id, auth.userId]);
  return Response.json(body: {'ok': true});
}
