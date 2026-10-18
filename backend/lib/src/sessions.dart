import 'dart:io' show InternetAddress;
import 'dart:math';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import 'call_signaling.dart';
import 'database.dart' show newId;
import 'push_tokens.dart';
import 'security_policy.dart';

// ---------------------------------------------------------------------------
// Security event log (NFR-07)
// ---------------------------------------------------------------------------

/// Appends one row to `security_events`. [type] is a short code such as
/// 'login_failed', 'login_locked', 'session_revoked', 'data_wiped'. [detail]
/// is free text for the admin - callers must NEVER pass a password or token.
void logSecurityEvent(
  Database db,
  String type, {
  String? userId,
  String? username,
  String? ip,
  String? detail,
}) {
  db.execute(
    '''
    INSERT INTO security_events (id, type, user_id, username, ip, detail, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [newId(), type, userId, username, ip, detail, DateTime.now().toUtc().toIso8601String()],
  );
}

/// Remote address of the caller. The direct socket peer is used, EXCEPT when that peer is a loopback address (production:
/// nginx on 127.0.0.1 fed by a Cloudflare tunnel, so every request has peer 127.0.0.1): then the proxy's view of the
/// client is trusted - `CF-Connecting-IP`, else the first `X-Forwarded-For` value, else `X-Real-IP` - provided it is a
/// valid IP. From any non-loopback peer these headers are ignored, so a direct client cannot spoof its address.
String clientIp(RequestContext context) {
  try {
    final peer = context.request.connectionInfo.remoteAddress.address;
    return resolveClientIp(peer, context.request.headers);
  } catch (_) {
    return 'unknown';
  }
}

/// Pure part of [clientIp] (unit-tested): [peer] is the socket peer, [headers] the request headers (any case).
String resolveClientIp(String peer, Map<String, String> headers) {
  if (!_isLoopback(peer)) return peer;
  String? header(String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  final candidates = [
    header('cf-connecting-ip'),
    header('x-forwarded-for')?.split(',').first,
    header('x-real-ip'),
  ];
  for (final c in candidates) {
    final v = c?.trim();
    if (v == null || v.isEmpty) continue;
    final ip = InternetAddress.tryParse(v);
    if (ip != null) return ip.address;
  }
  return peer;
}

bool _isLoopback(String peer) {
  final ip = InternetAddress.tryParse(peer.startsWith('::ffff:') ? peer.substring(7) : peer);
  return ip != null && ip.isLoopback;
}

// ---------------------------------------------------------------------------
// Login throttling (K03 / S03)
// ---------------------------------------------------------------------------

// Free tries, first lock and lock ceiling come from the admin-set security policy
// (security_policy.dart); the lock doubles with every further failure.
const _failureMemory = Duration(hours: 1); // quiet period that resets the count

String _attemptKey(String identity, String ip) => '${identity.toLowerCase()}|$ip';

/// Seconds the caller must still wait before another attempt for this
/// account + IP, or 0 if not locked. Nothing is ever deleted by a lock.
int lockedSecondsLeft(Database db, String identity, String ip) {
  final rows = db.select(
    'SELECT locked_until FROM login_attempts WHERE key = ?',
    [_attemptKey(identity, ip)],
  );
  if (rows.isEmpty) return 0;
  final until = rows.first['locked_until'] as String?;
  if (until == null) return 0;
  final left = DateTime.parse(until).difference(DateTime.now().toUtc()).inSeconds;
  return left > 0 ? left + 1 : 0;
}

/// Counts one wrong attempt; once past [_freeAttempts] the account+IP is
/// locked with an exponentially growing delay (30s, 60s, 120s ... max 15 min).
/// Returns the lock length in seconds if this failure triggered a lock, else 0.
///
/// [freeAttempts] lets a caller use a looser threshold for a shared counter
/// (e.g. one per IP across many account names); default is [_freeAttempts].
int recordLoginFailure(Database db, String identity, String ip, {String? userId, int? freeAttempts}) {
  final policy = loadPolicy(db);
  final free = freeAttempts ?? policy.loginFreeAttempts;
  final key = _attemptKey(identity, ip);
  final now = DateTime.now().toUtc();
  var count = 0;
  final rows = db.select('SELECT fail_count, last_fail_at FROM login_attempts WHERE key = ?', [key]);
  if (rows.isNotEmpty) {
    final last = DateTime.parse(rows.first['last_fail_at'] as String);
    if (now.difference(last) < _failureMemory) count = rows.first['fail_count'] as int;
  }
  count += 1;
  var lockSeconds = 0;
  String? lockedUntil;
  if (count >= free) {
    lockSeconds = min(policy.loginBaseLockSeconds * (1 << min(count - free, 10)), policy.loginMaxLockSeconds);
    lockedUntil = now.add(Duration(seconds: lockSeconds)).toIso8601String();
  }
  db.execute(
    '''
    INSERT INTO login_attempts (key, fail_count, last_fail_at, locked_until)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET fail_count = excluded.fail_count,
      last_fail_at = excluded.last_fail_at, locked_until = excluded.locked_until
    ''',
    [key, count, now.toIso8601String(), lockedUntil],
  );
  logSecurityEvent(db, 'login_failed', userId: userId, username: identity, ip: ip, detail: 'Lần sai thứ $count');
  if (lockSeconds > 0) {
    logSecurityEvent(db, 'login_locked', userId: userId, username: identity, ip: ip, detail: 'Khoá tạm $lockSeconds giây');
  }
  return lockSeconds;
}

void clearLoginFailures(Database db, String identity, String ip) {
  db.execute('DELETE FROM login_attempts WHERE key = ?', [_attemptKey(identity, ip)]);
}

/// Generic 429 body: never says which field was wrong.
Response lockedResponse(int seconds) => Response.json(
      statusCode: 429,
      headers: {'retry-after': '$seconds'},
      body: {
        'error': 'Quá nhiều lần thử không thành công. Vui lòng thử lại sau $seconds giây.',
        'retryAfterSeconds': seconds,
      },
    );

// ---------------------------------------------------------------------------
// Device sessions (K10 / A04 / A14 / S04)
// ---------------------------------------------------------------------------

/// Short human label for a User-Agent, e.g. "Chrome · macOS (máy tính)".
String deviceLabel(String? ua) {
  final s = ua ?? '';
  if (s.isEmpty) return 'Thiết bị không rõ';
  final browser = s.contains('Edg/')
      ? 'Edge'
      : s.contains('OPR/')
          ? 'Opera'
          : s.contains('Firefox/')
              ? 'Firefox'
              : s.contains('Chrome/')
                  ? 'Chrome'
                  : s.contains('Safari/')
                      ? 'Safari'
                      : 'Trình duyệt khác';
  final os = s.contains('Windows')
      ? 'Windows'
      : s.contains('Android')
          ? 'Android'
          : (s.contains('iPhone') || s.contains('iPad'))
              ? 'iOS'
              : s.contains('Mac OS')
                  ? 'macOS'
                  : s.contains('Linux')
                      ? 'Linux'
                      : 'HĐH khác';
  final kind = (s.contains('Mobile') || s.contains('Android') || s.contains('iPhone')) ? 'điện thoại' : 'máy tính';
  return '$browser · $os ($kind)';
}

/// Creates the session row a freshly issued token points to (its id goes into
/// the JWT as `sid`).
String createSession(Database db, String userId, RequestContext context) {
  final id = newId();
  final ua = context.request.headers['user-agent'];
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    '''
    INSERT INTO device_sessions (id, user_id, device_label, user_agent, ip, created_at, last_seen)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [id, userId, deviceLabel(ua), ua == null ? null : (ua.length > 300 ? ua.substring(0, 300) : ua), clientIp(context), now, now],
  );
  return id;
}

