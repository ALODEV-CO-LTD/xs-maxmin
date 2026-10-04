import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET ?q=` - finds other customers by name, username or their exact Mã ID
/// (the number each customer sees on Bạn bè / Tài khoản), so a customer can
/// find and add a friend without needing to be handed a customer code
/// out-of-band first. Admin accounts are never returned: Admin is reached
/// through the Phản hồi page, not as a friend. Excludes the caller themselves and marks entries already on the
/// caller's friend list (`isFriend`) so the client can show "Đã kết bạn"
/// instead of an Add button.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final q = context.request.uri.queryParameters['q']?.trim() ?? '';
  if (q.isEmpty) {
    return Response.json(body: {'results': []});
  }

  final db = context.read<Database>();
  final rows = db.select(
    '''
    SELECT u.id, u.name, u.username, u.role,
      EXISTS(SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = u.id) AS is_friend
    FROM users u
    WHERE u.id != ? AND u.role != 'admin'
      AND (u.name LIKE ? OR u.username LIKE ?
           OR u.id IN (SELECT user_id FROM customer_codes WHERE code = ?))
    ORDER BY u.name COLLATE NOCASE
    LIMIT 20
    ''',
    [auth.userId, auth.userId, '%$q%', '%$q%', q],
  );

  return Response.json(
    body: {
      'results': [
        for (final r in rows)
          {
            'id': r['id'],
            'name': r['name'],
            'username': r['username'],
            'isAdmin': r['role'] == 'admin',
            'isFriend': (r['is_friend'] as int) == 1,
          },
      ],
    },
  );
}
