import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/attachments.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/database.dart';
import 'package:server/src/push.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET`/`POST /api/admin/messages/:userId` - admin reading or replying to
/// one customer's thread. Backed by `direct_messages` between that customer
/// and any admin account (the customer's Phản hồi page reads the same
/// table), with `sender` derived as 'admin'/'user' from who sent each row
/// so the existing thread UI (MessageThreadView.vue) needs no changes.
/// Admin is never a friend, so replying creates no friendship row.
Future<Response> onRequest(RequestContext context, String userId) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'support.messages');
  if (denied != null) return denied;

  return switch (context.request.method) {
    HttpMethod.get => _list(context, userId),
    HttpMethod.post => await _reply(context, auth.userId, userId),
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

Future<Response> _reply(RequestContext context, String adminId, String userId) async {
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

  final db = context.read<Database>();
  final targetExists = db.select("SELECT 1 FROM users WHERE id = ? AND role = 'user'", [userId]);
  if (targetExists.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy khách hàng'});
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
    [id, adminId, userId, content, now, att?.name, att?.type, att?.data.length, att?.data],
  );
  final saved = db.select('SELECT * FROM direct_messages WHERE id = ?', [id]).first;
  pushNewMessage(db, toUserId: userId, fromUserId: adminId, source: 'support', messageId: id, content: content, hasAttachment: att != null, fromName: 'Hỗ trợ (Admin)');
  return Response.json(
    statusCode: 201,
    body: {
      'id': id,
      'sender': 'admin',
      'content': content,
      'createdAt': now,
      'attachment': attachmentMeta(saved),
    },
  );
}
