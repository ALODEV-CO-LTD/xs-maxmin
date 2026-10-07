import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/payments.dart';
import 'package:sqlite3/sqlite3.dart';

/// The calling user's own payment requests (pending + decided), newest
/// first - lets the client show "đang chờ duyệt" / "đã bị từ chối" state
/// on the purchase screen without an admin-only endpoint.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final rows = db.select(
    'SELECT * FROM payment_requests WHERE user_id = ? ORDER BY created_at DESC LIMIT 50',
    [auth.userId],
  );
  return Response.json(body: {'requests': [for (final r in rows) paymentJson(r)]});
}
