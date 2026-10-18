import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/attachments.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/database.dart';
import 'package:server/src/push.dart';
import 'package:sqlite3/sqlite3.dart';

/// A customer's own thread with admin support - the Phản hồi (feedback)
/// page. It is the ONLY way a customer messages Admin: Admin is not a friend
/// (see routes/api/me/friends), so there is no friendship row to create here.
/// Backed by `direct_messages` between the customer and an admin account,
/// shared with routes/api/admin/messages so both ends see the same thread.
/// `sender` is derived as 'user'/'admin' from who sent each row.
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => await _send(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  final rows = db.select(
    '''
    SELECT * FROM direct_messages
    WHERE (from_user_id = ? AND to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
       OR (to_user_id = ? AND from_user_id IN (SELECT id FROM users WHERE role = 'admin'))
    ORDER BY created_at ASC
    ''',
    [userId, userId],
  );
  return Response.json(
    body: {
      'messages': [
        for (final r in rows)
          {
            'id': r['id'],
            'sender': r['from_user_id'] == userId ? 'user' : 'admin',
            'content': r['content'],
            'createdAt': r['created_at'],
            'attachment': attachmentMeta(r),
          },
      ],
    },
  );
}

Future<Response> _send(RequestContext context, String userId) async {
  final read = await readJsonBody(context, messageBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final content = (body['content'] as String?)?.trim() ?? '';
  final parsed = parseAttachment(body['attachment']);
  if (parsed.error != null) {
    return Response.json(statusCode: 400, body: {'error': parsed.error});
  }
  final att = parsed.attachment;
  if (content.isEmpty && att == null) {
    return Response.json(statusCode: 400, body: {'error': 'Nội dung trống'});
  }

  final db = context.read<Database>();
  final adminRows = db.select("SELECT id FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1");
  if (adminRows.isEmpty) {
    return Response.json(statusCode: 500, body: {'error': 'Chưa có tài khoản admin nào'});
  }
  final adminId = adminRows.first['id'] as String;

  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    '''
    INSERT INTO direct_messages
      (id, from_user_id, to_user_id, content, created_at,
       attachment_name, attachment_type, attachment_size, attachment_data)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [id, userId, adminId, content, now, att?.name, att?.type, att?.data.length, att?.data],
  );
  final saved = db.select('SELECT * FROM direct_messages WHERE id = ?', [id]).first;
  for (final to in {adminId, ...supportAdminIds(db)}) {
    pushNewMessage(db, toUserId: to, fromUserId: userId, source: 'support', messageId: id, content: content, hasAttachment: att != null);
  }
  return Response.json(
    statusCode: 201,
    body: {
      'id': id,
      'sender': 'user',
      'content': content,
      'createdAt': now,
      'attachment': attachmentMeta(saved),
    },
  );
}
