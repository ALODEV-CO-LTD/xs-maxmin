import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/admin/messages` - one row per customer who has messaged an
/// admin account, newest conversation first. Feeds the admin "Phản hồi"
/// tab (per-conversation unread counts come from `GET /api/me/unread`). Sourced from `direct_messages` (the same table the "Bạn bè" tab
/// uses) rather than the old standalone `messages` table, so a customer
/// only has to reach out once - via the friend chat they already have -
/// for it to show up here too, instead of admin needing a second, separate
/// "Giữa khách hàng" view just to see it.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'support.messages');
  if (denied != null) return denied;

  final db = context.read<Database>();
  final rows = db.select('''
    SELECT
      u.id AS user_id,
      u.name AS name,
      u.username AS username,
      u.package_type AS package_type,
      u.package_expires_at AS package_expires_at,
      (SELECT dm.from_user_id = u.id FROM direct_messages dm
        WHERE (dm.from_user_id = u.id AND dm.to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
           OR (dm.to_user_id = u.id AND dm.from_user_id IN (SELECT id FROM users WHERE role = 'admin'))
        ORDER BY dm.created_at DESC LIMIT 1) AS last_from_user,
      (SELECT CASE WHEN dm.deleted_at IS NOT NULL THEN 'Tin nhắn đã bị xoá' WHEN dm.content = '' THEN '[Đính kèm] ' || COALESCE(dm.attachment_name, '') ELSE dm.content END FROM direct_messages dm
        WHERE (dm.from_user_id = u.id AND dm.to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
           OR (dm.to_user_id = u.id AND dm.from_user_id IN (SELECT id FROM users WHERE role = 'admin'))
        ORDER BY dm.created_at DESC LIMIT 1) AS last_content,
      (SELECT created_at FROM direct_messages dm
        WHERE (dm.from_user_id = u.id AND dm.to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
           OR (dm.to_user_id = u.id AND dm.from_user_id IN (SELECT id FROM users WHERE role = 'admin'))
        ORDER BY dm.created_at DESC LIMIT 1) AS last_at
    FROM users u
    WHERE u.role = 'user' AND EXISTS (
      SELECT 1 FROM direct_messages dm2
      WHERE (dm2.from_user_id = u.id AND dm2.to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
         OR (dm2.to_user_id = u.id AND dm2.from_user_id IN (SELECT id FROM users WHERE role = 'admin'))
    )
    ORDER BY last_at DESC
  ''');

  return Response.json(
    body: {
      'conversations': [
        for (final r in rows)
          {
            'userId': r['user_id'],
            'userName': r['name'],
            'username': r['username'],
            'packageType': r['package_type'],
            'packageExpiresAt': r['package_expires_at'],
            // true when the customer wrote last, i.e. admin has not answered yet.
            'awaitingReply': (r['last_from_user'] as int? ?? 0) == 1,
            'avatar': initials(r['name'] as String),
            'lastMessage': r['last_content'],
            'lastMessageAt': r['last_at'],
          },
      ],
    },
  );
}
