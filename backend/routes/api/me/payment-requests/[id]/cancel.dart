import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// The user withdraws their own still-pending request (e.g. picked the wrong
/// package). Stored as status 'rejected' + cancelled = 1; only 'pending'
/// requests of the caller can be withdrawn.
Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM payment_requests WHERE id = ? AND user_id = ?', [id, auth.userId]);
  if (rows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy yêu cầu'});
  }
  if (rows.first['status'] != 'pending') {
    return Response.json(statusCode: 409, body: {'error': 'Yêu cầu này đã được xử lý nên không huỷ được'});
  }
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    "UPDATE payment_requests SET status = 'rejected', cancelled = 1, decided_at = ?, reject_reason = 'Người dùng tự huỷ' WHERE id = ? AND status = 'pending'",
    [now, id],
  );
  logSecurityEvent(db, 'payment_cancelled', userId: auth.userId, ip: clientIp(context), detail: 'Người dùng huỷ ${rows.first['reference_code'] ?? id}');
  return Response.json(body: {'ok': true});
}
