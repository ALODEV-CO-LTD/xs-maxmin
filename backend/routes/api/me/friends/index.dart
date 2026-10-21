import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/database.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:server/src/friend_requests.dart';
import 'package:server/src/rate_gate.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role == 'admin' && context.request.method == HttpMethod.post) return forbidden();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => await _add(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

/// Dispatches to add-by-code (existing flow, code shared out-of-band) or
/// add-by-id (new: picked directly from `GET /me/friends/search` results).
Future<Response> _add(RequestContext context, String userId) async {
  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
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
  return requestFriend(db, userId, friendRows.first);
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
            // one key per device of the friend: the sender encrypts to each of them
            'devices': friendDevices(db, r['id'] as String),
          },
      ],
    },
  );
}

Object? _key(Object? raw) => raw is String ? jsonDecode(raw) : null;

/// Asks a friend by one of their generated customer codes. Like add-by-id this
/// only creates a friend REQUEST; the friendship exists once they accept.
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
  markCodeUsed(db, code);
  final friendId = codeRows.first['user_id'] as String;
  if (friendId == userId) {
    return Response.json(statusCode: 400, body: {'error': 'Không thể tự kết bạn với chính mình'});
  }

  final friendRows = db.select('SELECT id, name, username, role FROM users WHERE id = ?', [friendId]);
  if (friendRows.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy người dùng'});
  }
  return requestFriend(db, userId, friendRows.first);
}
