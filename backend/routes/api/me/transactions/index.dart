import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final rows = db.select(
    'SELECT * FROM transactions WHERE user_id = ? ORDER BY created_at DESC',
    [auth.userId],
  );
  return Response.json(
    body: {
      'transactions': [
        for (final r in rows)
          {
            'id': r['id'],
            'type': r['type'],
            'packageType': r['package_type'],
            'amount': r['amount'],
            'createdAt': r['created_at'],
          },
      ],
    },
  );
}
