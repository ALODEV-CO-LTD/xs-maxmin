import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/recovery_requests.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST {action: 'approve' | 'reject'}` on one recovery request (A06).
/// Approve (from pending, or again from approved/expired to re-issue) returns
/// `{ticket, expiresAt}` ONCE: the admin passes it to the verified customer,
/// who sets their own new password with it (POST /auth/recover-with-ticket).
/// Nothing on the account changes until the customer uses the ticket.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'users.recovery');
  if (denied != null) return denied;

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final action = body['action'];
  if (action != 'approve' && action != 'reject') {
    return Response.json(statusCode: 400, body: {'error': "action phải là 'approve' hoặc 'reject'"});
  }

  final db = context.read<Database>();
  expireRecoveryTickets(db);
  final rows = db.select(
    "SELECT r.*, u.role FROM recovery_requests r JOIN users u ON u.id = r.user_id WHERE r.id = ?",
    [id],
  );
  if (rows.isEmpty) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy yêu cầu'});
  final r = rows.first;
  final status = r['status'] as String;
  final ip = clientIp(context);
  final username = r['username'] as String;

  if (action == 'reject') {
    if (status != 'pending' && status != 'approved') {
      return Response.json(statusCode: 409, body: {'error': 'Yêu cầu này đã được xử lý'});
    }
    db.execute(
      "UPDATE recovery_requests SET status = 'rejected', handled_by = ?, handled_at = ?, ticket_hash = NULL WHERE id = ?",
      [auth.userId, DateTime.now().toUtc().toIso8601String(), id],
    );
    logSecurityEvent(db, 'recovery_request_rejected', userId: r['user_id'] as String?, username: username, ip: ip, detail: 'Admin từ chối yêu cầu khôi phục');
    return Response.json(body: {'status': 'rejected'});
  }

  if (status != 'pending' && status != 'approved' && status != 'expired') {
    return Response.json(statusCode: 409, body: {'error': 'Yêu cầu này đã được xử lý'});
  }
  final (ticket, expires) = issueRecoveryTicket(db, id, auth.userId);
  logSecurityEvent(db, 'recovery_request_approved', userId: r['user_id'] as String?, username: username, ip: ip, detail: 'Admin duyệt yêu cầu khôi phục và cấp mã hỗ trợ (hạn 24 giờ)');
  return Response.json(body: {
    'status': 'approved',
    'ticket': ticket,
    'expiresAt': expires.toIso8601String(),
  });
}
