import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/recovery_requests.dart';
import 'package:sqlite3/sqlite3.dart';

/// Recovery-request queue for Admin (A06). `?status=open` (default: pending +
/// approved) or `all`. Never returns a ticket - that is shown once, when approving.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'users.recovery');
  if (denied != null) return denied;

  final db = context.read<Database>();
  expireRecoveryTickets(db);
  final all = context.request.uri.queryParameters['status'] == 'all';
  final rows = db.select(
    '''
    SELECT r.*, u.name AS user_name, u.package_type, u.package_expires_at, u.created_at AS registered_at,
           u.status AS account_status
    FROM recovery_requests r JOIN users u ON u.id = r.user_id
    ${all ? '' : "WHERE r.status IN ('pending', 'approved')"}
    ORDER BY (r.status = 'pending') DESC, r.created_at DESC
    LIMIT 200
    ''',
  );
  final pending = db.select("SELECT COUNT(*) AS n FROM recovery_requests WHERE status = 'pending'").first['n'];
  return Response.json(body: {
    'pending': pending,
    'requests': [
      for (final r in rows)
        {
          'id': r['id'],
          'userId': r['user_id'],
          'username': r['username'],
          'name': r['user_name'],
          'note': r['note'] ?? '',
          'status': r['status'],
          'ip': r['ip'],
          'createdAt': r['created_at'],
          'handledAt': r['handled_at'],
          'ticketExpiresAt': r['ticket_expires_at'],
          'completedAt': r['completed_at'],
          'packageType': r['package_type'],
          'packageExpiresAt': r['package_expires_at'],
          'registeredAt': r['registered_at'],
          'accountLocked': r['account_status'] == 'locked',
        },
    ],
  });
}
