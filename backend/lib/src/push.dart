import 'package:server/src/call_signaling.dart';
import 'package:sqlite3/sqlite3.dart';

/// Tells [toUserId]'s open app (over the signaling WebSocket) that a message
/// just arrived, so it can ping, show a notification and refresh the
/// conversation without polling. Best-effort: a user who is offline simply
/// finds the message next time they open the page.
///
/// [source] is 'friend' (chat between customers) or 'support' (customer <->
/// Admin, the Phản hồi page). Only a short preview travels - never the
/// attachment itself.
void pushNewMessage(
  Database db, {
  required String toUserId,
  required String fromUserId,
  required String source,
  required String messageId,
  required String content,
  required bool hasAttachment,
  String? fromName,
}) {
  var name = fromName;
  if (name == null) {
    final rows = db.select('SELECT name FROM users WHERE id = ?', [fromUserId]);
    name = rows.isEmpty ? 'Người dùng' : rows.first['name'] as String;
  }
  var preview = content.trim();
  if (preview.length > 80) preview = '${preview.substring(0, 80)}…';
  if (preview.isEmpty && hasAttachment) preview = 'Đã gửi một tệp đính kèm';
  CallSignalingRegistry.instance.sendTo(toUserId, {
    'type': 'new-message',
    'source': source,
    'from': fromUserId,
    'fromName': name,
    'messageId': messageId,
    'preview': preview,
    'hasAttachment': hasAttachment,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}
