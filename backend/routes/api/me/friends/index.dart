import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/rate_gate.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => await _add(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

/// Dispatches to add-by-code (existing flow, code shared out-of-band) or
/// add-by-id (new: picked directly from `GET /me/friends/search` results).
Future<Response> _add(RequestContext context, String userId) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  if ((body['userId'] != null && body['userId'] is! String) || (body['code'] != null && body['code'] is! String)) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  // Too many failed lookups (someone sweeping IDs): wait before trying again.
  final locked = checkFriendAddLock(context, userId);
  if (locked != null) return locked;
  final directId = (body['userId'] as String?)?.trim();
  if (directId != null && directId.isNotEmpty) {
    return _addById(context, userId, directId);
  }
  return _addByCode(context, userId, body);
}

Future<Response> _addById(RequestContext context, String userId, String friendId) async {
  if (friendId == userId) {
    return Response.json(statusCode: 400, body: {'error': 'Không thể tự kết bạn với chính mình'});
  }
  final db = context.read<Database>();
  final friendRows = db.select('SELECT id, name, username, role FROM users WHERE id = ?', [friendId]);
  if (friendRows.isEmpty) {
    recordFriendAddFailure(context, userId);
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy người dùng'});
  }
  return _createFriendship(db, userId, friendRows.first);
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  // No message preview/ordering here: friend chat is end-to-end encrypted and
  // lives only on the devices (docs/MA_HOA_2_DAU.md). Each friend carries their
  // public key so the client can encrypt to it.
  final rows = db.select(
    '''
    SELECT u.id, u.name, u.username, u.role, u.e2ee_public_key
    FROM friendships f
    JOIN users u ON u.id = f.friend_id
    WHERE f.user_id = ? AND u.role != 'admin'
    ORDER BY u.name COLLATE NOCASE ASC
    ''',
    [userId],
  );
  return Response.json(
    body: {
      'friends': [
        for (final r in rows)
          {
            'id': r['id'],
            'name': r['name'],
            'username': r['username'],
            'isAdmin': r['role'] == 'admin',
            'publicKey': _key(r['e2ee_public_key']),
          },
      ],
    },
  );
}

Object? _key(Object? raw) => raw is String ? jsonDecode(raw) : null;

/// Adds a friend by one of their generated customer codes. Friendship is
/// symmetric and immediate (no pending/accept step) since sharing the code
/// out-of-band already implies consent - mirrors how the code is described
/// to users ("gửi cho người khác để kết bạn").
Response _addByCode(RequestContext context, String userId, Map<String, dynamic> body) {
  final code = (body['code'] as String?)?.trim();
  if (code == null || code.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập mã ID'});
  }

  final db = context.read<Database>();
  final codeRows = db.select('SELECT user_id FROM customer_codes WHERE code = ?', [code]);
  if (codeRows.isEmpty) {
    recordFriendAddFailure(context, userId);
    return Response.json(statusCode: 404, body: {'error': 'Mã ID không tồn tại'});
  }
  final friendId = codeRows.first['user_id'] as String;
  if (friendId == userId) {
    return Response.json(statusCode: 400, body: {'error': 'Không thể tự kết bạn với chính mình'});
  }

  final friendRows = db.select('SELECT id, name, username, role FROM users WHERE id = ?', [friendId]);
  if (friendRows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy người dùng'});
  }
  return _createFriendship(db, userId, friendRows.first);
}

/// Shared by both add flows: inserts the symmetric friendship pair (if not
/// already present) and returns the new friend in the list-row shape the
/// client expects to unshift onto its friend list.
Response _createFriendship(Database db, String userId, Row friendRow) {
  // Admin is reached through the Phản hồi page, never as a friend.
  if (friendRow['role'] == 'admin') {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Không thể kết bạn với Admin. Hãy gửi tin nhắn ở mục Phản hồi.'},
    );
  }
  final friendId = friendRow['id'] as String;
  final existing = db.select(
    'SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?',
    [userId, friendId],
  );
  if (existing.isEmpty) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO friendships (id, user_id, friend_id, created_at) VALUES (?, ?, ?, ?)',
      [newId(), userId, friendId, now],
    );
    db.execute(
      'INSERT INTO friendships (id, user_id, friend_id, created_at) VALUES (?, ?, ?, ?)',
      [newId(), friendId, userId, now],
    );
  }

  return Response.json(
    statusCode: 201,
    body: {
      'id': friendRow['id'],
      'name': friendRow['name'],
      'username': friendRow['username'],
      'isAdmin': friendRow['role'] == 'admin',
      'publicKey': _key(db.select('SELECT e2ee_public_key FROM users WHERE id = ?', [friendId]).first['e2ee_public_key']),
    },
  );
}
