import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => _create(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  final rows = db.select(
    'SELECT * FROM customer_codes WHERE user_id = ? ORDER BY created_at DESC',
    [userId],
  );
  return Response.json(
    body: {
      'codes': [
        for (final r in rows) {'id': r['id'], 'code': r['code'], 'createdAt': r['created_at']},
      ],
    },
  );
}

/// Generates a new random numeric code (purely digits, [_codeLength] long)
/// unique across every user's codes, so it's safe to hand to someone else
/// on the platform without colliding with anyone else's.
Response _create(RequestContext context, String userId) {
  final db = context.read<Database>();
  final code = generateUniqueCustomerCode(db);
  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    'INSERT INTO customer_codes (id, user_id, code, created_at) VALUES (?, ?, ?, ?)',
    [id, userId, code, now],
  );
  return Response.json(statusCode: 201, body: {'id': id, 'code': code, 'createdAt': now});
}
