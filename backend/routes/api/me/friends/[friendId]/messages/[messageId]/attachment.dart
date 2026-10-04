import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/attachments.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/me/friends/:friendId/messages/:messageId/attachment` - the file
/// or image attached to one message of this friend chat. Only the two people
/// in the conversation can read it.
Response onRequest(RequestContext context, String friendId, String messageId) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final friendship = db.select(
    'SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?',
    [auth.userId, friendId],
  );
  if (friendship.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không phải bạn bè'});
  }
  final rows = db.select(
    '''
    SELECT * FROM direct_messages
    WHERE id = ?
      AND ((from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?))
    ''',
    [messageId, auth.userId, friendId, friendId, auth.userId],
  );
  if (rows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy tin nhắn'});
  }
  return attachmentResponse(rows.first);
}
