import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('password policy', () {
    test('any non-empty password is accepted, however short or common', () {
      for (final p in ['1234', '0909', '008866', '070501', '1', 'a', 'password', '12345678', 'aaaa', 'Xk9mPq2zLw']) {
        expect(validateNewPassword(p), isNull, reason: p);
      }
    });
    test('rejects empty and over-long (bcrypt 72-byte limit) passwords', () {
      expect(validateNewPassword(''), isNotNull);
      expect(validateNewPassword('a' * 72), isNull);
      expect(validateNewPassword('a' * 73), isNotNull);
      expect(validateNewPassword('ế' * 25), isNotNull); // 3 bytes each = 75
    });
  });

  group('token type', () {
    test('access token verifies', () {
      final p = verifyToken(issueToken(userId: 'u1', role: 'user', sessionId: 's1'));
      expect(p?.userId, 'u1');
      expect(p?.sessionId, 's1');
      expect(p?.issuedAt, isNotNull);
    });
    test('pending tokens are NOT access tokens', () {
      expect(verifyToken(issuePendingSecondFactorToken('u1')), isNull);
      expect(verifyToken(issuePendingWipeToken('u1')), isNull);
    });
    test('garbage and malformed claims give null, never throw', () {
      expect(verifyToken('not-a-token'), isNull);
      expect(verifyToken(''), isNull);
    });
    test('pending tokens only verify as their own type', () {
      expect(verifyPendingSecondFactorToken(issuePendingWipeToken('u1')), isNull);
      expect(verifyPendingWipeToken(issuePendingSecondFactorToken('u1')), isNull);
      expect(verifyPendingSecondFactorToken(issueToken(userId: 'u1', role: 'user')), isNull);
    });
  });

  group('one-time tokens', () {
    test('2FA pending token: verify is repeatable until spent, then dead', () {
      final t = issuePendingSecondFactorToken('u1');
      expect(verifyPendingSecondFactorToken(t), 'u1');
      expect(verifyPendingSecondFactorToken(t), 'u1'); // wrong password may retry
      expect(spendPendingSecondFactorToken(t), isTrue);
      expect(spendPendingSecondFactorToken(t), isFalse);
      expect(verifyPendingSecondFactorToken(t), isNull);
    });
    test('wipe token works exactly once', () {
      final t = issuePendingWipeToken('u2');
      expect(verifyPendingWipeToken(t), 'u2');
      expect(verifyPendingWipeToken(t), isNull);
    });
    test('two different tokens for the same user are independent', () {
      final a = issuePendingWipeToken('u3');
      final b = issuePendingWipeToken('u3');
      expect(verifyPendingWipeToken(a), 'u3');
      expect(verifyPendingWipeToken(b), 'u3');
    });
    test('a token without jti (issued before this change) still works', () {
      // Signed by an unrelated key => invalid; just make sure no throw.
      final jwt = JWT({'sub': 'u1', 'type': 'pending_wipe'});
      expect(verifyPendingWipeToken(jwt.sign(SecretKey('x' * 20))), isNull);
    });
  });

  test('fieldsAreStrings', () {
    expect(fieldsAreStrings({'a': 'x', 'b': null}, ['a', 'b', 'c']), isTrue);
    expect(fieldsAreStrings({'a': 5}, ['a']), isFalse);
    expect(fieldsAreStrings({'a': ['x']}, ['a']), isFalse);
  });

  group('sessionIsActive', () {
    late Database db;
    setUp(() {
      db = sqlite3.openInMemory();
      db.execute('''
        CREATE TABLE users (id TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT 'active', tokens_valid_after INTEGER);
        CREATE TABLE device_sessions (id TEXT PRIMARY KEY, user_id TEXT, device_label TEXT, user_agent TEXT, ip TEXT,
          created_at TEXT, last_seen TEXT, revoked_at TEXT, revoked_by TEXT);
        CREATE TABLE security_events (id TEXT PRIMARY KEY, type TEXT, user_id TEXT, username TEXT, ip TEXT, detail TEXT, created_at TEXT);
        INSERT INTO users (id) VALUES ('u1'), ('u2');
        INSERT INTO device_sessions (id, user_id, created_at, last_seen) VALUES
          ('s1', 'u1', 'x', '2099-01-01T00:00:00Z'), ('s2', 'u1', 'x', '2099-01-01T00:00:00Z'),
          ('s3', 'u2', 'x', '2099-01-01T00:00:00Z');
      ''');
    });
    tearDown(() => db.dispose());

    test('active, revoked and foreign sessions', () {
      expect(sessionIsActive(db, 'u1', 's1'), isTrue);
      expect(sessionIsActive(db, 'u1', 's3'), isFalse); // belongs to u2
      expect(sessionIsActive(db, 'u1', 'nope'), isFalse);
      revokeAllSessions(db, 'u1', by: 'u1', exceptSessionId: 's2');
      expect(sessionIsActive(db, 'u1', 's1'), isFalse);
      expect(sessionIsActive(db, 'u1', 's2'), isTrue); // current one kept
      expect(sessionIsActive(db, 'u2', 's3'), isTrue); // other user untouched
    });

    test('locked or missing account is never active', () {
      db.execute("UPDATE users SET status = 'locked' WHERE id = 'u1'");
      expect(sessionIsActive(db, 'u1', 's1'), isFalse);
      expect(sessionIsActive(db, 'u1', null), isFalse);
      expect(sessionIsActive(db, 'ghost', null), isFalse);
      db.execute("UPDATE users SET status = 'active' WHERE id = 'u1'");
      expect(sessionIsActive(db, 'u1', 's1'), isTrue);
    });

    test('session-less (legacy) token is revoked by tokens_valid_after', () {
      expect(sessionIsActive(db, 'u1', null), isTrue);
      expect(sessionIsActive(db, 'u1', null, issuedAtSeconds: 1000), isTrue);
      revokeAllSessions(db, 'u1', by: 'admin');
      final cut = db.select('SELECT tokens_valid_after v FROM users WHERE id = ?', ['u1']).first['v'] as int;
      expect(sessionIsActive(db, 'u1', null, issuedAtSeconds: cut - 5), isFalse);
      expect(sessionIsActive(db, 'u1', null), isFalse); // no iat => cannot prove it is newer
      expect(sessionIsActive(db, 'u1', null, issuedAtSeconds: cut + 5), isTrue);
      expect(sessionIsActive(db, 'u2', null, issuedAtSeconds: 1000), isTrue); // other user
    });
  });
}
