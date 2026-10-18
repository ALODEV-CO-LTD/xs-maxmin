import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/me/calls?friendId=<id>&limit=<n>` - the caller's voice-call
/// history (newest first), optionally only with one friend, plus how many
/// missed calls per friend they have not seen yet:
/// `{ calls: [...], unseenMissed: { <friendId>: <count> } }`.
/// A call is "missed" for the callee when it ended unanswered - the caller
/// hung up, it timed out, the callee was offline, or the callee was busy.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final me = auth.userId;
  final db = context.read<Database>();

  final params = context.request.uri.queryParameters;
  final friendId = params['friendId'];
  final limit = (int.tryParse(params['limit'] ?? '') ?? 50).clamp(1, 200);

  final rows = db.select(
    '''
    SELECT c.*, uc.name AS caller_name, ue.name AS callee_name
    FROM call_logs c
    JOIN users uc ON uc.id = c.caller_id
    JOIN users ue ON ue.id = c.callee_id
    WHERE (c.caller_id = ? OR c.callee_id = ?)
      ${friendId == null ? '' : 'AND (c.caller_id = ? OR c.callee_id = ?)'}
    ORDER BY c.created_at DESC
    LIMIT ?
    ''',
    [me, me, if (friendId != null) ...[friendId, friendId], limit],
  );

  final calls = [
    for (final r in rows)
      () {
        final outgoing = r['caller_id'] == me;
        return {
          'id': r['id'],
          'direction': outgoing ? 'outgoing' : 'incoming',
          'peerId': outgoing ? r['callee_id'] : r['caller_id'],
          'peerName': outgoing ? r['callee_name'] : r['caller_name'],
          'status': r['status'],
          'createdAt': r['created_at'],
          'answeredAt': r['answered_at'],
          'durationSeconds': r['duration_seconds'],
          'seen': outgoing || r['callee_seen'] == 1,
        };
      }(),
  ];

  final unseen = db.select(
    '''
    SELECT caller_id, COUNT(*) AS n FROM call_logs
    WHERE callee_id = ? AND callee_seen = 0 AND status IN ('missed', 'busy')
    GROUP BY caller_id
    ''',
    [me],
  );
  return Response.json(body: {
    'calls': calls,
    'unseenMissed': {for (final r in unseen) r['caller_id'] as String: r['n']},
  });
}
