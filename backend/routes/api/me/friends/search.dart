import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/database.dart';
import 'package:server/src/rate_gate.dart';
import 'package:server/src/text_fold.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET ?q=` - finds other customers by name (accents ignored), username or their exact Mã ID
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

  // Per-user and per-IP limit so the Mã ID space cannot be swept.
  final limited = throttleFriendSearch(context, auth.userId);
  if (limited != null) return limited;

  final q = context.request.uri.queryParameters['q']?.trim() ?? '';
  if (q.isEmpty) {
    return Response.json(body: {'results': []});
  }

  final db = context.read<Database>();
  // SQLite's LIKE does not ignore Vietnamese accents, so candidates are read and matched here
  // with foldVi ("do ngoc" finds "Đỗ Ngọc Mai"). An exact Mã ID always matches.
  final needle = foldVi(q);
  final candidates = db.select(
    '''
    SELECT u.id, u.name, u.username, u.role,
      EXISTS(SELECT 1 FROM friendships WHERE user_id = ?1 AND friend_id = u.id) AS is_friend,
      CASE
        WHEN EXISTS(SELECT 1 FROM friend_requests WHERE from_user_id = ?1 AND to_user_id = u.id AND status = 'pending') THEN 'outgoing'
        WHEN EXISTS(SELECT 1 FROM friend_requests WHERE from_user_id = u.id AND to_user_id = ?1 AND status = 'pending') THEN 'incoming'
        ELSE 'none' END AS request_state,
      EXISTS(SELECT 1 FROM customer_codes WHERE user_id = u.id AND code = ?2) AS by_code
    FROM users u
    WHERE u.id != ?1 AND u.role != 'admin'
    ''',
    [auth.userId, q],
  );
  final matched = [
    for (final r in candidates)
      if ((r['by_code'] as int) == 1 ||
          foldVi(r['name'] as String).contains(needle) ||
          foldVi(r['username'] as String).contains(needle))
        r,
  ]..sort((a, b) => foldVi(a['name'] as String).compareTo(foldVi(b['name'] as String)));
  final rows = matched.take(20).toList();
  if (rows.any((r) => (r['by_code'] as int) == 1)) markCodeUsed(db, q);

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
            'requestState': r['request_state'],
          },
      ],
    },
  );
}
