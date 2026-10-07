import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/payments.dart';
import 'package:server/src/sessions.dart';
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
  var reason = '';
  try {
    final raw = await context.request.body();
    if (raw.isNotEmpty) reason = ((jsonDecode(raw) as Map<String, dynamic>)['reason'] as String? ?? '').trim();
  } catch (_) {}
  if (reason.length > 200) {
    return Response.json(statusCode: 400, body: {'error': 'Lý do tối đa 200 ký tự'});
  }
  final rows = db.select('SELECT * FROM payment_requests WHERE id = ?', [id]);
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
    "UPDATE payment_requests SET status = 'rejected', decided_at = ?, decided_by = ?, reject_reason = ? WHERE id = ?",
    [now, auth.userId, reason.isEmpty ? null : reason, id],
  );
  final row = rows.first;
  logSecurityEvent(
    db,
    'payment_rejected',
    userId: row['user_id'] as String,
    ip: clientIp(context),
    detail: 'Admin từ chối ${row['reference_code'] ?? id}${reason.isEmpty ? '' : ': $reason'}',
  );
  pushPaymentDecision(row['user_id'] as String,
      status: 'rejected', reason: reason.isEmpty ? null : reason, reference: '${row['reference_code'] ?? ''}');

  return Response.json(body: {'ok': true});
}