/// True unless the session row exists and was revoked (or belongs to another
/// user). A token WITHOUT a session id (issued before this feature) is
/// accepted as before, so existing logins are not kicked out.
/// Also refreshes `last_seen`, at most once a minute per session.
///
/// Also false when the account no longer exists or an admin locked it
/// (`users.status = 'locked'`) - one primary-key lookup on `users`, so a
/// locked account's existing tokens (and its call WebSocket) stop working
/// immediately. A token with no session id is additionally rejected when it
/// was issued ([issuedAtSeconds], JWT `iat`) at or before the account's
/// `tokens_valid_after` (set by [revokeAllSessions]), so the pre-session
/// tokens that cannot be revoked row by row are revoked as well.
bool sessionIsActive(Database db, String userId, String? sessionId, {int? issuedAtSeconds}) {
  final u = db.select('SELECT status, tokens_valid_after FROM users WHERE id = ?', [userId]);
  if (u.isEmpty || u.first['status'] == 'locked') return false;
  if (sessionId == null) {
    final after = u.first['tokens_valid_after'] as int?;
    return after == null || (issuedAtSeconds != null && issuedAtSeconds > after);
  }
  final rows = db.select(
    'SELECT user_id, revoked_at, last_seen FROM device_sessions WHERE id = ?',
    [sessionId],
  );
  if (rows.isEmpty) return false;
  final r = rows.first;
  if (r['user_id'] != userId || r['revoked_at'] != null) return false;
  final now = DateTime.now().toUtc();
  final seen = DateTime.tryParse(r['last_seen'] as String? ?? '');
  if (seen == null || now.difference(seen).inSeconds >= 60) {
    db.execute('UPDATE device_sessions SET last_seen = ? WHERE id = ?', [now.toIso8601String(), sessionId]);
  }
  return true;
}

