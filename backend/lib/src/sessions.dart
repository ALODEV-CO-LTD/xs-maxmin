import 'dart:math';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart' show newId;

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

/// Remote address of the caller (the direct socket peer; X-Forwarded-For is
/// deliberately ignored so a client cannot dodge the per-IP counter by
/// spoofing it).
String clientIp(RequestContext context) {
  try {
    return context.request.connectionInfo.remoteAddress.address;
  } catch (_) {
    return 'unknown';
  }
}

// ---------------------------------------------------------------------------
// Login throttling (K03 / S03)
// ---------------------------------------------------------------------------

const _freeAttempts = 5; // wrong tries allowed before the first lock
const _baseLockSeconds = 30; // first lock; doubles with every further failure
const _maxLockSeconds = 15 * 60;
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
int recordLoginFailure(Database db, String identity, String ip, {String? userId}) {
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
  if (count >= _freeAttempts) {
    lockSeconds = min(_baseLockSeconds * (1 << min(count - _freeAttempts, 10)), _maxLockSeconds);
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
bool sessionIsActive(Database db, String userId, String? sessionId) {
  if (sessionId == null) return true;
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
  if (n > 0) {
    logSecurityEvent(db, 'session_revoked', userId: userId, ip: ip, detail: 'Thu hồi $n phiên (${by == userId ? 'người dùng' : 'admin'})');
  }
  return n;
}
