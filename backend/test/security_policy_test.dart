import 'package:server/src/reauth_limit.dart';
import 'package:server/src/security_policy.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  db.execute('CREATE TABLE login_attempts (key TEXT PRIMARY KEY, fail_count INTEGER NOT NULL DEFAULT 0, last_fail_at TEXT NOT NULL, locked_until TEXT)');
  db.execute('CREATE TABLE security_events (id TEXT PRIMARY KEY, type TEXT NOT NULL, user_id TEXT, username TEXT, ip TEXT, detail TEXT, created_at TEXT NOT NULL)');
  return db;
}

void main() {
  test('defaults equal the old hard-coded values', () {
    final p = loadPolicy(_db());
    expect([p.loginFreeAttempts, p.loginBaseLockSeconds, p.loginMaxLockSeconds, p.tokenDays, p.autoLockMinutes, p.watermarkEnabled], [5, 30, 900, 30, 0, false]);
    expect(p.screenshotGuardEnabled, true);
    expect(p.blurOnHideEnabled, true);
  });

  test('saved values are used; out-of-range stored values fall back', () {
    final db = _db();
    savePolicy(db, {'loginFreeAttempts': 3, 'tokenDays': 7, 'watermarkEnabled': true, 'autoLockMinutes': 15});
    var p = loadPolicy(db);
    expect([p.loginFreeAttempts, p.tokenDays, p.watermarkEnabled, p.autoLockMinutes], [3, 7, true, 15]);
    db.execute("INSERT OR REPLACE INTO settings VALUES ('policy.tokenDays', '99999')");
    p = loadPolicy(db);
    expect(p.tokenDays, 30);
    resetPolicy(db);
    expect(loadPolicy(db).loginFreeAttempts, 5);
  });

  test('validation', () {
    expect(validatePolicyInput({'loginFreeAttempts': 2}), isNotNull);
    expect(validatePolicyInput({'loginFreeAttempts': 21}), isNotNull);
    expect(validatePolicyInput({'tokenDays': '7'}), isNotNull);
    expect(validatePolicyInput({'watermarkEnabled': 'yes'}), isNotNull);
    expect(validatePolicyInput({'screenshotGuardEnabled': 1}), isNotNull);
    expect(validatePolicyInput({'loginBaseLockSeconds': 600, 'loginMaxLockSeconds': 300}), isNotNull);
    expect(validatePolicyInput({'loginFreeAttempts': 3, 'tokenDays': 7, 'autoLockMinutes': 0, 'watermarkEnabled': true}), isNull);
  });

  test('login lock follows the configured free tries and first lock', () {
    final db = _db();
    savePolicy(db, {'loginFreeAttempts': 3, 'loginBaseLockSeconds': 60, 'loginMaxLockSeconds': 600});
    expect(recordLoginFailure(db, 'u', '1.1.1.1'), 0);
    expect(recordLoginFailure(db, 'u', '1.1.1.1'), 0);
    expect(recordLoginFailure(db, 'u', '1.1.1.1'), 60); // 3rd wrong try locks for the first-lock time
    expect(recordLoginFailure(db, 'u', '1.1.1.1'), 120);
  });

  test('re-auth lock uses the same policy', () {
    final db = _db();
    savePolicy(db, {'loginFreeAttempts': 3, 'loginBaseLockSeconds': 45});
    expect(reauthRecordFailure(db, 'user1', 'x'), 0);
    expect(reauthRecordFailure(db, 'user1', 'x'), 0);
    expect(reauthRecordFailure(db, 'user1', 'x'), 45);
  });
}
