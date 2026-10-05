import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/attachments.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/push.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context, String friendId) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  // Messaging Admin happens only on the Phản hồi page (/api/me/messages).
  // Refuse it here even if a legacy friendship row still exists.
  final friendIsAdmin = db.select(
    "SELECT 1 FROM users WHERE id = ? AND role = 'admin'",
    [friendId],
  ).isNotEmpty;
  if (friendIsAdmin) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Hãy nhắn tin cho Admin ở mục Phản hồi.'},
    );
  }
  final friendship = db.select(
    'SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?',
    [auth.userId, friendId],
  );
  if (friendship.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không phải bạn bè'});
  }

  return switch (context.request.method) {
    HttpMethod.get => _list(db, auth.userId, friendId),
    HttpMethod.post => await _send(context, db, auth.userId, friendId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _list(Database db, String userId, String friendId) {
  final rows = db.select(
    '''
    SELECT * FROM direct_messages
    WHERE (from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)
    ORDER BY created_at ASC
    ''',
    [userId, friendId, friendId, userId],
  );
  return Response.json(
    body: {
      'messages': [
        for (final r in rows)
          {
            'id': r['id'],
            'fromUserId': r['from_user_id'],
            'content': r['content'],
            'createdAt': r['created_at'],
            'attachment': attachmentMeta(r),
          },
      ],
    },
  );
}

Future<Response> _send(RequestContext context, Database db, String userId, String friendId) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final content = (body['content'] as String?)?.trim() ?? '';
  final parsed = parseAttachment(body['attachment']);
  if (parsed.error != null) {
    return Response.json(statusCode: 400, body: {'error': parsed.error});
  }
  final att = parsed.attachment;
  if (content.isEmpty && att == null) {
    return Response.json(statusCode: 400, body: {'error': 'Nội dung trống'});
  }

  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    '''
    INSERT INTO direct_messages
      (id, from_user_id, to_user_id, content, created_at,
       attachment_name, attachment_type, attachment_size, attachment_data)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [id, userId, friendId, content, now, att?.name, att?.type, att?.data.length, att?.data],
  );
  final saved = db.select('SELECT * FROM direct_messages WHERE id = ?', [id]).first;
  pushNewMessage(db, toUserId: friendId, fromUserId: userId, source: 'friend', messageId: id, content: content, hasAttachment: att != null);
  return Response.json(
    statusCode: 201,
    body: {
      'id': id,
      'fromUserId': userId,
      'content': content,
      'createdAt': now,
      'attachment': attachmentMeta(saved),
    },
  );
}
