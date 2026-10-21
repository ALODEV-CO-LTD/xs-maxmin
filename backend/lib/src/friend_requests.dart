import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/call_signaling.dart';
import 'package:server/src/database.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:server/src/push_message.dart';
import 'package:server/src/push_notify.dart';
import 'package:sqlite3/sqlite3.dart';

const maxPendingOutgoing = 30;
const maxPendingIncoming = 200;
const declineCooldown = Duration(hours: 24);
const listLimit = 100;

/// Idempotent DDL for the friend-request table (fresh and existing DBs).
const friendRequestsDdl = '''
  CREATE TABLE IF NOT EXISTS friend_requests (
    id TEXT PRIMARY KEY,
    from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('pending','accepted','declined','cancelled')),
    created_at TEXT NOT NULL,
    decided_at TEXT
  );
  CREATE UNIQUE INDEX IF NOT EXISTS idx_friend_requests_pending_pair
    ON friend_requests (from_user_id, to_user_id) WHERE status = 'pending';
  CREATE INDEX IF NOT EXISTS idx_friend_requests_to_status ON friend_requests (to_user_id, status);
  CREATE INDEX IF NOT EXISTS idx_friend_requests_from_status ON friend_requests (from_user_id, status);
''';

void ensureFriendRequestsTable(Database db) => db.execute(friendRequestsDdl);

String _now() => DateTime.now().toUtc().toIso8601String();

Response _bad(int code, String msg) => Response.json(statusCode: code, body: {'error': msg});

/// The GET /me/friends row for [friendId], or null if the user is missing.
Map<String, dynamic>? friendListRow(Database db, String friendId) {
  final r = db.select('SELECT id, name, username, role, e2ee_public_key FROM users WHERE id = ?', [friendId]);
  if (r.isEmpty) return null;
  final k = r.first['e2ee_public_key'];
  return {
    'id': r.first['id'],
    'name': r.first['name'],
    'username': r.first['username'],
    'isAdmin': r.first['role'] == 'admin',
    'publicKey': k is String ? jsonDecode(k) : null,
    'devices': friendDevices(db, friendId),
  };
}

bool areFriends(Database db, String a, String b) =>
    db.select('SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?', [a, b]).isNotEmpty;

int pendingIncomingCount(Database db, String userId) =>
    db.select("SELECT COUNT(*) AS n FROM friend_requests WHERE to_user_id = ? AND status = 'pending'", [userId]).first['n'] as int;

String _nameOf(Database db, String id) {
  final r = db.select('SELECT name FROM users WHERE id = ?', [id]);
  return r.isEmpty ? 'Người dùng' : r.first['name'] as String;
}

/// Inserts the symmetric friendship pair (idempotent).
void _makeFriends(Database db, String a, String b) {
  final now = _now();
  for (final p in [(a, b), (b, a)]) {
    db.execute(
      'INSERT OR IGNORE INTO friendships (id, user_id, friend_id, created_at) VALUES (?, ?, ?, ?)',
      [newId(), p.$1, p.$2, now],
    );
  }
}

