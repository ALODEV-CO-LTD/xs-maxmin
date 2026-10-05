import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// DELETE - cancels a pending deletion schedule. The owner can cancel any of
/// theirs; either person in a conversation can cancel its chat auto-delete
/// rule. Cancelling never restores anything already deleted.
Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  db.execute(
    '''
    UPDATE deletion_schedules SET status = 'cancelled'
    WHERE id = ? AND status = 'pending'
      AND (user_id = ? OR (kind = 'chat' AND friend_id = ?))
    ''',
    [id, auth.userId, auth.userId],
  );
  if (db.updatedRows == 0) {
    return Response.json(statusCode: 404, body: {'error': 'Không có lịch xoá đang chờ này'});
  }
  return Response.json(body: {'ok': true});
}
