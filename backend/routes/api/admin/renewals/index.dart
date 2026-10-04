import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// System-wide renewal/purchase history, joined with subscriber name for
/// display. Only touches `transactions`, never `data_entries`.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final db = context.read<Database>();
  final rows = db.select('''
    SELECT t.*, u.name AS user_name
    FROM transactions t
    JOIN users u ON u.id = t.user_id
    ORDER BY t.created_at DESC
    LIMIT 200
  ''');

  return Response.json(
    body: {
      'renewals': [
        for (final r in rows)
          {
            'id': r['id'],
            'userName': r['user_name'],
            'avatar': initials(r['user_name'] as String),
            'type': r['type'],
            'packageType': r['package_type'],
            'amount': r['amount'],
            'createdAt': r['created_at'],
          },
      ],
    },
  );
}
