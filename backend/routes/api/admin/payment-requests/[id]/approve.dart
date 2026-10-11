import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/package_plans.dart';
import 'package:server/src/payments.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Admin confirms the money arrived - grants the package (extend expiry,
/// add quota, log a `transactions` row) via `applyApprovedPackage`, exactly
/// as an instant purchase used to, then marks this request 'approved'.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'payments.manage');
  if (denied != null) return denied;

  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM payment_requests WHERE id = ?', [id]);
  if (rows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy yêu cầu'});
  }
  final request = rows.first;
  if (request['status'] != 'pending') {
    return Response.json(
      statusCode: 409,
      body: {'error': 'Yêu cầu này đã được xử lý trước đó'},
    );
  }

  // The package may have been hidden since the request was made, still grantable;
  // only a deleted one cannot be.
  final pkg = findPackage(db, request['package_type'] as String);
  if (pkg == null) {
    return Response.json(
      statusCode: 409,
      body: {'error': 'Gói này đã bị xoá khỏi danh mục - hãy từ chối yêu cầu hoặc tạo lại gói.'},
    );
  }
  applyApprovedPackage(
    db,
    request['user_id'] as String,
    pkg,
    request['amount'] as int,
  );

  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    "UPDATE payment_requests SET status = 'approved', decided_at = ?, decided_by = ? WHERE id = ?",
    [now, auth.userId, id],
  );

  logSecurityEvent(
    db,
    'payment_approved',
    userId: request['user_id'] as String,
    ip: clientIp(context),
    detail: 'Admin duyệt ${request['reference_code'] ?? id}: ${request['package_type']} - ${request['amount']} đ',
  );
  pushPaymentDecision(request['user_id'] as String, status: 'approved', reference: '${request['reference_code'] ?? ''}');
  return Response.json(body: {'ok': true});
}
