import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `DELETE /api/admin/messages/:userId/:messageId` - Admin deleting one of ITS OWN replies in a customer's Phản hồi thread.
/// The row stays as a "tin nhắn đã bị xoá" notice (shown to both sides in place of the message): its text and attachment are
/// blanked for good. A customer's message can never be deleted by Admin (403). Idempotent: deleting it again is a 200.
Response onRequest(RequestContext context, String userId, String messageId) {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'support.messages');
  if (denied != null) return denied;

  final db = context.read<Database>();
  final rows = db.select(
    '''
    SELECT from_user_id, deleted_at FROM direct_messages
    WHERE id = ?
      AND ((from_user_id = ? AND to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
        OR (to_user_id = ? AND from_user_id IN (SELECT id FROM users WHERE role = 'admin')))
    ''',
    [messageId, userId, userId],
  );
  if (rows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy tin nhắn'});
  }
  if (rows.first['from_user_id'] == userId) {
    return Response.json(statusCode: 403, body: {'error': 'Không thể xoá tin nhắn của khách hàng'});
  }
  if (rows.first['deleted_at'] == null) {
    db.execute(
      '''
      UPDATE direct_messages
      SET content = '', attachment_name = NULL, attachment_type = NULL, attachment_size = NULL, attachment_data = NULL, deleted_at = ?
      WHERE id = ?
      ''',
      [DateTime.now().toUtc().toIso8601String(), messageId],
    );
  }
  return Response.json(body: {'ok': true});
}