/// Active (not revoked) sessions of [userId], most recently used first.
List<Map<String, dynamic>> listSessions(Database db, String userId, {String? currentSessionId}) {
  final rows = db.select(
    'SELECT * FROM device_sessions WHERE user_id = ? AND revoked_at IS NULL ORDER BY last_seen DESC',
    [userId],
  );
  return [
    for (final r in rows)
      {
        'id': r['id'],
        'deviceLabel': r['device_label'],
        'ip': r['ip'],
        'createdAt': r['created_at'],
        'lastSeen': r['last_seen'],
        'current': r['id'] == currentSessionId,
      },
  ];
}

/// Revokes one session of [userId]; returns false if there was none active.
bool revokeSession(Database db, String userId, String sessionId, {required String by, String? ip}) {
  db.execute(
    'UPDATE device_sessions SET revoked_at = ?, revoked_by = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL',
    [DateTime.now().toUtc().toIso8601String(), by, sessionId, userId],
  );
  final changed = db.updatedRows > 0;
  if (changed) {
    // The session's open call/chat socket and its push token die with it.
    CallSignalingRegistry.instance.closeSession(userId, sessionId);
    deletePushTokensOfSession(db, sessionId);
    logSecurityEvent(db, 'session_revoked', userId: userId, ip: ip, detail: by == userId ? 'Người dùng tự đăng xuất thiết bị' : 'Admin thu hồi phiên');
  }
  return changed;
}

/// Revokes every active session of [userId] except [exceptSessionId].
int revokeAllSessions(Database db, String userId, {required String by, String? exceptSessionId, String? ip}) {
  db.execute(
    'UPDATE device_sessions SET revoked_at = ?, revoked_by = ? WHERE user_id = ? AND revoked_at IS NULL AND id != ?',
    [DateTime.now().toUtc().toIso8601String(), by, userId, exceptSessionId ?? ''],
  );
  final n = db.updatedRows;
  CallSignalingRegistry.instance.closeUser(userId, exceptSessionId: exceptSessionId);
  deletePushTokensOfUser(db, userId, exceptSessionId: exceptSessionId);
  // Tokens issued before device sessions existed have no row to revoke; this
  // marker revokes them instead (checked in sessionIsActive).
  db.execute('UPDATE users SET tokens_valid_after = ? WHERE id = ?', [DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000, userId]);
  if (n > 0) {
    logSecurityEvent(db, 'session_revoked', userId: userId, ip: ip, detail: 'Thu hồi $n phiên (${by == userId ? 'người dùng' : 'admin'})');
  }
  return n;
}
