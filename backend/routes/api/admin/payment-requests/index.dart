import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// All payment requests (default: only 'pending', matching what Admin's
/// approval queue needs) joined with the requesting user's name/username -
/// pass `?status=all` to see the full history instead.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final statusFilter = context.request.uri.queryParameters['status'];
  final db = context.read<Database>();
  final rows = statusFilter == 'all'
      ? db.select(
          '''
          SELECT pr.*, u.name AS user_name, u.username AS username
          FROM payment_requests pr JOIN users u ON u.id = pr.user_id
          ORDER BY pr.created_at DESC LIMIT 200
          ''',
        )
      : db.select(
          '''
          SELECT pr.*, u.name AS user_name, u.username AS username
          FROM payment_requests pr JOIN users u ON u.id = pr.user_id
          WHERE pr.status = 'pending'
          ORDER BY pr.created_at ASC LIMIT 200
          ''',
        );

  return Response.json(
    body: {
      'requests': [
        for (final r in rows)
          {
            'id': r['id'],
            'userName': r['user_name'],
            'username': r['username'],
            'packageType': r['package_type'],
            'amount': r['amount'],
            'status': r['status'],
            'createdAt': r['created_at'],
            'decidedAt': r['decided_at'],
          },
      ],
    },
  );
}
