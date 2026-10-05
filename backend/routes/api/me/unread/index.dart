import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/me/unread` -> unread message counts, kept on the server so they
/// survive a page reload and include messages that arrived while the user was
/// offline:
///   `{ friends: {<friendId>: n}, support: n, supportByUser: {<userId>: n},
///      total: n }`
/// `support` is a customer's unread replies from Admin; `supportByUser` is an
/// Admin's unread messages per customer.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final me = auth.userId;
  final db = context.read<Database>();

  final rows = db.select(
    '''
    SELECT m.from_user_id AS peer, u.role AS role, COUNT(*) AS n
    FROM direct_messages m
    JOIN users u ON u.id = m.from_user_id
    LEFT JOIN message_reads r
      ON r.user_id = ?1
     AND r.peer_key = CASE WHEN u.role = 'admin' THEN 'support' ELSE m.from_user_id END
    WHERE m.to_user_id = ?1
      AND m.created_at > COALESCE(
            r.last_read_at,
            (SELECT value FROM settings WHERE key = 'unread_epoch'),
            '')
    GROUP BY m.from_user_id
    ''',
    [me],
  );

  final friends = <String, int>{};
  final supportByUser = <String, int>{};
  var support = 0;
  var total = 0;
  for (final r in rows) {
    final n = r['n'] as int;
    total += n;
    if (r['role'] == 'admin') {
      support += n;
    } else if (auth.role == 'admin') {
      supportByUser[r['peer'] as String] = n;
    } else {
      friends[r['peer'] as String] = n;
    }
  }
  return Response.json(body: {
    'friends': friends,
    'support': support,
    'supportByUser': supportByUser,
    'total': total,
  });
}
