import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/attachments.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/admin/messages/:userId/attachment/:messageId` - admin reading an
/// attachment from one customer's Phản hồi thread.
Response onRequest(RequestContext context, String userId, String messageId) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final db = context.read<Database>();
  final rows = db.select(
    '''
    SELECT * FROM direct_messages
    WHERE id = ?
      AND ((from_user_id = ? AND to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
        OR (to_user_id = ? AND from_user_id IN (SELECT id FROM users WHERE role = 'admin')))
    ''',
    [messageId, userId, userId],
  );
  if (rows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy tin nhắn'});
  }
  return attachmentResponse(rows.first);
}
