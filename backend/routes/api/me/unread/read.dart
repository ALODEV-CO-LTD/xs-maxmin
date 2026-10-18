import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST /api/me/unread/read` `{ peerId }` - the user opened (or is looking at)
/// the conversation with [peerId]; everything up to now counts as read.
/// `peerId` may be a friend, a customer (when the caller is Admin), an Admin's
/// id, or the literal 'support' (the customer's Phản hồi conversation).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final peerId = body['peerId'];
  if (peerId is! String || peerId.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu peerId'});
  }
  final db = context.read<Database>();
  // 'support' is the customer's conversation with Admin (a customer does not
  // know any Admin's user id).
  var key = peerId;
  if (peerId != 'support') {
    final peer = db.select('SELECT role FROM users WHERE id = ?', [peerId]);
    if (peer.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy người dùng'});
    }
    if (peer.first['role'] == 'admin') key = 'support';
  }
  db.execute(
    '''
    INSERT INTO message_reads (user_id, peer_key, last_read_at) VALUES (?, ?, ?)
    ON CONFLICT(user_id, peer_key) DO UPDATE SET last_read_at = excluded.last_read_at
    ''',
    [auth.userId, key, DateTime.now().toUtc().toIso8601String()],
  );
  return Response.json(body: {'ok': true});
}
