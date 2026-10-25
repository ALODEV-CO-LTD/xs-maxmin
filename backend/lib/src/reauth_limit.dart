import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import 'security_policy.dart';

import 'package:server/src/sessions.dart';

/// Throttling for endpoints that ask a LOGGED-IN user to re-type their
/// password (set second/wipe password, delete data, lock-screen unlock).
/// Same scheme as the login throttle in sessions.dart and stored in the same
/// `login_attempts` table (so it survives restarts) under a separate key
/// `reauth:<userId>`: 5 free wrong tries, then a lock of 30s, 60s, 120s ...
/// up to 15 min. Counted per account (not per IP) so a stolen token cannot
/// be used to guess the password by hopping IPs. A lock only delays; it never
/// deletes anything.
const _failureMemory = Duration(hours: 1);

String _key(String userId) => 'reauth:$userId|-';

int reauthLockedSecondsLeft(Database db, String userId) {
  final rows = db.select('SELECT locked_until FROM login_attempts WHERE key = ?', [_key(userId)]);
  if (rows.isEmpty) return 0;
  final until = rows.first['locked_until'] as String?;
  if (until == null) return 0;
  final left = DateTime.parse(until).difference(DateTime.now().toUtc()).inSeconds;
  return left > 0 ? left + 1 : 0;
}

/// Counts one wrong attempt; returns the lock length (seconds) if it
/// triggered a lock, else 0. Logs to security_events (never the password).
int reauthRecordFailure(Database db, String userId, String action, {String? ip}) {
  final now = DateTime.now().toUtc();
  var count = 0;
  final rows = db.select('SELECT fail_count, last_fail_at FROM login_attempts WHERE key = ?', [_key(userId)]);
  if (rows.isNotEmpty) {
    final last = DateTime.parse(rows.first['last_fail_at'] as String);
    if (now.difference(last) < _failureMemory) count = rows.first['fail_count'] as int;
  }
  count += 1;
  var lockSeconds = 0;
  String? lockedUntil;
  final policy = loadPolicy(db);
  if (count >= policy.loginFreeAttempts) {
    lockSeconds = min(policy.loginBaseLockSeconds * (1 << min(count - policy.loginFreeAttempts, 10)), policy.loginMaxLockSeconds);
    lockedUntil = now.add(Duration(seconds: lockSeconds)).toIso8601String();
  }
  db.execute(
    '''
    INSERT INTO login_attempts (key, fail_count, last_fail_at, locked_until)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET fail_count = excluded.fail_count,
      last_fail_at = excluded.last_fail_at, locked_until = excluded.locked_until
    ''',
    [_key(userId), count, now.toIso8601String(), lockedUntil],
  );
  logSecurityEvent(db, 'reauth_failed', userId: userId, ip: ip, detail: '$action: sai mật khẩu (lần $count)');
  if (lockSeconds > 0) {
    logSecurityEvent(db, 'reauth_locked', userId: userId, ip: ip, detail: '$action: khoá tạm $lockSeconds giây');
  }
  return lockSeconds;
}

int _failCount(Database db, String userId) {
  final rows = db.select('SELECT fail_count FROM login_attempts WHERE key = ?', [_key(userId)]);
  return rows.isEmpty ? 0 : rows.first['fail_count'] as int;
}

void reauthClear(Database db, String userId) {
  db.execute('DELETE FROM login_attempts WHERE key = ?', [_key(userId)]);
}

/// Checks [password] against the user's login password (and, when
/// [allowSecond], the second-layer password too) with throttling.
/// Returns null when correct (counter reset). Otherwise the response to send:
/// 429 while locked, or 403 for a wrong password - deliberately NOT 401, so
/// the client does not mistake it for an expired session and log out.
Response? checkReauthPassword(
  Database db,
  Row self,
  String? password, {
  required String action,
  String? ip,
  String wrongMessage = 'Mật khẩu hiện tại không đúng',
  bool allowSecond = false,
}) {
  final userId = self['id'] as String;
  final left = reauthLockedSecondsLeft(db, userId);
  if (left > 0) return lockedResponse(left);

  final second = self['second_password_hash'] as String?;
  final ok = password != null &&
      password.isNotEmpty &&
      (BCrypt.checkpw(password, self['password_hash'] as String) ||
          (allowSecond && second != null && BCrypt.checkpw(password, second)));
  if (ok) {
    reauthClear(db, userId);
    return null;
  }
  final lock = reauthRecordFailure(db, userId, action, ip: ip);
  if (lock > 0) return lockedResponse(lock);
  // Tell the client how it stands, so it can say "sai 3/5 lần, còn 2 lần trước khi bị khoá tạm": `failedAttempts` so far, the
  // `maxAttempts` before a lock (the policy's free tries; the last one that fails starts the lock), and `attemptsLeft`.
  final max = loadPolicy(db).loginFreeAttempts;
  final failed = _failCount(db, userId);
  return Response.json(statusCode: 403, body: {
    'error': wrongMessage,
    'failedAttempts': failed,
    'maxAttempts': max,
    'attemptsLeft': (max - failed).clamp(0, max),
  });
}
