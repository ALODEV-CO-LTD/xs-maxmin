import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final search = context.request.uri.queryParameters['q']?.trim();
  final db = context.read<Database>();

  final rows = (search == null || search.isEmpty)
      ? db.select(
          "SELECT * FROM users WHERE role = 'user' ORDER BY created_at DESC",
        )
      : db.select(
          "SELECT * FROM users WHERE role = 'user' AND name LIKE ? ORDER BY created_at DESC",
          ['%$search%'],
        );

  return Response.json(
    body: {
      'total': rows.length,
      'subscribers': [
        for (final r in rows)
          {...adminSubscriberJson(r), 'avatar': initials(r['name'] as String)},
      ],
    },
  );
}
