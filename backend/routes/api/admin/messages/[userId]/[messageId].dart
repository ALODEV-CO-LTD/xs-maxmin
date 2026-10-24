import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `DELETE /api/admin/messages/:userId/:messageId` - admin deleting one message of a customer's Phản hồi thread (the
/// customer's own message or an admin reply). Only a row that really belongs to that thread can be deleted. The rows are
/// shared with the customer's Phản hồi page, so it disappears there too.
Response onRequest(RequestContext context, String userId, String messageId) {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'support.messages');
  if (denied != null) return denied;

  final db = context.read<Database>();
  db.execute(
    '''
    DELETE FROM direct_messages
    WHERE id = ?
      AND ((from_user_id = ? AND to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
        OR (to_user_id = ? AND from_user_id IN (SELECT id FROM users WHERE role = 'admin')))
    ''',
    [messageId, userId, userId],
  );
  if (db.updatedRows == 0) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy tin nhắn'});
  }
  return Response.json(body: {'ok': true});
}