/// Accepts pending request [requestId] (recipient [toId], requester [fromId]):
/// creates both friendship rows, marks accepted and tells the requester.
void _acceptPending(Database db, String requestId, String fromId, String toId) {
  db.execute('BEGIN IMMEDIATE');
  try {
    _makeFriends(db, fromId, toId);
    db.execute("UPDATE friend_requests SET status = 'accepted', decided_at = ? WHERE id = ?", [_now(), requestId]);
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  CallSignalingRegistry.instance.sendToAll(fromId, {
    'type': 'friend-accepted',
    'friendId': toId,
    'name': _nameOf(db, toId),
  });
}

Map<String, dynamic> _outgoingRow(Row r, String toName, String toUsername) => {
      'id': r['id'],
      'toId': r['to_user_id'],
      'toName': toName,
      'toUsername': toUsername,
      'createdAt': r['created_at'],
    };

/// Both add flows end here: [me] asks [target] (a users row) to be friends.
Response requestFriend(Database db, String me, Row target) {
  if (target['role'] == 'admin') {
    return _bad(400, 'Không thể kết bạn với Admin. Hãy gửi tin nhắn ở mục Phản hồi.');
  }
  final other = target['id'] as String;
  if (areFriends(db, me, other)) {
    return Response.json(body: {'status': 'friends', 'friend': friendListRow(db, other)});
  }
  // The target already asked me: asking back means yes.
  final incoming = db.select(
    "SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'",
    [other, me],
  );
  if (incoming.isNotEmpty) {
    _acceptPending(db, incoming.first['id'] as String, other, me);
    return Response.json(body: {'status': 'friends', 'friend': friendListRow(db, other)});
  }
  final mine = db.select(
    "SELECT id, to_user_id, created_at FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'",
    [me, other],
  );
  if (mine.isNotEmpty) {
    return Response.json(body: {
      'status': 'pending',
      'request': _outgoingRow(mine.first, target['name'] as String, target['username'] as String),
    });
  }
  // Declined me recently: look pending, create nothing (the decline stays private).
  final since = DateTime.now().toUtc().subtract(declineCooldown).toIso8601String();
  final declined = db.select(
    "SELECT 1 FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'declined' AND decided_at > ?",
    [me, other, since],
  );
  if (declined.isNotEmpty) return Response.json(body: {'status': 'pending'});

  final outCount = db.select("SELECT COUNT(*) AS n FROM friend_requests WHERE from_user_id = ? AND status = 'pending'", [me]).first['n'] as int;
  if (outCount >= maxPendingOutgoing) {
    return _bad(429, 'Bạn đã gửi quá nhiều lời mời đang chờ. Hãy huỷ bớt hoặc chờ người kia trả lời.');
  }
  if (pendingIncomingCount(db, other) >= maxPendingIncoming) {
    return Response.json(body: {'status': 'pending'});
  }

  final id = newId();
  final createdAt = _now();
  db.execute(
    "INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES (?, ?, ?, 'pending', ?)",
    [id, me, other, createdAt],
  );
  final fromName = _nameOf(db, me);
  final registry = CallSignalingRegistry.instance;
  if (registry.isOnline(other)) {
    registry.sendToAll(other, {'type': 'friend-request', 'requestId': id, 'fromId': me, 'fromName': fromName});
  } else {
    notifyOfflineRecipient(kind: PushKind.friendRequest, fromUserId: me, fromName: fromName, toUserId: other);
  }
  return Response.json(statusCode: 201, body: {
    'status': 'pending',
    'request': {
      'id': id,
      'toId': other,
      'toName': target['name'],
      'toUsername': target['username'],
      'createdAt': createdAt,
    },
  });
}

Map<String, dynamic> listRequests(Database db, String me) {
  final inc = db.select(
    '''
    SELECT r.id, r.from_user_id, r.created_at, u.name, u.username
    FROM friend_requests r JOIN users u ON u.id = r.from_user_id
    WHERE r.to_user_id = ? AND r.status = 'pending' AND u.role != 'admin'
    ORDER BY r.created_at DESC, r.id LIMIT $listLimit
    ''',
    [me],
  );
  final out = db.select(
    '''
    SELECT r.id, r.to_user_id, r.created_at, u.name, u.username
    FROM friend_requests r JOIN users u ON u.id = r.to_user_id
    WHERE r.from_user_id = ? AND r.status = 'pending' AND u.role != 'admin'
    ORDER BY r.created_at DESC, r.id LIMIT $listLimit
    ''',
    [me],
  );
  return {
    'incoming': [
      for (final r in inc)
        {
          'id': r['id'],
          'fromId': r['from_user_id'],
          'fromName': r['name'],
          'fromUsername': r['username'],
          'createdAt': r['created_at'],
        },
    ],
    'outgoing': [for (final r in out) _outgoingRow(r, r['name'] as String, r['username'] as String)],
  };
}

Row? _byId(Database db, String id) {
  final r = db.select('SELECT id, from_user_id, to_user_id, status FROM friend_requests WHERE id = ?', [id]);
  return r.isEmpty ? null : r.first;
}

Response _notFound() => _bad(404, 'Không tìm thấy lời mời kết bạn');

Response acceptRequest(Database db, String me, String id) {
  final r = _byId(db, id);
  if (r == null || r['to_user_id'] != me) return _notFound();
  final from = r['from_user_id'] as String;
  switch (r['status']) {
    case 'accepted':
      break;
    case 'pending':
      _acceptPending(db, id, from, me);
    default:
      return _bad(409, 'Lời mời này đã được xử lý, không thể chấp nhận.');
  }
  return Response.json(body: {'friend': friendListRow(db, from)});
}

Response declineRequest(Database db, String me, String id) {
  final r = _byId(db, id);
  if (r == null || r['to_user_id'] != me) return _notFound();
  if (r['status'] == 'pending') {
    db.execute("UPDATE friend_requests SET status = 'declined', decided_at = ? WHERE id = ?", [_now(), id]);
  } else if (r['status'] != 'declined') {
    return _bad(409, 'Lời mời này đã được xử lý.');
  }
  return Response.json(body: {'ok': true});
}

Response cancelRequest(Database db, String me, String id) {
  final r = _byId(db, id);
  if (r == null || r['from_user_id'] != me) return _notFound();
  if (r['status'] == 'pending') {
    db.execute("UPDATE friend_requests SET status = 'cancelled', decided_at = ? WHERE id = ?", [_now(), id]);
  } else if (r['status'] != 'cancelled') {
    return _bad(409, 'Lời mời này đã được xử lý.');
  }
  return Response.json(body: {'ok': true});
}
