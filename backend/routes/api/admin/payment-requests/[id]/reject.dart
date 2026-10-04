import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Admin didn't receive the money (or it doesn't match) - marks the
/// request 'rejected'. Nothing was ever applied to the user's package/
/// quota while it sat pending, so there's nothing to undo here.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final db = context.read<Database>();
  final rows = db.select('SELECT status FROM payment_requests WHERE id = ?', [id]);
  if (rows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy yêu cầu'});
  }
  if (rows.first['status'] != 'pending') {
    return Response.json(
      statusCode: 409,
      body: {'error': 'Yêu cầu này đã được xử lý trước đó'},
    );
  }

  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    "UPDATE payment_requests SET status = 'rejected', decided_at = ?, decided_by = ? WHERE id = ?",
    [now, auth.userId, id],
  );

  return Response.json(body: {'ok': true});
}
